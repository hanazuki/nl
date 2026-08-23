# rbs_inline: enabled

module Nl
  module Async
    module Drivers
      class Thread
        def start(&block)
          ::Thread.new(&block)
        end

        def wait_readable(io)
          io.wait_readable
        end

        def stop(task)
          task.join
        end

        def check_wait_context! = nil
      end

      class Fiber
        def start(&block)
          raise ArgumentError, 'Fiber.scheduler is not installed' unless ::Fiber.scheduler

          ::Fiber.schedule(&block)
        end

        def wait_readable(io)
          io.wait_readable
        end

        def stop(_task)
          # Scheduled fibers have no general join operation. Closing the socket
          # makes the receive loop terminate at its next scheduling point.
        end

        def check_wait_context!
          return unless ::Fiber.blocking?

          raise BlockingFiberError,
            'fiber-backed operations must wait inside Fiber.schedule'
        end
      end
    end

    def self.driver(name)
      case name
      when :thread then Drivers::Thread.new
      when :fiber then Drivers::Fiber.new
      else
        raise ArgumentError, "unknown async executor: #{name.inspect}"
      end
    end
  end
end
