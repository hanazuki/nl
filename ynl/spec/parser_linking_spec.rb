require 'pathname'
require 'stringio'
require 'nl'
require 'ynl'

RSpec.describe Ynl::Parser, 'model linking' do
  let(:path) { Pathname(__dir__) + 'fixtures/recursive.yaml' }
  let(:parser) { described_class.new(path.read) }
  let(:family) { parser.parse }
  let(:outer) { family.attribute_sets.fetch('outer') }
  let(:inner) { family.attribute_sets.fetch('inner') }

  def expect_frozen_graph(root)
    pending = [root]
    seen = {}.compare_by_identity
    until pending.empty?
      object = pending.pop
      next if seen.key?(object)
      seen[object] = true
      expect(object).to be_frozen, "expected a frozen #{object.class}"

      case object
      when Hash
        pending.concat(object.keys).concat(object.values)
      when Array
        pending.concat(object)
      when Struct
        object.each_pair { |_, value| pending << value }
      when Data
        pending.concat(object.to_h.values)
      else
        object.instance_variables.each { pending << object.instance_variable_get(it) }
      end
    end
  end

  it 'links forward struct references to the registered object' do
    header = family.structs.fetch('header')
    expect(header.members.first.type.struct).to equal family.structs.fetch('tail')
  end

  it 'preserves object identity through self references' do
    expect(outer.attributes.first.type.attribute_set).to equal outer
  end

  it 'preserves object identity through mutual references' do
    expect(outer.attributes[1].type.attribute_set).to equal inner
    expect(inner.attributes.first.type.attribute_set).to equal outer
  end

  it 'expands a subset declared before its parent while preserving IDs' do
    selected = family.attribute_sets.fetch('selected')
    expect(selected.superset).to equal outer
    expect(selected.attributes.first).to have_attributes(name: 'child', value: 10)
    expect(selected.attributes.first.type.attribute_set).to equal inner
  end

  it 'links sub-messages and their layouts' do
    packet = family.sub_messages.fetch('packet')
    expect(outer.attributes.last.type.sub_message).to equal packet
    expect(packet.formats.first.fixed_header).to equal family.structs.fetch('header')
    expect(packet.formats.first.attribute_set).to equal family.attribute_sets.fetch('payload')
  end

  it 'links notifications to operations declared later and multicast groups' do
    notification = family.operations.fetch('changed').notification
    expect(notification.source).to equal family.operations.fetch('get')
    expect(notification.group).to equal family.mcast_groups.fetch('changes')
  end

  it 'preserves operation declaration order and IDs when constructing a source first' do
    expect(family.operations.keys).to eq %w[changed get]
    expect(family.operations.fetch('changed').notification.message.value).to eq 1
    expect(family.operations.fetch('get').doit.reply.value).to eq 2
  end

  it 'links recursion through a subset and its superset' do
    source = <<~YAML
      name: recursive-subset
      attribute-sets:
        - name: selected
          subset-of: root
          attributes:
            - { name: child }
        - name: root
          attributes:
            - { name: child, type: nest, nested-attributes: selected }
    YAML
    model = described_class.new(source).parse
    root = model.attribute_sets.fetch('root')
    selected = model.attribute_sets.fetch('selected')
    expect(model.attribute_sets.keys).to eq %w[selected root]
    expect(selected.superset).to equal root
    expect(root.attributes.first.type.attribute_set).to equal selected
    expect(selected.attributes.first.type.attribute_set).to equal selected
    expect_frozen_graph(model)
  end

  it 'links mutual recursion between sub-message formats and attribute sets' do
    source = <<~YAML
      name: recursive-sub-message
      attribute-sets:
        - name: root
          attributes:
            - { name: kind, type: string }
            - { name: payload, type: sub-message, sub-message: packet, selector: kind }
      sub-messages:
        - name: packet
          formats:
            - { value: nested, attribute-set: root }
    YAML
    model = described_class.new(source).parse
    root = model.attribute_sets.fetch('root')
    packet = model.sub_messages.fetch('packet')
    expect(root.attributes.last.type.sub_message).to equal packet
    expect(packet.formats.first.attribute_set).to equal root
    expect_frozen_graph(model)
  end

  it 'returns a Ractor-shareable graph including recursive references' do
    skip 'Ractor shareability checks are unavailable' unless defined?(Ractor) && Ractor.respond_to?(:shareable?)
    expect(Ractor.shareable?(family)).to be true
  end

  it 'deeply freezes recursive models without Ractor support' do
    parsing = parser
    hide_const('Ractor')
    expect_frozen_graph(parsing.parse)
  end

  it 'keeps mutable declarations and normalization state separate from models' do
    model = family
    declarations = parser.instance_variable_get(:@attribute_declarations)
    declaration = declarations.fetch('outer')
    normalized = parser.instance_variable_get(:@attribute_definitions).fetch('selected')

    expect(declaration).to be_a Hash
    expect(declaration.fetch('attributes').first.fetch('nested-attributes')).to eq 'outer'
    expect(normalized.first).to include('name' => 'child', 'value' => 10, 'nested-attributes' => 'inner')
    expect(declaration).not_to be_frozen

    declaration.fetch('name').replace('renamed')
    declaration.fetch('attributes').clear
    parser.instance_variable_get(:@document).dig('operations', 'list').last['flags'] = ['uns-admin-perm']

    expect(outer.name).to eq 'outer'
    expect(outer.attributes.length).to eq 4
    expect(model.operations.fetch('get').flags).to eq ['admin-perm']
    expect_frozen_graph(model)
  end

  it 'freezes models, collections, types, and string values' do
    expect { family.name = 'other' }.to raise_error(FrozenError)
    expect { family.attribute_sets.clear }.to raise_error(FrozenError)
    expect { outer.attributes.clear }.to raise_error(FrozenError)
    expect { outer.attributes.first.name.replace('other') }.to raise_error(FrozenError)
    expect { outer.attributes.first.type.attribute_set = inner }.to raise_error(FrozenError)
    expect { family.operations.fetch('get').flags << 'uns-admin-perm' }.to raise_error(FrozenError)
  end

  it 'returns the same completed model when parsed again' do
    expect(parser.parse).to equal family
  end

  it 'can generate twice from the same immutable recursive model' do
    outputs = Array.new(2) do
      StringIO.new.tap { |out| Ynl::Generator.new(family, out).generate }.string
    end
    expect(outputs.first).not_to be_empty
    expect(outputs.last).to eq outputs.first
    expect_frozen_graph(family)
  end

  it 'generates codecs that round-trip finite values through recursive schemas' do
    cls = Ynl::Family.build(path)
    attributes = cls::AttributeSets::Outer.build_instance({ encap: { child: { parent: {} } } })
    encoded = Nl::Encoder.new
    attributes.encode(encoded)

    decoded = cls::AttributeSets::Outer.decode(Nl::Decoder.new(encoded.buffer))
    expect(decoded.encap.child.parent).to be_a cls::AttributeSets::Outer
    reencoded = Nl::Encoder.new
    decoded.encode(reencoded)
    expect(reencoded.buffer.get_string).to eq encoded.buffer.get_string
  end

  it 'deeply freezes models for every existing parser fixture' do
    Pathname(__dir__).glob('fixtures/*.yaml').each do |fixture|
      expect_frozen_graph(described_class.parse_file(fixture))
    end
  end

  it 'reuses shared string arrays in YAML aliases and inherited attributes' do
    source = <<~YAML
      name: shared-arrays
      attribute-sets:
        - name: outer
          attributes:
            - { name: child, type: nest-type-value, nested-attributes: inner, type-value: [index] }
        - name: selected
          subset-of: outer
          attributes:
            - { name: child }
        - name: inner
          attributes: []
      operations:
        list:
          - name: first
            attribute-set: outer
            flags: &flags [admin-perm]
            do:
              request:
                attributes: &attributes [child]
              reply:
                attributes: *attributes
          - name: second
            attribute-set: outer
            flags: *flags
            do:
              request:
                attributes: *attributes
    YAML
    model = described_class.new(source).parse
    first = model.operations.fetch('first')
    second = model.operations.fetch('second')
    expect(first.flags).to equal second.flags
    expect(first.doit.request.attributes).to equal first.doit.reply.attributes
    expect(first.doit.request.attributes).to equal second.doit.request.attributes
    original = model.attribute_sets.fetch('outer').attributes.first.type.type_values
    inherited = model.attribute_sets.fetch('selected').attributes.first.type.type_values
    expect(original).to equal inherited
    expect_frozen_graph(model)
  end

  it 'rejects missing targets during parsing' do
    source = <<~YAML
      name: invalid
      attribute-sets:
        - name: outer
          attributes:
            - { name: child, type: nest, nested-attributes: missing }
    YAML
    expect { described_class.new(source).parse }
      .to raise_error(Ynl::ParseError, /attribute child: Unknown attribute set: missing/)
  end

  it 'rejects duplicate named objects' do
    source = <<~YAML
      name: invalid
      attribute-sets:
        - { name: duplicate, attributes: [] }
        - { name: duplicate, attributes: [] }
    YAML
    expect { described_class.new(source).parse }
      .to raise_error(Ynl::ParseError, /Duplicate AttributeSet: duplicate/)
  end

  it 'rejects subset inheritance cycles separately from valid nesting recursion' do
    source = <<~YAML
      name: invalid
      attribute-sets:
        - { name: a, subset-of: b, attributes: [] }
        - { name: b, subset-of: a, attributes: [] }
    YAML
    expect { described_class.new(source).parse }
      .to raise_error(Ynl::ParseError, /subset inheritance cycle: a -> b -> a/)
  end

  it 'reports cyclic notification sources' do
    source = <<~YAML
      name: cyclic-notifications
      attribute-sets: []
      operations:
        list:
          - { name: first, notify: second }
          - { name: second, notify: first }
    YAML
    expect { described_class.new(source).parse }
      .to raise_error(Ynl::ParseError, 'Notification source cycle: first -> second -> first')
  end
end
