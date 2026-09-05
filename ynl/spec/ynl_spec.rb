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
    it 'generates and round-trips statically selected sub-messages' do
      path = Pathname(__dir__) + 'fixtures/sub_messages.yaml'
      generated = StringIO.new
      path.open { |source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)

      attributes = cls::AttributeSets::OuterAttrs.build_attributes(
        child: {leaf: {data: {header_value: 7, payload_value: 11}}},
        kind: 'foo',
      )
      encoder = Nl::Encoder.new
      attributes.encode(encoder)
      decoded = cls::AttributeSets::OuterAttrs.decode(Nl::Decoder.new(encoder.buffer))
      data = decoded.child.leaf.data

      expect(data).to be_a(cls::SubMessages::PayloadMessage::Foo)
      expect(data).to have_attributes(header_value: 7, payload_value: 11)
      expect(encoder.buffer.get_value(Nl::Endian::Host::U16, 2)).to eq(1)
      expect(generated.string).to include('::Nl::Selector::External.new(0)')
      expect(generated.string).to include('selector_bindings: Ractor.make_shareable([::Nl::Selector::Local.new(0)])')
      expect(generated.string).to include('selector_bindings: Ractor.make_shareable([::Nl::Selector::External.new(0)])')
      expect(generated.string).to include('SELECTOR_SLOT = 0')
      expect(generated.string).not_to include('SELECTOR_SLOTS_BY_')
      expect(generated.string).to include('# @rbs return: AttributeSets::ChildAttrs')
      expect(generated.string).to include('def child; self[:"child"]&.value; end')
      expect(generated.string).to include(
        '# @rbs return: SubMessages::PayloadMessage::Foo | SubMessages::PayloadMessage::Bar | ::Nl::RawSubMessage',
      )
      expect(generated.string).to include('def data; self[:"data"]&.value; end')
    end

    it 'compiles enum selector names to their integer values' do
      path = Pathname(__dir__) + 'fixtures/sub_messages.yaml'
      generated = StringIO.new
      path.open { |source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)

      attributes = cls::AttributeSets::EnumAttrs.build_attributes(
        data: {header_value: 3, payload_value: 5},
        kind: 10,
      )
      encoder = Nl::Encoder.new
      attributes.encode(encoder)
      decoded = cls::AttributeSets::EnumAttrs.decode(Nl::Decoder.new(encoder.buffer))

      expect(decoded[:data].value).to have_attributes(header_value: 3, payload_value: 5)
      expect(encoder.buffer.get_value(Nl::Endian::Host::U16, 2)).to eq(
        cls::AttributeSets::EnumAttrs::Kind::TYPE,
      )
      expect(cls::AttributeSets::EnumAttrs::Kind::ORDER).to eq(0)
      expect(cls::AttributeSets::EnumAttrs::Data::ORDER).to eq(1)
      expect(generated.string).to include('10 => ::Nl::DataTypes::SubMessage::Format.new')
      expect(generated.string).to include('20 => ::Nl::DataTypes::SubMessage::Format.new')
    end

    it 'rejects a sub-message whose selector has not appeared on the wire' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/sub_messages.yaml')
      encoded = Nl::Encoder.new
      attrs = cls::AttributeSets::EnumAttrs.build_attributes(
        kind: 10,
        data: {header_value: 3, payload_value: 5},
      )
      attrs[:data].then do |data|
        encoded.measure(Nl::Endian::Host::U16) do
          Nl::Raw::NlAttr.new(0, data.class::TYPE | Nl::Raw::NLA_F_NESTED).encode(encoded)
          data.value.encode(encoded)
        end
        encoded.align_to(Nl::Raw::NLA_ALIGNTO)
      end

      expect do
        cls::AttributeSets::EnumAttrs.decode(Nl::Decoder.new(encoded.buffer))
      end.to raise_error(
        Nl::Decoder::Error,
        'selector :kind must precede the dependent attribute',
      )

      expect do
        cls::AttributeSets::LeafAttrs.build_attributes(
          data: {header_value: 3, payload_value: 5},
        )
      end.to raise_error(
        ArgumentError,
        'selector :kind is required by a dependent attribute',
      )
    end

    it 'preserves an unknown sub-message format as raw data' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/sub_messages.yaml')
      raw = Nl::RawSubMessage.new(
        "\x01\x02\x03\x04".b,
        nlattr_type_flags: Nl::Raw::NLA_F_NESTED,
      )
      attributes = cls::AttributeSets::EnumAttrs.build_attributes(kind: 99, data: raw)
      encoded = Nl::Encoder.new
      attributes.encode(encoded)

      decoded = cls::AttributeSets::EnumAttrs.decode(Nl::Decoder.new(encoded.buffer))
      value = decoded[:data].value
      reencoded = Nl::Encoder.new
      decoded.encode(reencoded)

      expect(value).to be_a(Nl::RawSubMessage)
      expect(value.payload).to eq("\x01\x02\x03\x04".b)
      expect(value.nlattr_type_flags).to eq(Nl::Raw::NLA_F_NESTED)
      expect(reencoded.buffer.get_string).to eq(encoded.buffer.get_string)
    end

    it 'allows raw data after its selector format becomes known' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/sub_messages.yaml')
      raw = Nl::RawSubMessage.new(
        "\x01\x02\x03\x04".b,
        nlattr_type_flags: Nl::Raw::NLA_F_NESTED,
      )

      attributes = cls::AttributeSets::EnumAttrs.build_attributes(kind: 10, data: raw)
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
      expect(generated.string).to include('bytes: ::Nl::DataTypes::Binary.new(length: 3, check: nil)')
      expect(generated.string).to include('inner: ::Nl::DataTypes::Struct.new(Structs::Inner, check: nil)')
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
      attributes = cls::AttributeSets::Attrs.build_attributes(record: values)
      encoder = Nl::Encoder.new

      attributes.encode(encoder)
      decoded = cls::AttributeSets::Attrs.decode(Nl::Decoder.new(encoder.buffer))[:record].value

      expect(decoded).to be_a(cls::Structs::Outer)
      expect(decoded).to have_attributes(prefix: 1, bytes: "\x02\x03\x04".b, suffix: 6)
      expect(decoded.inner).to eq(cls::Structs::Inner.new(0x0504))
      expect(generated.string).to include(
        '::Nl::DataTypes::Struct.new(Structs::Outer, check:',
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
        Nl::Raw::NlAttr.new(0, 2).encode(encoder)
        outer.encode(encoder)
        encoder.put_string("\xaa\xbb".b)
      end
      encoder.align_to(Nl::Raw::NLA_ALIGNTO)

      attributes = cls::AttributeSets::Attrs.decode(Nl::Decoder.new(encoder.buffer))

      expect(attributes[:extensible_record].value).to eq(outer)
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
        '::Nl::DataTypes::VariableInteger.new(::Nl::Endian::Host, signed: false, check: nil)',
      )
      expect(generated.string).to include(
        '::Nl::DataTypes::VariableInteger.new(::Nl::Endian::Host, signed: true, check: nil)',
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

      expect(generated.string).to include('DATATYPE = ::Nl::DataTypes::Bitfield32.new')
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
        '::Nl::DataTypes::PackedArray.new(::Nl::DataTypes::Scalar.new(::Nl::Endian::Big::U32, check: nil), check: nil)',
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
        attributes = cls::AttributeSets::Attrs.build_attributes(payload: '12345')
        attributes.encode(Nl::Encoder.new)
      end.to raise_error(ArgumentError, 'Value "12345" is longer than maximum length 4')
    end

    it 'generates array APIs for multi-attributes' do
      path = Pathname(__dir__) + 'fixtures/multi_attr.yaml'
      generated = StringIO.new
      path.open { |source| Ynl::Family.generate(source, generated) }
      cls = Ynl::Family.build(path)
      message_class = cls::Messages::DoUpdateRequest

      message = message_class.from_params(ids: [10, 20])

      expect(message.ids).to eq [10, 20]
      expect(message.attributes[:ids].map(&:value)).to eq [10, 20]
      expect(message_class.from_params({}).ids).to eq []
      expect(cls::AttributeSets::Subset::Ids::MULTI).to be true
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

      expect(do_request.child[:text].value).to eq 'do'
      expect(dump_request.child[:text].value).to eq 'dump'
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

    it 'does not inject a resolver into raw Netlink families' do
      generated = StringIO.new
      yaml.open do |source|
        Ynl::Family.generate(source, generated, default_resolver: 'DefaultResolver')
      end

      expect(generated.string).not_to include('def self.open')
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
        payload = decoder.get_buffer

        selected = protocol.notification_class(endpoint, header, payload, family_class::NOTIFICATIONS)
        notification = protocol.decode_notification(endpoint, header, payload, selected)

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
