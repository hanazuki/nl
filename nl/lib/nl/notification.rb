# rbs_inline: enabled

require_relative 'error'

module Nl
  # A multicast group. `name` is the kernel-facing name.
  # `id` is the fixed ID when the specification provides one.
  McastGroup = Data.define(:name, :id)

  # Thread-safe queue shared by a family's blocking and asynchronous facades.
  class NotificationChannel
    def initialize(capacity:)
      raise ArgumentError, 'notification capacity must be positive' if capacity && capacity <= 0

      @capacity = capacity
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @queue = []
      @error = nil
      @closed = false
    end

    # Adds a notification without ever blocking the socket receive loop.
    # Returns false after the channel has been closed.
    def push(notification)
      @mutex.synchronize do
        return false if @closed

        if @capacity && @queue.length >= @capacity
          lose!(NotificationLossError.new('notification queue capacity exceeded'))
        else
          wake = @queue.empty? && !@error
          @queue << notification
          @condition.signal if wake
        end
      end
      true
    end

    # Records a broken notification boundary while allowing later delivery to
    # resume after the consumer observes the error and resynchronizes state.
    def fail(error)
      @mutex.synchronize do
        return false if @closed

        lose!(error)
      end
      true
    end

    def pop(timeout: nil)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout if timeout

      @mutex.synchronize do
        loop do
          if error = @error
            @error = nil
            raise error
          end
          return @queue.shift unless @queue.empty?
          raise ClosedError, 'notification channel is closed' if @closed

          remaining = deadline && deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise TimeoutError, 'notification receive timed out' if remaining && remaining <= 0

          @condition.wait(@mutex, remaining)
        end
      end
    end

    def empty?
      @mutex.synchronize { @queue.empty? && !@error }
    end

    def close
      @mutex.synchronize do
        return nil if @closed

        @closed = true
        @queue.clear
        @error = nil
        @condition.broadcast
      end
      nil
    end

    private def lose!(error)
      @queue.clear
      @error = error
      @condition.signal
    end
  end

  # An unbounded-in-time, single-family view of unsolicited messages.
  class NotificationStream
    include Enumerable

    def initialize(&receive)
      @receive = receive
    end

    def next(timeout: nil)
      @receive.call(timeout)
    end

    def each
      return enum_for(__method__) unless block_given?

      loop { yield self.next }
    end
  end
end
