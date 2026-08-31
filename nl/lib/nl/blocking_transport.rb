# rbs_inline: enabled

require_relative 'datagram'
require_relative 'exchange'
require_relative 'notification_router'
require_relative 'sequence_allocator'

module Nl
  # Drives one exchange at a time with blocking socket operations.
  class BlockingTransport
    class ConcurrentOperationError < StandardError; end

    class UnexpectedSequenceError < StandardError
      attr_reader :expected, :actual

      def initialize(expected, actual)
        @expected = expected
        @actual = actual
        super("expected Netlink sequence and port ID #{expected.inspect}, got #{actual.inspect}")
      end
    end

    def initialize(socket, notifications:)
      @socket = socket
      @sequences = SequenceAllocator.new
      @mutex = Mutex.new
      @notifications = notifications
    end

    def exchange(protocol, kind, request_class, reply_class, args)
      unless locked = @mutex.try_lock
        raise ConcurrentOperationError, 'BlockingTransport supports only one active operation'
      end

      request = protocol.build_request(kind, request_class, args)
      seq = @sequences.next
      pid = @socket.local_port_id
      key = [seq, pid]
      protocol.send_message(@socket, request, seq:, pid:)
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

    def receive_notification(protocol, timeout: nil)
      channel = @notifications.channel(protocol)
      return channel.pop(timeout: 0)
    rescue TimeoutError
      unless locked = @mutex.try_lock
        raise ConcurrentOperationError, 'BlockingTransport supports only one active operation'
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout if timeout
      loop do
        begin
          return channel.pop(timeout: 0)
        rescue TimeoutError
          # Read another datagram below.
        end

        remaining = deadline && deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise TimeoutError, 'notification receive timed out' if remaining && remaining <= 0
        if remaining && !@socket.wait_readable(remaining)
          raise TimeoutError, 'notification receive timed out'
        end

        receive_notifications
      end
    ensure
      @mutex.unlock if locked
    end

    def close #: void
      @socket.close unless @socket.closed?
      nil
    end

    private def receive(protocol, expected_key, reply_class)
      Datagram.each_frame(receive_datagram) do |header, payload|
        actual_key = [header.seq, header.pid]
        if actual_key == expected_key
          yield protocol.decode_frame(header, payload, reply_class)
        elsif header.seq.zero?
          @notifications.route(header, payload)
        else
          raise UnexpectedSequenceError.new(expected_key, actual_key)
        end
      end
    rescue Errno::ENOBUFS
      @notifications.lose_all(NotificationLossError.new('kernel receive buffer overflowed'))
      raise
    end

    private def receive_notifications
      Datagram.each_frame(receive_datagram) do |header, payload|
        if header.seq.zero?
          @notifications.route(header, payload)
        else
          raise UnexpectedSequenceError.new(nil, [header.seq, header.pid])
        end
      end
    rescue Errno::ENOBUFS
      @notifications.lose_all(NotificationLossError.new('kernel receive buffer overflowed'))
    end

    private def receive_datagram
      data, = @socket.recvmsg
      IO::Buffer.for(data)
    end
  end
end
