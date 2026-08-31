# rbs_inline: enabled

require_relative '../error'

module Nl
  module Async
    module Events
      Item = Data.define(:value)
      Done = Data.define
      Error = Data.define(:exception)
    end
    private_constant :Events

    class ConcurrentConsumptionError < StandardError; end
    class StreamOverflowError < StandardError; end

    # Future for the result of an already-started, single-reply operation.
    # @rbs generic out Result
    class Future
      def self.build(mailbox: Mailbox.new, on_close: nil)
        operation = new(mailbox:, on_close:)
        [operation, Sink.new(mailbox)]
      end

      def initialize(mailbox:, on_close:)
        @mailbox = mailbox
        @on_close = on_close
        @mutex = Mutex.new
        @state = :open
        @value = nil
        @error = nil
      end

      # @rbs (?timeout: Numeric?) -> Result
      def await(timeout: nil)
        return terminal_result unless @mutex.synchronize { @state == :open }

        event = @mailbox.pop(timeout:)
        case event
        when Events::Item
          settle_done(event.value)
        when Events::Done
          settle_done(nil)
        when Events::Error
          settle_failed(event.exception)
        end
        @mailbox.close
        terminal_result
      rescue ClosedError
        terminal_result
      end
      alias value await

      def ready? #: bool
        @mutex.synchronize { @state != :open } || !@mailbox.empty?
      end

      # Stops local delivery. The dispatcher still drains the Netlink exchange.
      def close #: nil
        closed, callback = @mutex.synchronize do
          next [false, nil] if @state != :open

          @state = :closed
          [true, @on_close]
        end
        if closed
          callback&.call
          @mailbox.close
        end
        nil
      end

      private def settle_done(value)
        @mutex.synchronize do
          if @state == :open
            @state = :done
            @value = value
          end
        end
      end

      private def settle_failed(error)
        @mutex.synchronize do
          if @state == :open
            @state = :failed
            @error = error
          end
        end
      end

      private def terminal_result
        state, value, error = @mutex.synchronize { [@state, @value, @error] }
        case state
        when :done then value
        when :failed then raise error
        else raise ClosedError, 'future is closed'
        end
      end

      class Sink
        def initialize(mailbox)
          @mailbox = mailbox
        end

        def succeed(value) = @mailbox.push(Events::Item.new(value))
        def finish = @mailbox.push_terminal(Events::Done.new)
        def fail(exception) = @mailbox.push_terminal(Events::Error.new(exception))
      end
    end

    # Single-pass consumer handle for a multipart Netlink operation.
    # @rbs generic out Item
    class Stream
      include Enumerable #[Item]

      def self.build(mailbox: Mailbox.new, on_close: nil)
        operation = new(mailbox:, on_close:)
        [operation, Sink.new(mailbox)]
      end

      def initialize(mailbox:, on_close:)
        @mailbox = mailbox
        @on_close = on_close
        @mutex = Mutex.new
        @owner = nil
        @state = :open
        @error = nil
      end

      # @rbs () { (Item) -> void } -> self
      #    | () -> Enumerator[Item, self]
      def each
        return enum_for(__method__) unless block_given?

        state, error = current_state
        case state
        when :completed then return self
        when :closed then raise ClosedError, 'stream is closed'
        when :failed then raise error
        end

        claim_consumer!
        begin
          loop do
            case event = @mailbox.pop
            when Events::Item
              yield event.value
            when Events::Done
              completed = mark_completed
              @mailbox.close
              terminal_result unless completed
              break
            when Events::Error
              failed = mark_failed(event.exception)
              @mailbox.close
              raise event.exception if failed

              terminal_result
            end
          end
          self
        rescue ClosedError
          terminal_result
        ensure
          close if open?
        end
      end

      # @rbs (?timeout: Numeric?) -> Item
      def next(timeout: nil)
        state, error = current_state
        case state
        when :completed then raise StopIteration
        when :closed then raise ClosedError, 'stream is closed'
        when :failed then raise error
        end

        claim_consumer!
        case event = @mailbox.pop(timeout:)
        when Events::Item
          event.value
        when Events::Done
          completed = mark_completed
          @mailbox.close
          raise StopIteration if completed

          terminal_result(next_item: true)
        when Events::Error
          failed = mark_failed(event.exception)
          @mailbox.close
          raise event.exception if failed

          terminal_result(next_item: true)
        end
      rescue ClosedError
        terminal_result(next_item: true)
      end

      # Stops local delivery. The dispatcher still drains the Netlink exchange.
      def close #: nil
        closed, callback = @mutex.synchronize do
          next [false, nil] if @state != :open

          @state = :closed
          [true, @on_close]
        end
        if closed
          callback&.call
          @mailbox.close
        end
        nil
      end

      def closed? #: bool
        @mutex.synchronize { @state != :open }
      end

      private def current_state
        @mutex.synchronize { [@state, @error] }
      end

      private def open?
        @mutex.synchronize { @state == :open }
      end

      private def claim_consumer!
        owner = Fiber.current
        @mutex.synchronize do
          @owner ||= owner
          unless @owner.equal?(owner)
            raise ConcurrentConsumptionError, 'a stream can only be consumed by one fiber'
          end
        end
      end

      private def mark_completed
        @mutex.synchronize do
          next false unless @state == :open

          @state = :completed
          true
        end
      end

      private def mark_failed(error)
        @mutex.synchronize do
          next false unless @state == :open

          @state = :failed
          @error = error
          true
        end
      end

      private def terminal_result(next_item: false)
        state, error = current_state
        case state
        when :completed
          raise StopIteration if next_item
          self
        when :failed
          raise error
        else
          raise ClosedError, 'stream is closed'
        end
      end

      class Sink
        def initialize(mailbox)
          @mailbox = mailbox
        end

        def push(value) = @mailbox.push(Events::Item.new(value))
        def finish = @mailbox.push_terminal(Events::Done.new)
        def fail(exception) = @mailbox.push_terminal(Events::Error.new(exception))
      end
    end
  end
end
