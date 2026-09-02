# rbs_inline: enabled

require_relative '../datagram'
require_relative '../error'
require_relative '../exchange'
require_relative '../notification_router'
require_relative '../sequence_allocator'

module Nl
  module Async
    # Owns the single receive loop for a socket and routes replies by sequence.
    class Dispatcher
      Pending = Data.define(:exchange, :endpoint, :reply_class, :sink)
      private_constant :Pending

      def initialize(socket, protocol:, executor: :thread, notifications:)
        @socket = socket
        @protocol = protocol
        @sequences = SequenceAllocator.new
        @notifications = notifications
        @driver = executor.respond_to?(:start) ? executor : Async.driver(executor)
        @mutex = Mutex.new
        @send_mutex = Mutex.new
        @pending = {}
        @closed = false
        @task = @driver.start { receive_loop }
      end

      def exchange(endpoint, kind, request_class, reply_class, args, &block)
        operation = exchange_async(endpoint, kind, request_class, reply_class, args)
        if kind == :dump
          if block
            operation.each(&block)
            nil
          else
            operation.to_a
          end
        else
          operation.await
        end
      end

      def exchange_async(endpoint, kind, request_class, reply_class, args, stream_capacity: nil)
        request = @protocol.build_request(endpoint, kind, request_class, args)

        key = nil
        seq = pid = nil
        operation = sink = nil
        @send_mutex.synchronize do
          @mutex.synchronize do
            raise ClosedError, 'dispatcher is closed' if @closed

            pid = @socket.local_port_id
            seq = @sequences.next { @pending.key?([it, pid]) }
            key = [seq, pid]
            mailbox = Mailbox.new(capacity: stream_capacity)
            operation, sink = if kind == :dump
              Stream.build(mailbox:, on_close: -> { discard(key) })
            else
              Future.build(mailbox:, on_close: -> { discard(key) })
            end
            exchange = Exchange.new(kind:, expects_reply: !reply_class.nil?)
            @pending[key] = Pending.new(exchange:, endpoint:, reply_class:, sink:)
          end

          begin
            @protocol.send_message(@socket, endpoint, request, seq:, pid:)
          rescue Exception => error
            fail_pending(key, error)
            raise
          end
        end
        operation
      end

      def async_capable? #: true
        true
      end

      def receive_notification(endpoint, timeout: nil)
        @notifications.channel(endpoint).pop(timeout:)
      end

      def close
        task = @mutex.synchronize do
          next if @closed

          @closed = true
          @socket.close unless @socket.closed?
          @task
        end
        fail_all(ClosedError.new('dispatcher is closed'))
        @driver.stop(task) if task && !task.equal?(::Thread.current)
        nil
      end

      private def receive_loop
        loop do
          break if @mutex.synchronize { @closed }

          @socket.wait_readable
          data = @socket.recvmsg_nonblock(exception: false)
          next if data == :wait_readable

          dispatch_datagram(IO::Buffer.for(data.first))
        rescue Errno::ENOBUFS => e
          @notifications.lose_all(NotificationLossError.new('kernel receive buffer overflowed'))
          fail_all(e)
        end
      rescue Exception => e
        fail_receive_loop(e)
      end

      private def fail_receive_loop(error)
        failed = @mutex.synchronize do
          next false if @closed

          @closed = true
          @socket.close unless @socket.closed?
          true
        end
        return unless failed

        fail_all(error)
        @notifications.close
      end

      private def dispatch_datagram(buffer)
        Datagram.each_frame(buffer) do |header, payload|
          key = [header.seq, header.pid]
          pending = @mutex.synchronize { @pending[key] }
          unless pending
            @notifications.route(header, payload) if header.seq.zero?
            next
          end

          begin
            message = @protocol.decode_frame(pending.endpoint, header, payload, pending.reply_class)
            dispatch_outcome(key, pending, pending.exchange.accept(message))
          rescue Exception => error
            fail_pending(key, error) if pending
          end
        end
      end

      private def dispatch_outcome(key, pending, outcome)
        return unless outcome

        case outcome
        when Exchange::Item
          begin
            pending.sink.push(outcome.value)
          rescue Mailbox::FullError
            fail_pending(key, StreamOverflowError.new("reply buffer exceeded for sequence #{key.first}"))
          end
        when Exchange::Complete
          complete_pending(key, pending, pending.exchange.result)
        when Exchange::Failure
          fail_pending(key, outcome.exception)
        end
      end

      private def complete_pending(key, pending, value)
        removed = @mutex.synchronize { @pending.delete(key) }
        return unless removed
        return if pending.exchange.cancelled?

        if pending.exchange.kind == :dump
          pending.sink.finish
        elsif pending.exchange.expects_reply?
          pending.sink.succeed(value)
        else
          pending.sink.finish
        end
      end

      private def discard(key)
        @mutex.synchronize do
          if pending = @pending[key]
            pending.exchange.cancel
          end
        end
      end

      private def fail_pending(key, error)
        pending = @mutex.synchronize { @pending.delete(key) }
        pending&.sink&.fail(error) unless pending&.exchange&.cancelled?
      end

      private def fail_all(error)
        pending = @mutex.synchronize do
          old = @pending.values
          @pending.clear
          old
        end
        pending.each { it.sink.fail(error) unless it.exchange.cancelled? }
      end
    end
  end
end
