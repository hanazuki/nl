# rbs_inline: enabled

require_relative 'sequence_allocator'

module Nl
  # Drives one exchange at a time with blocking socket operations.
  class BlockingTransport
    class ConcurrentExchangeError < StandardError; end

    class UnexpectedSequenceError < StandardError
      attr_reader :expected, :actual

      def initialize(expected, actual)
        @expected = expected
        @actual = actual
        super("expected Netlink sequence and port ID #{expected.inspect}, got #{actual.inspect}")
      end
    end

    def initialize(socket)
      @socket = socket
      @sequences = SequenceAllocator.new
      @mutex = Mutex.new
    end

    def exchange(protocol, kind, request_class, reply_class, args)
      unless locked = @mutex.try_lock
        raise ConcurrentExchangeError, 'BlockingTransport supports only one active exchange'
      end

      request = protocol.build_request(kind, request_class, args)
      key = prepare(request.header)
      protocol.send_message(@socket, request)
      exchange = Exchange.new(kind:, expects_reply: !reply_class.nil?)
      result = [] unless block_given?

      until exchange.complete?
        receive(protocol, key, reply_class) do |message|
          case outcome = exchange.accept(message)
          when Exchange::Item
            block_given? ? yield(outcome.value) : result << outcome.value
          when Exchange::Failure
            raise outcome.exception
          end
        end
      end

      return if block_given?

      kind == :dump ? result : exchange.result
    ensure
      @mutex.unlock if locked
    end

    def async_capable? #: false
      false
    end

    def close #: void
      @socket.close unless @socket.closed?
      nil
    end

    private def receive(protocol, expected_key, reply_class)
      data, = @socket.recvmsg
      buffer = IO::Buffer.for(data)
      Datagram.each_frame(buffer) do |header, payload|
        actual_key = [header.seq, header.pid]
        unless actual_key == expected_key
          raise UnexpectedSequenceError.new(expected_key, actual_key)
        end

        yield protocol.decode_frame(header, payload, reply_class)
      end
    end

    private def prepare(header)
      header.pid = @socket.local_port_id
      header.seq = @sequences.next
      [header.seq, header.pid]
    end
  end
end
