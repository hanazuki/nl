# rbs_inline: enabled

require 'io/wait'

module Nl
  module Async
    # A thread-safe, scheduler-aware, single-consumer mailbox.
    class Mailbox
      class ClosedError < StandardError; end
      TimeoutError = Nl::Async::TimeoutError
      class FullError < StandardError; end

      def initialize(capacity: nil, before_wait: -> {})
        raise ArgumentError, 'capacity must be positive' if capacity && capacity <= 0

        @reader, @writer = IO.pipe
        @mutex = Mutex.new
        @queue = []
        @closed = false
        @capacity = capacity
        @before_wait = before_wait
        ObjectSpace.define_finalizer(self, self.class.__send__(:close_ios, @reader, @writer))
      end

      def self.close_ios(*ios)
        ->(_object_id) { ios.each { it.close unless it.closed? } }
      end
      private_class_method :close_ios

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
        wake = @mutex.synchronize do
          return false if @closed
          if enforce_capacity && @capacity && @queue.length >= @capacity
            raise FullError, 'mailbox capacity exceeded'
          end

          wake = @queue.empty?
          @queue << value
          wake
        end
        signal if wake
        true
      end

      # Removes the next value, suspending through IO#wait_readable if empty.
      # @rbs (?timeout: Numeric?) -> untyped
      def pop(timeout: nil)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout if timeout

        loop do
          present, value, empty, closed = @mutex.synchronize do
            present = !@queue.empty?
            value = @queue.shift if present
            [present, value, @queue.empty?, @closed]
          end

          if present
            drain_signal if empty
            return value
          end
          raise ClosedError if closed

          @before_wait.call
          remaining = deadline && deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise TimeoutError if remaining && remaining <= 0
          begin
            readable = @reader.wait_readable(remaining)
          rescue IOError
            raise ClosedError if closed?
            raise
          end
          raise TimeoutError unless readable

          drain_signal
        end
      end

      def close
        wake = @mutex.synchronize do
          next false if @closed

          @closed = true
          true
        end
        if wake
          signal
          @reader.close unless @reader.closed?
          @writer.close unless @writer.closed?
        end
        nil
      end

      def closed?
        @mutex.synchronize { @closed }
      end

      def empty?
        @mutex.synchronize { @queue.empty? }
      end

      private def signal
        @writer.write_nonblock(?\x00)
      rescue IO::WaitWritable
        # A pending byte already makes the reader runnable.
      rescue IOError, Errno::EPIPE
        # Closing a mailbox races harmlessly with a producer.
      end

      private def drain_signal
        @reader.read_nonblock(4096)
      rescue IO::WaitReadable, EOFError, IOError
        nil
      end
    end
  end
end
