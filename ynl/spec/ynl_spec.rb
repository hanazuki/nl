require 'pathname'
require 'stringio'

require 'nl'

RSpec.describe Ynl do
  let(:yaml) { Pathname(__dir__) + 'fixtures/conntrack.yaml' }

  describe Ynl::Parser do
    let(:parser) do
      yaml.open {|f| Ynl::Parser.new(f) }
    end

    example do
      family = parser.parse

      aggregate_failures do
        expect(family.name).to eq 'conntrack'
        expect(family.protonum).to eq 12
      end
    end
  end

  describe Ynl::Family do
    it 'allows an attribute named external_selectors in from_params' do
      source = <<~YAML
        name: constructor-keywords
        protocol: genetlink
        attribute-sets:
          - name: attrs
            attributes:
              - {name: external-selectors, type: u32}
        operations:
          list:
            - name: echo
              attribute-set: attrs
              do:
                request:
                  attributes: [external-selectors]
      YAML
      generated = StringIO.new
      Ynl::Family.generate(source, generated)
      scope = Module.new
      scope.module_eval(generated.string)
      klass = scope::ConstructorKeywords::Messages::DoEchoRequest

      message = klass.from_params(external_selectors: 42)
      encoder = Nl::Encoder.new
      message.encode(encoder)
      decoded = klass.decode(Nl::Decoder.new(encoder.buffer))

      expect(decoded.external_selectors).to eq(42)
    end

    %w[netlink-raw genetlink].each do |wire_protocol|
      context "with generated #{wire_protocol} message decoders" do
        let(:generated) { StringIO.new }
        let(:family_class) do
          source = <<~YAML
            name: payload-codec
            protocol: #{wire_protocol}
            #{wire_protocol == 'netlink-raw' ? 'protonum: 0' : 'version: 1'}
            definitions:
              - name: header
                type: struct
                members:
                  - {name: tag, type: u32}
            attribute-sets:
              - name: attrs
                attributes:
                  - {name: value, type: u32}
            operations:
              list:
                - name: echo
                  value: 24
                  fixed-header: header
                  attribute-set: attrs
                  do:
                    request:
                      attributes: [value]
                    reply:
                      attributes: [value]
                - name: no-header
                  value: 25
                  attribute-set: attrs
                  do:
                    reply:
                      attributes: [value]
          YAML
          Ynl::Family.generate(StringIO.new(source), generated)
          Module.new.module_eval(generated.string + "\nPayloadCodec")
        end
        let(:message_class) { family_class::Messages::DoEchoReply }

        it 'names positional constructor parameters after the fixed-header fields' do
          expect(message_class.instance_method(:initialize).parameters).to eq(
            [[:req, :tag], [:opt, :attributes]],
          )
          expect(message_class.new(7, [1, 42])).to have_attributes(tag: 7, value: 42)
        end

        it 'round-trips the family payload through the protocol' do
          expect(message_class.superclass).to equal(Nl::Message)
          message = message_class.from_params(tag: 7, value: 42)
          if wire_protocol == 'netlink-raw'
            protocol = Nl::Raw::Protocol.new(0)
            endpoint = Nl::Raw::Endpoint.new(family_class)
          else
            protocol = Nl::Genl::Protocol.new
            info = Nl::Genl::FamilyInfo.new(id: 42, multicast_groups: {})
            endpoint = Nl::Genl::Endpoint.new(family_class, info)
          end
          request = Nl::Raw::Request.new(type: endpoint.frame_type(message_class), flags: 0, message:)
          encoder = Nl::Encoder.new
          protocol.encode_message(encoder, endpoint, request, seq: 1, pid: 77)
          decoder = Nl::Decoder.new(encoder.buffer)
          header = Nl::Raw::NlMsgHdr.decode(decoder)

          decoded = protocol.decode_frame(endpoint, header, decoder, message_class)

          expect(decoded).to have_attributes(tag: 7, value: 42)
          expect(decoder.remaining).to eq(0)
        end

        it 'decodes payloads directly without protocol headers or a type argument' do
          message = message_class.from_params(tag: 7, value: 42)
          encoder = Nl::Encoder.new
          message.encode(encoder)

          decoded = message_class.decode(Nl::Decoder.new(encoder.buffer))

          expect(decoded).to have_attributes(tag: 7, value: 42)
        end

        it 'stores header fields and ordered attribute values in the message itself' do
          encoder = Nl::Encoder.new
          message_class.from_params(tag: 7, value: 42).encode(encoder)
          decoded = message_class.decode(Nl::Decoder.new(encoder.buffer))

          expect(decoded.instance_variables).to contain_exactly(:@tag, :@attributes)
          expect(decoded.instance_variable_get(:@tag)).to eq(7)
          expect(decoded.instance_variable_get(:@attributes)).to eq([1, 42])
          expect(message_class::BY_TYPE).to equal(family_class::AttributeSets::Attrs::BY_TYPE)

          decoded.append_attribute(:value, 99)
          encoded = Nl::Encoder.new
          decoded.encode(encoded)
          round_trip = message_class.decode(Nl::Decoder.new(encoded.buffer))

          expect(round_trip.value).to eq(42)
          expect(round_trip.instance_variable_get(:@attributes)).to eq([1, 42, 1, 99])
        end

        it 'decodes messages with no family-specific fixed header' do
          klass = family_class::Messages::DoNoHeaderReply
          encoder = Nl::Encoder.new
          klass.from_params(value: 42).encode(encoder)

          decoded = klass.decode(Nl::Decoder.new(encoder.buffer))

          expect(decoded.instance_variables).to eq([:@attributes])
          expect(decoded.value).to eq(42)
        end

        it 'inherits the generated layout without looking up subclass constants' do
          subclass = Class.new(message_class)
          subclass.const_set(:FIXED_HEADER, nil)
          subclass.const_set(:ATTRIBUTE_SET, nil)
          subclass.const_set(:BY_TYPE, [].freeze)
          encoder = Nl::Encoder.new
          message_class.from_params(tag: 7, value: 42).encode(encoder)

          decoded = subclass.decode(Nl::Decoder.new(encoder.buffer))

          expect(decoded).to be_a(subclass)
          expect(decoded).to have_attributes(tag: 7, value: 42)
        end
      end
    end

    it 'generates and round-trips statically selected sub-messages' do
      path = Pathname(__dir__) + 'fixtures/sub_messages.yaml'
      generated = StringIO.new
      path.open { |source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)
      expect(cls::SubMessages::PayloadMessage::Foo).to be < Nl::Message

      attributes = cls::AttributeSets::OuterAttrs.build_instance({
        child: {leaf: {data: {header_value: 7, payload_value: 11}}},
        kind: 'foo',
      })
      encoder = Nl::Encoder.new
      attributes.encode(encoder)
      decoded = cls::AttributeSets::OuterAttrs.decode(Nl::Decoder.new(encoder.buffer))
      data = decoded.child.leaf.data

      expect(data).to be_a(cls::SubMessages::PayloadMessage::Foo)
      expect(data).to have_attributes(header_value: 7, payload_value: 11)
      expect(encoder.buffer.get_value(Nl::Endian::Host::U16, 2)).to eq(1)
      expect(generated.string).to include('::Nl::Selector::External.new(0)')
      expect(generated.string).to include('selector_bindings: [::Nl::Selector::Local.new(0)]')
      expect(generated.string).to include('selector_bindings: [::Nl::Selector::External.new(0)]')
      expect(cls::AttributeSets::OuterAttrs.by_name(:kind).selector_slot).to eq(0)
      expect(cls::AttributeSets::OuterAttrs::LOCAL_SELECTOR_NAMES).to eq([:kind])
      expect(cls::AttributeSets::OuterAttrs::LOCAL_SELECTOR_NAMES).to be_frozen
      expect(cls::AttributeSets::OuterAttrs::EXTERNAL_SELECTOR_NAMES).to equal(Nl::AttributeSet::EXTERNAL_SELECTOR_NAMES)
      expect(cls::AttributeSets::ChildAttrs::LOCAL_SELECTOR_NAMES).to equal(Nl::AttributeSet::LOCAL_SELECTOR_NAMES)
      expect(cls::AttributeSets::ChildAttrs::EXTERNAL_SELECTOR_NAMES).to eq([:kind])
      expect(cls::AttributeSets::ChildAttrs::EXTERNAL_SELECTOR_NAMES).to be_frozen
      expect(generated.string).not_to include('SELECTOR_SLOTS_BY_')
      expect(generated.string).to include('# @rbs return: AttributeSets::ChildAttrs')
      expect(generated.string).to include('def child; self[:"child"]; end')
      expect(generated.string).to include(
        '# @rbs return: SubMessages::PayloadMessage::Foo | SubMessages::PayloadMessage::Bar | ::Nl::RawAttributeValue',
      )
      expect(generated.string).to include('def data; self[:"data"]; end')
    end

    it 'decodes an empty sub-message format' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/sub_messages.yaml')
      klass = cls::SubMessages::PayloadMessage::Bar
      decoder = Nl::Decoder.new(IO::Buffer.for(''))

      decoded = klass.decode(decoder)

      expect(decoded).to be_a(klass)
      expect(decoded.instance_variables).to be_empty
    end

    it 'inherits the generated sub-message layout without looking up subclass constants' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/sub_messages.yaml')
      klass = cls::SubMessages::PayloadMessage::Foo
      subclass = Class.new(klass)
      subclass.const_set(:FIXED_HEADER, nil)
      subclass.const_set(:ATTRIBUTE_SET, nil)
      subclass.const_set(:BY_TYPE, [].freeze)
      encoder = Nl::Encoder.new
      klass.from_params(header_value: 7, payload_value: 42).encode(encoder)

      decoded = subclass.decode(Nl::Decoder.new(encoder.buffer))

      expect(decoded).to be_a(subclass)
      expect(decoded).to have_attributes(header_value: 7, payload_value: 42)
    end

    it 'compiles enum selector names to their integer values' do
      path = Pathname(__dir__) + 'fixtures/sub_messages.yaml'
      generated = StringIO.new
      path.open { |source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)

      attributes = cls::AttributeSets::EnumAttrs.build_instance({
        data: {header_value: 3, payload_value: 5},
        kind: 10,
      })
      encoder = Nl::Encoder.new
      attributes.encode(encoder)
      decoded = cls::AttributeSets::EnumAttrs.decode(Nl::Decoder.new(encoder.buffer))

      expect(decoded[:data]).to have_attributes(header_value: 3, payload_value: 5)
      expect(encoder.buffer.get_value(Nl::Endian::Host::U16, 2)).to eq(
        cls::AttributeSets::EnumAttrs.by_name(:kind).id,
      )
      expect(cls::AttributeSets::EnumAttrs.by_name(:kind).order).to eq(0)
      expect(cls::AttributeSets::EnumAttrs.by_name(:data).order).to eq(1)
      expect(generated.string).to include('10 => ::Nl::DataTypes::SubMessage::Format.new')
      expect(generated.string).to include('20 => ::Nl::DataTypes::SubMessage::Format.new')
    end

    it 'rejects a sub-message whose selector has not appeared on the wire' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/sub_messages.yaml')
      encoded = Nl::Encoder.new
      attrs = cls::AttributeSets::EnumAttrs.build_instance({
        kind: 10,
        data: {header_value: 3, payload_value: 5},
      })
      attrs[:data].then do |data|
        encoded.measure(Nl::Endian::Host::U16) do
          encoded.put_value(Nl::Endian::Host::U16, 0)  # nla_len
          encoded.put_value(Nl::Endian::Host::U16, cls::AttributeSets::EnumAttrs.by_name(:data).id | Nl::Raw::NLA_F_NESTED)  # nla_type
          data.encode(encoded)
        end
        encoded.align_to_4  # NLA_ALIGNTO
      end

      expect do
        cls::AttributeSets::EnumAttrs.decode(Nl::Decoder.new(encoded.buffer))
      end.to raise_error(
        Nl::Decoder::Error,
        'selector :kind must precede the dependent attribute',
      )

      expect do
        cls::AttributeSets::LeafAttrs.decode(Nl::Decoder.new(encoded.buffer))
      end.to raise_error(
        Nl::Decoder::Error,
        'selector :kind must precede the dependent attribute',
      )

      expect do
        cls::AttributeSets::LeafAttrs.new([1, attrs[:data]]).encode(Nl::Encoder.new)
      end.to raise_error(
        ArgumentError,
        'selector :kind is required by a dependent attribute',
      )

      expect do
        cls::AttributeSets::LeafAttrs.build_instance({
          data: {header_value: 3, payload_value: 5},
        })
      end.to raise_error(
        ArgumentError,
        'selector :kind is required by a dependent attribute',
      )
    end

    it 'preserves an unknown sub-message format as raw data' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/sub_messages.yaml')
      raw = Nl::RawAttributeValue.new(
        "\x01\x02\x03\x04".b,
        nlattr_type_flags: Nl::Raw::NLA_F_NESTED,
      )
      attributes = cls::AttributeSets::EnumAttrs.build_instance({ kind: 99, data: raw })
      encoded = Nl::Encoder.new
      attributes.encode(encoded)

      decoded = cls::AttributeSets::EnumAttrs.decode(Nl::Decoder.new(encoded.buffer))
      value = decoded[:data]
      reencoded = Nl::Encoder.new
      decoded.encode(reencoded)

      expect(value).to be_a(Nl::RawAttributeValue)
      expect(value.payload).to eq("\x01\x02\x03\x04".b)
      expect(value.nlattr_type_flags).to eq(Nl::Raw::NLA_F_NESTED)
      expect(reencoded.buffer.get_string).to eq(encoded.buffer.get_string)
    end

    it 'allows raw data after its selector format becomes known' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/sub_messages.yaml')
      raw = Nl::RawAttributeValue.new(
        "\x01\x02\x03\x04".b,
        nlattr_type_flags: Nl::Raw::NLA_F_NESTED,
      )

      attributes = cls::AttributeSets::EnumAttrs.build_instance({ kind: 10, data: raw })
      encoder = Nl::Encoder.new

      expect { attributes.encode(encoder) }.not_to raise_error
    end

    it 'encodes and decodes fixed-size binary and nested struct members' do
      path = Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml'
      generated = StringIO.new
      path.open { |source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)
      inner = cls::Structs::Inner.new(0x0504)
      outer = cls::Structs::Outer.new(1, "\x02\x03\x04".b, inner, 6)
      encoder = Nl::Encoder.new

      outer.encode(encoder)
      decoded = cls::Structs::Outer.decode(Nl::Decoder.new(encoder.buffer))

      expect(encoder.buffer.get_string).to eq("\x01\x02\x03\x04\x04\x05\x06".b)
      expect(decoded).to eq(outer)
      expect(generated.string).to include(':"inner", #: Structs::Inner')
      expect(generated.string).to include('bytes: ::Nl::DataTypes::Binary.new(length: 3)')
      expect(generated.string).to include('inner: ::Nl::DataTypes::Struct.new(Structs::Inner)')
      expect(generated.string).to include('decoder.get_host_u8')
      expect(generated.string).to include('MEMBERS[:"prefix"].encode(encoder, public_send(:"prefix"))')
      expect(generated.string).to include('MEMBERS[:"prefix"].coerce(params.fetch(:"prefix", 0), context:)')
      expect(generated.string).not_to include('.map {|name, datatype|')
      expect(generated.string).not_to include('.each {|name, datatype|')
    end

    it 'defaults omitted numeric struct members at construction and rejects explicit nil on encoding' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      record = cls::Structs::Inner.from_params({})
      encoder = Nl::Encoder.new

      expect(record.value).to eq(0)
      record.encode(encoder)
      expect(encoder.buffer.get_string).to eq("\0\0".b)
      expect { cls::Structs::Inner.from_params({value: nil}).encode(Nl::Encoder.new) }
        .to raise_error(TypeError)
    end

    it 'preserves scalar widths, signedness, and byte order in generated structs' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      values = [0xfedcba98, 254, -3, 0xfedc, -1234, 0xfedcba98,
                -123456, 0xfedcba9876543210, -123456789012345, -42]
      bytes = values.pack('LCcS<s>L>l< Q<q>i!')
      encoder = Nl::Encoder.new

      cls::Structs::Scalars.new(*values).encode(encoder)
      decoder = Nl::Decoder.new(IO::Buffer.for(bytes))

      expect(encoder.buffer.get_string).to eq(bytes)
      expect(cls::Structs::Scalars.decode(decoder).to_a).to eq(values)
      expect(decoder.remaining).to eq(0)
      expect { cls::Structs::Scalars.decode(Nl::Decoder.new(IO::Buffer.for(bytes.chop))) }
        .to raise_error(Nl::Decoder::OutOfBounds)
    end

    it 'decodes grouped small integers with signed and mixed-endian fields' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      values = [255, -128, 128, -1, 0xfedc, -32768, 254, -1234, 253, 252]
      bytes = values.pack('CcCcSsCs>CC')
      decoder = Nl::Decoder.new(IO::Buffer.for(bytes))
      expect(decoder).to receive(:get_u32).exactly(3).times.and_call_original

      expect(cls::Structs::Grouped.decode(decoder).to_a).to eq(values)
      expect(decoder.remaining).to eq(0)
    end

    it 'reads two adjacent u8 fields with a single u16 load' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      decoder = Nl::Decoder.new(IO::Buffer.for([0x81, 0xfe].pack('CC')))
      expect(decoder).to receive(:get_u16).once.and_call_original

      expect(cls::Structs::BytePair.decode(decoder).to_h).to eq(flags: 0x81, mask: 0xfe)
      expect(decoder.remaining).to eq(0)
    end

    it 'uses a u16 load for a byte pair followed by one leftover byte' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      decoder = Nl::Decoder.new(IO::Buffer.for([-128, 0xfe, 0xff].pack('cCC')))
      expect(decoder).to receive(:get_u16).once.and_call_original

      expect(cls::Structs::ThreeBytes.decode(decoder).to_a).to eq([-128, 0xfe, 0xff])
      expect(decoder.remaining).to eq(0)
    end

    it 'ignores padding in a grouped u16 load' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      decoder = Nl::Decoder.new(IO::Buffer.for([0x81, 0xff].pack('CC')))
      expect(decoder).to receive(:get_u16).once.and_call_original

      expect(cls::Structs::PaddedByte.decode(decoder).to_h).to eq(value: 0x81)
      expect(decoder.remaining).to eq(0)
    end

    it 'rejects a grouped read crossing the decoder limit' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      decoder = Nl::Decoder.new(IO::Buffer.for("\0" * 13))

      expect do
        decoder.limit(3) { cls::Structs::Grouped.decode(decoder) }
      end.to raise_error(Nl::Decoder::OutOfBounds)
    end

    it 'retains variable-width integer encoding in struct members' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')

      [42, 0xffffffffffffffff].zip([4, 8]).each do |value, size|
        encoder = Nl::Encoder.new
        cls::Structs::VariableInteger.new(value).encode(encoder)

        expect(encoder.position).to eq(size)
        expect(cls::Structs::VariableInteger.decode(Nl::Decoder.new(encoder.buffer)).value).to eq(value)
      end
    end

    it 'preserves padding between generated scalar fields' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      record = cls::Structs::Padded.from_params({prefix: 1, suffix: 0x12345678})
      encoder = Nl::Encoder.new

      record.encode(encoder)

      expect(encoder.buffer.get_string).to eq([1, 0x12345678].pack('Cx3L'))
      expect(cls::Structs::Padded.members).to eq([:prefix, :suffix])
      expect(cls::Structs::Padded::MEMBERS.keys).to eq([:prefix, :suffix])
      expect(cls::Structs::Padded.decode(Nl::Decoder.new(encoder.buffer))).to eq(record)
    end

    it 'ignores nonzero padding inside a grouped u32 read' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      bytes = [0x12, 0xff, 0x3456].pack('CCS')
      decoder = Nl::Decoder.new(IO::Buffer.for(bytes))
      expect(decoder).to receive(:get_u32).once.and_call_original

      record = cls::Structs::InternalPad.decode(decoder)

      expect(record.to_h).to eq(prefix: 0x12, suffix: 0x3456)
      encoder = Nl::Encoder.new
      record.encode(encoder)
      expect(encoder.buffer.get_string).to eq([0x12, 0x3456].pack('CxS'))
    end

    it 'skips padding outside grouped reads without exposing a field' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      bytes = "\xff" * 5 + [0x12345678].pack('L') + "\xff\xff"

      record = cls::Structs::UngroupedPad.decode(Nl::Decoder.new(IO::Buffer.for(bytes)))

      expect(record.to_h).to eq(value: 0x12345678)
      encoder = Nl::Encoder.new
      record.encode(encoder)
      expect(encoder.buffer.get_string).to eq([0x12345678].pack('x5Lx2'))
    end

    it 'generates an empty Struct for a padding-only layout' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      record = cls::Structs::OnlyPad.from_params({})
      encoder = Nl::Encoder.new

      record.encode(encoder)

      expect(record.to_h).to eq({})
      expect(encoder.buffer.get_string).to eq("\0\0")
      expect(cls::Structs::OnlyPad.decode(Nl::Decoder.new(encoder.buffer))).to eq(record)
    end

    it 'encodes and decodes structured binary attributes' do
      path = Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml'
      generated = StringIO.new
      path.open { |source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)
      values = {
        prefix: 1,
        bytes: "\x02\x03\x04".b,
        inner: {value: 0x0504},
        suffix: 6,
      }
      attributes = cls::AttributeSets::Attrs.build_instance({ record: values })
      encoder = Nl::Encoder.new

      attributes.encode(encoder)
      decoded = cls::AttributeSets::Attrs.decode(Nl::Decoder.new(encoder.buffer))[:record]

      expect(decoded).to be_a(cls::Structs::Outer)
      expect(decoded).to have_attributes(prefix: 1, bytes: "\x02\x03\x04".b, suffix: 6)
      expect(decoded.inner).to eq(cls::Structs::Inner.new(0x0504))
      expect(generated.string).to include(
        '::Nl::DataTypes::CheckedPayload.new(::Nl::DataTypes::Struct.new(Structs::Outer, consume_remaining: true), check:',
      )
      expect(generated.string).to include(
        '?record: (Structs::Outer | ::Hash[::Symbol, untyped])',
      )
      expect(generated.string).to include('# @rbs return: Structs::Outer')
    end

    it 'ignores extension bytes after a structured binary attribute' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      outer = cls::Structs::Outer.new(
        1,
        "\x02\x03\x04".b,
        cls::Structs::Inner.new(0x0504),
        6,
      )
      encoder = Nl::Encoder.new
      encoder.measure(Nl::Endian::Host::U16) do
        encoder.put_value(Nl::Endian::Host::U16, 0)  # nla_len
        encoder.put_value(Nl::Endian::Host::U16, 2)  # nla_type
        outer.encode(encoder)
        encoder.put_string("\xaa\xbb".b)
      end
      encoder.align_to_4  # NLA_ALIGNTO

      attributes = cls::AttributeSets::Attrs.decode(Nl::Decoder.new(encoder.buffer))

      expect(attributes[:extensible_record]).to eq(outer)
    end

    it 'rejects incorrectly sized fixed binary struct members' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/fixed_struct_members.yaml')
      outer = cls::Structs::Outer.new(1, "\x02\x03".b, cls::Structs::Inner.new(4), 5)

      expect { outer.encode(Nl::Encoder.new) }.to raise_error(
        ArgumentError,
        'binary value must be exactly 3 bytes, got 2',
      )
    end

    it 'generates variable-width integer datatypes for uint and sint attributes' do
      source = StringIO.new(<<~YAML)
        name: variable-integers
        protocol: genetlink
        doc: Variable-width integer test family.
        attribute-sets:
          -
            name: attrs
            attributes:
              - { name: unsigned, type: uint }
              - { name: signed, type: sint }
        operations:
          list: []
      YAML
      generated = StringIO.new

      Ynl::Family.generate(source, generated)

      expect(generated.string).to include(
        '::Nl::DataTypes::VariableInteger.new(::Nl::Endian::Host, signed: false)',
      )
      expect(generated.string).to include(
        '::Nl::DataTypes::VariableInteger.new(::Nl::Endian::Host, signed: true)',
      )
    end

    it 'generates Bitfield32 APIs for bitfield32 attributes' do
      source = StringIO.new(<<~YAML)
        name: bitfields
        protocol: genetlink
        attribute-sets:
          -
            name: attrs
            attributes:
              - { name: flags, type: bitfield32 }
        operations:
          list:
            -
              name: set
              attribute-set: attrs
              do:
                request:
                  attributes: [flags]
      YAML
      generated = StringIO.new

      Ynl::Family.generate(source, generated)

      expect(generated.string).to include('datatype: ::Nl::DataTypes::Bitfield32.new')
      expect(generated.string).to include('?flags: ::Nl::Bitfield32')
      expect(generated.string).to include('# @rbs return: ::Nl::Bitfield32')
    end

    it 'generates packed-array datatypes for binary attributes with sub-types' do
      source = StringIO.new(<<~YAML)
        name: packed-arrays
        protocol: genetlink
        attribute-sets:
          -
            name: attrs
            attributes:
              - { name: values, type: binary, sub-type: u32, byte-order: big-endian }
        operations:
          list:
            -
              name: set
              attribute-set: attrs
              do:
                request:
                  attributes: [values]
      YAML
      generated = StringIO.new

      Ynl::Family.generate(source, generated)

      expect(generated.string).to include(
        '::Nl::DataTypes::PackedArray.new(::Nl::DataTypes::Scalar[::Nl::Endian::Big::U32].new)',
      )
      expect(generated.string).to include('values: ::Array[::Integer]')
    end

    it 'exposes definitions and uses them in attribute checks' do
      path = Pathname(__dir__) + 'fixtures/constants.yaml'
      generated = StringIO.new
      path.open {|source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)

      expect(cls::Constants::TEST_MAXIMUM_LENGTH).to eq 4
      expect(cls::Constants::DISPLAY_NAME).to eq 'a "quoted" value'
      expect(generated.string).to include(
        'unless it.bytesize <= Constants::TEST_MAXIMUM_LENGTH',
      )
      expect do
        attributes = cls::AttributeSets::Attrs.build_instance({ payload: '12345' })
        attributes.encode(Nl::Encoder.new)
      end.to raise_error(ArgumentError, 'Value "12345" is longer than maximum length 4')
    end

    it 'exposes enums and flags as namespaced constants' do
      path = Pathname(__dir__) + 'fixtures/enums_flags.yaml'
      generated = StringIO.new
      path.open { |source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)

      expect(cls.name).to match(/::FooFamily\z/)
      expect(cls::Enums::EnumName::MemberName).to eq 3
      expect(cls::Enums::EnumName::ExplicitMember).to eq 7
      expect(cls::Flags::EnumName::MemberName).to eq 8
      expect(cls::Flags::EnumName::ExplicitMember).to eq 128
      expect(cls::Flags::FlagName::FirstFlag).to eq 1
      expect(cls::Flags::FlagName::LaterFlag).to eq 16
      expect(cls::Enums::PlainEnum::Only).to eq 0
      expect(cls::Flags.const_defined?(:PlainEnum, false)).to be false
      expect(generated.string.scan('module EnumName').length).to eq 2
      expect(generated.string).to include('# An explicitly numbered member.')
      expect(generated.string).to include('# A flag with an explicit bit position.')
    end

    it 'retains valid accessors for attribute names starting with a digit' do
      source = <<~YAML
        name: numbered-attributes
        protocol: genetlink
        attribute-sets:
          - name: attrs
            attributes:
              - name: 3-way
                type: u32
      YAML
      generated = StringIO.new
      Ynl::Family.generate(StringIO.new(source), generated)
      scope = Module.new
      scope.module_eval(generated.string)
      attrs = scope::NumberedAttributes::AttributeSets::Attrs

      values = attrs.build_instance({ x_3_way: 42 })

      expect(values.x_3_way).to eq(42)
      expect(attrs.by_name(:x_3_way)).to equal(attrs.by_type(1))
      expect(attrs.by_type(1).name).to eq(:x_3_way)
      expect(attrs.const_defined?(:X3Way, false)).to be(false)
    end

    describe 'numeric attribute lookup tables' do
      let(:attrs) do
        source = <<~YAML
          name: sparse-attributes
          protocol: genetlink
          attribute-sets:
            - name: attrs
              attributes:
                - {name: first, type: u32}
                - {name: last, type: u32, value: 2048}
            - name: empty
              attributes: []
        YAML
        generated = StringIO.new
        Ynl::Family.generate(source, generated)
        scope = Module.new
        scope.module_eval(generated.string)
        scope::SparseAttributes::AttributeSets
      end

      it 'uses a frozen array including gaps and high IDs' do
        table = attrs::Attrs::BY_TYPE

        expect(table).to be_an(Array)
        expect(table).to be_frozen
        expect(table.length).to eq(2049)
        expect(table[2]).to be_nil
        expect(attrs::Attrs.by_type(2048)).to equal(attrs::Attrs.by_name(:last))
        [0, 2, 2049, -1].each do |id|
          expect { attrs::Attrs.by_type(id) }.to raise_error(KeyError)
        end
      end

      it 'skips unknown IDs within and beyond the array without losing known values' do
        bytes = [8, 2, 10, 8, 2049, 20, 8, 2048, 30, 8, 1, 40].pack('SSL' * 4)
        values = attrs::Attrs.decode(Nl::Decoder.new(IO::Buffer.for(bytes)))
        encoder = Nl::Encoder.new
        values.encode(encoder)

        expect(values.first).to eq(40)
        expect(values.last).to eq(30)
        expect(encoder.buffer.get_string).to eq([8, 1, 40, 8, 2048, 30].pack('SSL' * 2))
      end

      it 'decodes an empty table and inherits the generated definitions in subclasses' do
        bytes = [8, 1, 42].pack('SSL')
        empty = attrs::Empty.decode(Nl::Decoder.new(IO::Buffer.for(bytes)))
        expect(empty.instance_variable_get(:@attributes)).to eq([])

        definition = attrs::Attrs.by_name(:last).with(id: 1, datatype: Nl::DataTypes::Binary.new)
        subclass = Class.new(attrs::Attrs)
        subclass.const_set(:BY_TYPE, [nil, definition].freeze)
        values = subclass.decode(Nl::Decoder.new(IO::Buffer.for(bytes)))

        expect(subclass::BY_TYPE[1]).to equal(definition)
        expect(values.first).to eq(42)
        expect(values.instance_variable_get(:@attributes)).to eq([1, 42])
      end
    end

    it 'generates array APIs for multi-attributes' do
      path = Pathname(__dir__) + 'fixtures/multi_attr.yaml'
      generated = StringIO.new
      path.open { |source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)
      message_class = cls::Messages::DoUpdateRequest

      message = message_class.from_params(ids: [10, 20])

      expect(message.ids).to eq [10, 20]
      expect(message[:ids]).to eq [10, 20]
      expect(message_class.from_params({}).ids).to eq []
      expect(cls::AttributeSets::Subset.by_name(:ids).multi).to be true
      expect(generated.string).to include('?ids: ::Array[::Integer]')
      expect(generated.string).to include('# @rbs return: ::Array[::Integer]')
    end

    it 'accepts hashes for nested attributes in do and dump operations' do
      path = Pathname(__dir__) + 'fixtures/multi_attr.yaml'
      generated = StringIO.new
      path.open { |source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)
      connection = Object.new
      allow(connection).to receive(:register_notifications)
      allow(connection).to receive(:receive_notification)
      allow(connection).to receive(:exchange) do |_endpoint, _kind, request_class, _reply_class, args|
        request_class.from_params(args)
      end
      info = Nl::Genl::FamilyInfo.new(id: 42, multicast_groups: {})
      family = cls.new(connection, endpoint: Nl::Genl::Endpoint.new(cls, info))

      do_request = family.do_update(child: { text: 'do' })
      dump_request = family.dump_update(child: { text: 'dump' })

      expect(do_request.child[:text]).to eq 'do'
      expect(dump_request.child[:text]).to eq 'dump'
      expect(generated.string).to include(
        '?child: (AttributeSets::InnerB | ::Hash[::Symbol, untyped])',
      )
    end

    example do
      cls = Ynl::Family.build(yaml)

      expect(cls.name).to match /::Conntrack\z/
      expect(cls::NAME).to eq 'conntrack'
      expect(cls::PROTONUM).to eq 12
      expect(cls).to be < Nl::Raw::Family
      expect(cls.const_defined?(:PROTOCOL, false)).to be(false)
    end

    it 'generates a dump method for an operation with an implicit empty request' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/ops_unified.yaml')

      expect(cls.instance_methods(false)).to include(:dump_op_a)
      expect(cls).to be < Nl::Genl::Family
      expect(cls.const_defined?(:PROTOCOL, false)).to be(false)
      expect(cls.instance_methods(false)).to include(:async)
      expect(cls::AsyncOperations.instance_methods(false)).to include(:dump_op_a)
      expect(cls::Messages::DumpOpARequest::TYPE).to eq 1
      expect(cls::Messages::DumpOpARequest::ATTRIBUTES).to be_empty
    end

    it 'generates Generic Netlink family version metadata' do
      source = StringIO.new(<<~YAML)
        name: versioned
        protocol: genetlink
        version: 2
        attribute-sets: []
      YAML
      generated = StringIO.new

      Ynl::Family.generate(source, generated)

      expect(generated.string).to include('VERSION = 2')
    end

    it 'generates the default Generic Netlink family version metadata' do
      generated = StringIO.new
      path = Pathname(__dir__) + 'fixtures/ops_unified.yaml'

      path.open { |source| Ynl::Family.generate(source, generated) }

      expect(generated.string).to include('VERSION = 1')
    end

    it 'injects a default resolver into Generic Netlink family open methods' do
      generated = StringIO.new
      path = Pathname(__dir__) + 'fixtures/ops_unified.yaml'
      path.open do |source|
        Ynl::Family.generate(source, generated, default_resolver: 'DefaultResolver')
      end

      expect(generated.string).to include(
        'def self.open(resolver: DefaultResolver, executor: nil, notification_capacity: DEFAULT_NOTIFICATION_CAPACITY)',
      )
      expect(generated.string).to include('super')
    end

    it 'generates raw Netlink family open methods without a resolver' do
      generated = StringIO.new
      yaml.open do |source|
        Ynl::Family.generate(source, generated, default_resolver: 'DefaultResolver')
      end

      expect(generated.string).to include(
        'def self.open(executor: nil, notification_capacity: DEFAULT_NOTIFICATION_CAPACITY)',
      )
      expect(generated.string).not_to include('resolver:')
      expect(generated.string).not_to include('DefaultResolver')
    end

    it 'rejects asynchronous operations when no executor is configured' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/ops_unified.yaml')
      family = cls.allocate
      connection = Nl::Connection.allocate
      connection.instance_variable_set(:@transport, Nl::BlockingTransport.allocate)
      family.instance_variable_set(:@connection, connection)

      expect(family).not_to be_async_capable
      expect { family.async }.to raise_error(
        Nl::Async::UnavailableError,
        'async operations require an executor',
      )
    end

    it 'reports asynchronous capability when an executor is configured' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/ops_unified.yaml')
      family = cls.allocate
      connection = Nl::Connection.allocate
      connection.instance_variable_set(:@transport, Nl::Async::Dispatcher.allocate)
      family.instance_variable_set(:@connection, connection)

      expect(family).to be_async_capable
      expect(family.async).to be_a(cls::AsyncOperations)
    end

    it 'dispatches asynchronous operations without bypassing Family encapsulation' do
      generated = StringIO.new
      path = Pathname(__dir__) + 'fixtures/ops_unified.yaml'
      path.open { |source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)
      connection = Object.new
      calls = []
      allow(connection).to receive(:async_capable?).and_return(true)
      allow(connection).to receive(:register_notifications).and_return(Object.new)
      allow(connection).to receive(:receive_notification) { |_endpoint, timeout:| timeout }
      allow(connection).to receive(:exchange_async) do |*args, **kwargs|
        calls << [args, kwargs]
        :operation
      end
      info = Nl::Genl::FamilyInfo.new(id: 42, multicast_groups: {})
      endpoint = Nl::Genl::Endpoint.new(cls, info)
      family = cls.new(connection, endpoint:)

      operations = family.async(stream_capacity: 7)
      expect(operations.do_op_a).to eq(:operation)
      expect(operations.dump_op_a).to eq(:operation)
      expect(calls).to eq([
        [[endpoint, :do, cls::Messages::DoOpARequest,
          cls::Messages::DoOpAReply, {}], {stream_capacity: 7}],
        [[endpoint, :dump, cls::Messages::DumpOpARequest,
          cls::Messages::DumpOpAReply, {}], {stream_capacity: 7}],
      ])
      expect(generated.string).not_to include('__send__')
      expect(cls.private_instance_methods).to include(:exchange_message_async)
    end

    it 'documents operation permission flags' do
      generated = StringIO.new
      path = Pathname(__dir__) + 'fixtures/operation_flags.yaml'
      path.open { |source| Ynl::Family.generate(source, generated) }

      expect(generated.string).to match(
        /# Change a global network setting\.\n[ \t]*#[ ]*\n[ \t]*# Requires CAP_NET_ADMIN in the initial user namespace\./,
      )
      expect(generated.string).to match(
        /# Change a namespaced network setting\.\n[ \t]*#[ ]*\n[ \t]*# Requires CAP_NET_ADMIN in the user namespace owning the network namespace\./,
      )
      expect(generated.string).not_to match(/# Read a network setting\.\n[ \t]*#[ ]*\n[ \t]*# Requires/)
    end

    describe 'notifications' do
      let(:path) { Pathname(__dir__) + 'fixtures/notifications.yaml' }
      let(:family_class) { Ynl::Family.build(path) }

      it 'generates multicast group metadata under Ruby-friendly names' do
        expect(family_class::MCAST_GROUPS).to eq(
          changes: Nl::McastGroup.new('changes', nil),
          fixed_id: Nl::McastGroup.new('fixed-id', 42),
        )
      end

      it 'generates typed notification classes and a wire ID lookup' do
        changed = family_class::Notifications::ObjectChanged
        failed = family_class::Notifications::ObjectFailed
        ungrouped = family_class::Notifications::UngroupedEvent
        list_changed = family_class::Notifications::ObjectListChanged

        expect(family_class::NOTIFICATIONS).to eq(
          2 => changed,
          3 => failed,
          4 => ungrouped,
          6 => list_changed,
        )
        expect(changed::TYPE).to eq 2
        expect(changed::ATTRIBUTE_SET).to equal family_class::AttributeSets::Attrs
        expect(changed::ATTRIBUTES).to eq %i[item_id reason]
        expect(failed::ATTRIBUTES).to eq %i[item_id reason]
        expect(ungrouped::ATTRIBUTES).to eq %i[reason]
        expect(list_changed::ATTRIBUTES).to eq %i[item_id]
        expect(changed.instance_methods(false)).to include(:item_id, :reason)
      end

      it 'registers and decodes generated notifications' do
        protocol = Nl::Genl::Protocol.new
        info = Nl::Genl::FamilyInfo.new(id: 42, multicast_groups: {})
        endpoint = Nl::Genl::Endpoint.new(family_class, info)
        message_class = family_class::Notifications::ObjectChanged
        request = protocol.build_request(
          endpoint,
          :do,
          message_class,
          item_id: 7,
          reason: 'updated',
        )
        encoder = Nl::Encoder.new
        protocol.encode_message(encoder, endpoint, request, seq: 0, pid: 0)
        encoded = encoder.buffer
        decoder = Nl::Decoder.new(encoded)
        header = Nl::Raw::NlMsgHdr.decode(decoder)
        payload = decoder

        notification = protocol.decode_notification(endpoint, header, payload, family_class::NOTIFICATIONS)

        expect(notification).to be_a(message_class)
        expect(notification.item_id).to eq 7
        expect(notification.reason).to eq 'updated'
      end

      it 'subscribes with normalized symbols while resolving the kernel group name' do
        info = Nl::Genl::FamilyInfo.new(
          id: 42,
          multicast_groups: {'fixed-id' => 99},
        )
        endpoint = Nl::Genl::Endpoint.new(family_class, info)
        connection = Object.new
        allow(connection).to receive(:register_notifications)
        allow(connection).to receive(:receive_notification)
        expect(connection).to receive(:add_memberships).with([99])
        expect(connection).to receive(:drop_memberships).with([99])
        family = family_class.new(connection, endpoint:)

        expect(family.subscribe(:fixed_id)).to equal family
        expect(family.unsubscribe(:fixed_id)).to equal family
      end

      it 'generates narrowed subscription annotations and delegating methods' do
        generated = StringIO.new
        path.open { |source| Ynl::Family.generate(source, generated) }

        expect(generated.string).to include(
          '# @rbs (*(:changes | :fixed_id) groups) -> self',
        )
        expect(generated.string).to include('def subscribe(*groups) = super')
        expect(generated.string).to include('def unsubscribe(*groups) = super')
      end

      it 'rejects notification sources without a reply schema' do
        source = Pathname(__dir__) + 'fixtures/ops_directional.yaml'

        expect do
          source.open { |input| Ynl::Family.generate(input, StringIO.new) }
        end.to raise_error(
          Ynl::ParseError,
          'Notification "ntf" references "setter", which has no do reply',
        )
      end

      it 'rejects multicast group names with colliding Ruby normalizations' do
        source = StringIO.new(<<~YAML)
          name: colliding-groups
          attribute-sets: []
          operations:
            list: []
          mcast-groups:
            list:
              - name: fixed-id
              - name: fixed_id
        YAML

        expect do
          Ynl::Family.generate(source, StringIO.new)
        end.to raise_error(
          Ynl::ParseError,
          'Multicast groups "fixed-id" and "fixed_id" normalize to :fixed_id',
        )
      end
    end
  end
end
