require 'nl'

RSpec.describe Nl::AttributeSet do
  let(:attribute_set) do
    Class.new(described_class).tap do |set|
      datatype = Nl::DataTypes::Scalar[Nl::Endian::Host::U32].new
      singular = Nl::AttributeSet::Definition.new(id: 1, name: :singular, datatype:)
      repeated = Nl::AttributeSet::Definition.new(id: 2, name: :repeated, datatype:, multi: true)

      set.const_set(:Singular, singular)
      set.const_set(:Repeated, repeated)
      set.const_set(:BY_NAME, {singular:, repeated:}.freeze)
      definitions = {1 => singular, 2 => repeated}.freeze
      set.const_set(:BY_TYPE, definitions)
      set.define_singleton_method(:decode) do |decoder, external_selectors: Nl::Selector::EMPTY_VALUES|
        super(decoder, definitions, 0, external_selectors)
      end
      set.define_singleton_method(:by_name) { const_get(:BY_NAME, false).fetch(it) }
      set.define_singleton_method(:by_type) { const_get(:BY_TYPE, false).fetch(it) }
    end
  end

  it 'builds, encodes, and decodes repeated attributes in order' do
    attributes = attribute_set.build_instance({ singular: 10, repeated: [20, 30] })
    encoder = Nl::Encoder.new

    attributes.encode(encoder)
    decoded = attribute_set.decode(Nl::Decoder.new(encoder.buffer))

    expect(decoded[:singular]).to eq 10
    expect(decoded[2]).to eq [20, 30]
  end

  it 'returns an empty array when a repeated attribute is absent' do
    attributes = attribute_set.build_instance({ singular: 10 })

    expect(attributes[:repeated]).to eq []
  end

  it 'requires an array when building a repeated attribute' do
    expect { attribute_set.build_instance({ repeated: 20 }) }
      .to raise_error(TypeError, 'value for multi-attribute repeated must be an Array')
  end

  it 'retains singular lookup behavior' do
    attributes = attribute_set.new
    attributes.append_attribute(:singular, 10)
    attributes.append_attribute(:singular, 20)

    expect(attributes[:singular]).to eq 10
  end

  it 'preserves repeated and duplicate singular values when re-encoding' do
    bytes = [8, 1, 10, 8, 2, 20, 8, 2, 30, 8, 1, 40].pack('SSL' * 4)
    attributes = attribute_set.decode(Nl::Decoder.new(IO::Buffer.for(bytes)))
    encoder = Nl::Encoder.new

    attributes.encode(encoder)

    expect(attributes[:singular]).to eq(10)
    expect(attributes[:repeated]).to eq([20, 30])
    expect(encoder.buffer.get_string).to eq(bytes)
  end

  it 'skips unknown attributes without losing subsequent values' do
    bytes = [8, 99, 123, 8, 1, 10].pack('SSL' * 2)

    attributes = attribute_set.decode(Nl::Decoder.new(IO::Buffer.for(bytes)))

    expect(attributes[:singular]).to eq(10)
    expect(attributes[:repeated]).to eq([])
  end

  it 'shares immutable schema definitions between attribute sets' do
    definition = attribute_set.by_name(:singular)

    expect(definition).to equal(attribute_set.by_type(1))
    expect(definition).to be_a(Nl::AttributeSet::Definition)
    expect(definition).to be_frozen
    expect(definition.datatype).to be_a(Nl::DataTypes::Scalar[Nl::Endian::Host::U32])
    expect(definition.id).to eq(1)
    expect(definition.name).to eq(:singular)
  end

  it 'retains false and nil values when appending' do
    attributes = attribute_set.new
    attributes.append_attribute(:singular, false)
    attributes.append_attribute(:repeated, nil)
    attributes.append_attribute(:repeated, false)

    expect(attributes[:singular]).to be(false)
    expect(attributes[:repeated]).to eq([nil, false])
  end

  it 'returns nil for an absent singular attribute' do
    expect(attribute_set.new[:singular]).to be_nil
  end

  it 'rejects an attribute shorter than its header' do
    encoder = Nl::Encoder.new
    encoder.put_value(Nl::Endian::Host::U16, Nl::Raw::NLA_HDRLEN - 1)
    encoder.put_value(Nl::Endian::Host::U16, 1)

    expect { attribute_set.decode(Nl::Decoder.new(encoder.buffer)) }.to raise_error(
      Nl::Decoder::Error,
      'attribute length must be at least 4 bytes, got 3',
    )
  end
end
