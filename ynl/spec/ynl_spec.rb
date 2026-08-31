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
  end
end
