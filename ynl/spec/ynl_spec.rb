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
    example do
      cls = Ynl::Family.build(yaml)

      expect(cls.name).to match /::Conntrack\z/
      expect(cls::NAME).to eq 'conntrack'
      expect(cls::PROTOCOL).to be_kind_of Nl::Protocols::Raw
    end

    it 'generates a dump method for an operation with an implicit empty request' do
      cls = Ynl::Family.build(Pathname(__dir__) + 'fixtures/ops_unified.yaml')

      expect(cls.instance_methods(false)).to include(:dump_op_a)
      expect(cls.instance_methods(false)).to include(:async)
      expect(cls::AsyncOperations.instance_methods(false)).to include(:dump_op_a)
      expect(cls::Messages::DumpOpARequest::TYPE).to eq 1
      expect(cls::Messages::DumpOpARequest::ATTRIBUTES).to be_empty
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
      allow(connection).to receive(:receive_notification) { |_protocol, timeout:| timeout }
      allow(connection).to receive(:exchange_async) do |*args, **kwargs|
        calls << [args, kwargs]
        :operation
      end
      family = cls.new(connection)

      operations = family.async(stream_capacity: 7)
      expect(operations.do_op_a).to eq(:operation)
      expect(operations.dump_op_a).to eq(:operation)
      expect(calls).to eq([
        [[cls::PROTOCOL, :do, cls::Messages::DoOpARequest,
          cls::Messages::DoOpAReply, {}], {stream_capacity: 7}],
        [[cls::PROTOCOL, :dump, cls::Messages::DumpOpARequest,
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
        protocol = Nl::Protocols::Genl.new('notifications', family_id: 42)
        message_class = family_class::Notifications::ObjectChanged
        request = protocol.build_request(
          :do,
          message_class,
          item_id: 7,
          reason: 'updated',
        )
        encoder = Nl::Encoder.new
        protocol.encode_message(encoder, request, seq: 0, pid: 0)
        encoded = encoder.buffer
        decoder = Nl::Decoder.new(encoded)
        header = Nl::Core::NlMsgHdr.decode(decoder)
        payload = decoder.get_buffer

        selected = protocol.notification_class(header, payload, family_class::NOTIFICATIONS)
        notification = protocol.decode_notification(header, payload, selected)

        expect(notification).to be_a(message_class)
        expect(notification.item_id).to eq 7
        expect(notification.reason).to eq 'updated'
      end

      it 'subscribes with normalized symbols while resolving the kernel group name' do
        protocol = Nl::Protocols::Genl.new(
          'notifications',
          family_id: 42,
          multicast_groups: {:'fixed-id' => 99},
        )
        connection = Object.new
        allow(connection).to receive(:register_notifications)
        allow(connection).to receive(:receive_notification)
        expect(connection).to receive(:add_memberships).with([99])
        expect(connection).to receive(:drop_memberships).with([99])
        family = family_class.new(connection, protocol:)

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
