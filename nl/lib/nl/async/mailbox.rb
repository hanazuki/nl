# rbs_inline: enabled

module Nl
  module Async
    # A thread-safe, scheduler-aware, single-consumer mailbox.
    class Mailbox
      class ClosedError < StandardError; end
      TimeoutError = Nl::Async::TimeoutError
      class FullError < StandardError; end

      def initialize(capacity: nil)
        raise ArgumentError, 'capacity must be positive' if capacity && capacity <= 0

        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @queue = []
        @closed = false
        @capacity = capacity
      end

      # Adds a value without executing consumer code.
      # @rbs (untyped) -> bool
      def push(value)
        push_value(value, enforce_capacity: true)
      end

      # Adds a completion/error event even when the value capacity is full.
      def push_terminal(value)
        push_value(value, enforce_capacity: false)
      end

      private def push_value(value, enforce_capacity:)
        @mutex.synchronize do
          return false if @closed
          if enforce_capacity && @capacity && @queue.length >= @capacity
            raise FullError, 'mailbox capacity exceeded'
          end

          wake = @queue.empty?
          @queue << value
          @condition.signal if wake
        end
        true
      end

      # Removes the next value, suspending through the current thread or Fiber scheduler if empty.
      # @rbs (?timeout: Numeric?) -> untyped
      def pop(timeout: nil)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout if timeout

        @mutex.synchronize do
          loop do
            return @queue.shift unless @queue.empty?
            raise ClosedError if @closed

            remaining = deadline && deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raise TimeoutError if remaining && remaining <= 0

            @condition.wait(@mutex, remaining)
          end
        end
      end

      def close
        @mutex.synchronize do
          return nil if @closed

          @closed = true
          @condition.broadcast
        end
        nil
      end

      def closed?
        @mutex.synchronize { @closed }
      end

      def empty?
        @mutex.synchronize { @queue.empty? }
      end
    end
  end
end
