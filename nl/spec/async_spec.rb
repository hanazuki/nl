# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Async do
  describe Nl::Async::Mailbox do
    it 'wakes a blocked thread when a value is pushed' do
      mailbox = described_class.new
      consumer = Thread.new { mailbox.pop }

      mailbox.push(:message)

      expect(consumer.value).to eq(:message)
    end

    it 'supports monotonic timeouts' do
      mailbox = described_class.new

      expect { mailbox.pop(timeout: 0.001) }.to raise_error(Nl::TimeoutError)
    end

    it 'wakes a blocked consumer when closed' do
      mailbox = described_class.new
      consumer = Thread.new do
        mailbox.pop
      rescue => error
        error
      end

      mailbox.close

      expect(consumer.value).to be_a(Nl::ClosedError)
    end

    it 'rejects pushes beyond a configured capacity without blocking' do
      mailbox = described_class.new(capacity: 1)
      mailbox.push(:first)

      expect { mailbox.push(:second) }.to raise_error(Nl::Async::Mailbox::FullError)
    end
  end

  describe Nl::Async::Future do
    it 'raises the public timeout error without closing the future' do
      future, sink = described_class.build

      expect { future.await(timeout: 0.001) }.to raise_error(Nl::TimeoutError)

      sink.succeed(:reply)
      expect(future.await).to eq(:reply)
    end

    it 'waits for and returns a reply' do
      future, sink = described_class.build
      producer = Thread.new { sink.succeed(:reply) }

      expect(future.await).to eq(:reply)
      expect(future.await).to eq(:reply)
      expect(future).to be_ready
      producer.join
    end

    it 'propagates operation failures' do
      future, sink = described_class.build
      sink.fail(ArgumentError.new('bad request'))

      expect { future.await }.to raise_error(ArgumentError, 'bad request')
      expect { future.await }.to raise_error(ArgumentError, 'bad request')
    end

    it 'wakes multiple concurrent waiters with the same result' do
      future, sink = described_class.build
      waiters = 2.times.map { Thread.new { future.await } }

      sink.succeed(:reply)

      expect(waiters.map(&:value)).to eq([:reply, :reply])
    end

    it 'closes local delivery once' do
      close_count = 0
      future, sink = described_class.build(on_close: -> { close_count += 1 })

      2.times { future.close }

      expect(close_count).to eq(1)
      expect(sink.succeed(:reply)).to be(false)
      expect { future.await }.to raise_error(Nl::ClosedError, 'future is closed')
    end

    it 'closes without a callback' do
      future, sink = described_class.build

      future.close

      expect(sink.succeed(:reply)).to be(false)
    end

  end

  describe Nl::Async::Stream do
    it 'raises the public timeout error without closing the stream' do
      stream, sink = described_class.build

      expect { stream.next(timeout: 0.001) }.to raise_error(Nl::TimeoutError)

      sink.push(:reply)
      expect(stream.next).to eq(:reply)
      stream.close
    end

    it 'is a single-pass Enumerable' do
      stream, sink = described_class.build
      sink.push(1)
      sink.push(2)
      sink.finish

      expect(stream.to_a).to eq([1, 2])
      expect(stream.to_a).to eq([])
      expect { stream.next }.to raise_error(StopIteration)
      expect(stream).to be_closed
    end

    it 'distinguishes explicit closure from normal completion' do
      stream, = described_class.build

      stream.close

      expect { stream.each {} }.to raise_error(Nl::ClosedError, 'stream is closed')
      expect { stream.next }.to raise_error(Nl::ClosedError, 'stream is closed')
    end

    it 'wakes a consumer with the public closed error' do
      stream, = described_class.build
      started = Queue.new
      consumer = Thread.new do
        started << true
        stream.next
      rescue => error
        error
      end
      started.pop
      Thread.pass until consumer.status == 'sleep'

      stream.close

      expect(consumer.value).to be_a(Nl::ClosedError)
    end

    it 'propagates an error after already-delivered items' do
      stream, sink = described_class.build
      sink.push(1)
      sink.fail(RuntimeError.new('dump failed'))
      values = []

      expect { stream.each { values << it } }.to raise_error(RuntimeError, 'dump failed')
      expect(values).to eq([1])
    end

    it 'closes delivery when iteration stops early' do
      close_count = 0
      stream, sink = described_class.build(on_close: -> { close_count += 1 })
      sink.push(1)
      sink.push(2)

      stream.each { break }
      stream.close

      expect(close_count).to eq(1)
      expect(stream).to be_closed
      expect(sink.push(3)).to be(false)
    end

    it 'rejects consumption by a second fiber' do
      stream, sink = described_class.build
      sink.push(1)
      expect(stream.next).to eq(1)

      error = Fiber.new do
        stream.next
      rescue => exception
        exception
      end.resume

      expect(error).to be_a(Nl::Async::ConcurrentConsumptionError)
      sink.push(2)
      expect(stream.next).to eq(2)
      stream.close
    end
  end

  describe Nl::Async::Drivers do
    TestScheduler = Class.new do
      def initialize
        @ready = []
        @waiting = {}
      end

      def fiber(&block)
        Fiber.new(blocking: false, &block).tap { @ready << [it, nil] }
      end

      def io_wait(io, events, timeout = nil)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout if timeout
        @waiting[Fiber.current] = [io, events, deadline]
        Fiber.yield
      end

      def kernel_sleep(duration = nil)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration if duration
        @waiting[Fiber.current] = [nil, 0, deadline]
        Fiber.yield
      end

      def block(_blocker, timeout = nil)
        kernel_sleep(timeout)
        true
      end

      def unblock(_blocker, fiber)
        @waiting.delete(fiber)
        @ready << [fiber, nil]
      end

      def fiber_interrupt(fiber, exception)
        @waiting.delete(fiber)
        fiber.raise(exception)
      end

      def run
        loop do
          while entry = @ready.shift
            fiber, value = entry
            fiber.resume(value) if fiber.alive?
          end
          break if @waiting.empty?

          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          closed, open = @waiting.partition { |_fiber, (io, _events, _deadline)| io&.closed? }
          closed.each do |fiber, _waiting|
            @waiting.delete(fiber)
            @ready << [fiber, 0]
          end
          next unless @ready.empty?

          readers = open.filter_map { |_fiber, (io, events, _deadline)| io if io && events & IO::READABLE != 0 }
          writers = open.filter_map { |_fiber, (io, events, _deadline)| io if io && events & IO::WRITABLE != 0 }
          deadlines = open.filter_map { |_fiber, (_io, _events, deadline)| deadline }
          timeout = deadlines.empty? ? nil : [deadlines.min - now, 0].max
          readable, writable = IO.select(readers, writers, [], timeout)
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          @waiting.to_a.each do |fiber, (io, events, deadline)|
            result = 0
            result |= IO::READABLE if readable&.include?(io) && events & IO::READABLE != 0
            result |= IO::WRITABLE if writable&.include?(io) && events & IO::WRITABLE != 0
            next if result == 0 && !(deadline && deadline <= now)

            @waiting.delete(fiber)
            @ready << [fiber, result]
          end
        end
      end

      def close
        run
      end
    end

    it 'runs work with the thread driver' do
      task = Nl::Async::Drivers::Thread.new.start { 42 }

      expect(task.value).to eq(42)
    end

    it 'requires a scheduler for the fiber driver' do
      expect do
        Nl::Async::Drivers::Fiber.new.start {}
      end.to raise_error(ArgumentError, 'Fiber.scheduler is not installed')
    end

    it 'suspends and wakes a scheduled fiber through the mailbox' do
      scheduler = TestScheduler.new
      Fiber.set_scheduler(scheduler)
      mailbox = Nl::Async::Mailbox.new
      result = nil

      Fiber.schedule { result = mailbox.pop }
      Fiber.schedule { mailbox.push(:reply) }
      scheduler.run

      expect(result).to eq(:reply)
    ensure
      mailbox&.close
      Fiber.set_scheduler(nil)
    end
  end

  describe Nl::Async::Dispatcher do
    FakeRequest = Class.new do
      const_set(:TYPE, 42)

      def self.from_params(_params) = new
    end

    FakeSocket = Class.new do
      def initialize(socket)
        @socket = socket
      end

      def local_port_id = 77

      def wait_readable = @socket.wait_readable

      def recvmsg_nonblock(exception: true)
        value = @socket.read_nonblock(65_536, exception:)
        value == :wait_readable ? value : [value]
      end

      def closed? = @socket.closed?
      def close = @socket.close
      def add_membership(_group_id) = nil
      def drop_membership(_group_id) = nil
    end

    FakeProtocol = Class.new do
      attr_reader :sent

      def initialize
        @raw = Nl::Protocols::Raw.new('fake', 0)
        @sent = []
      end

      def send_message(_socket, request, seq:, pid:)
        @sent << [request, seq, pid]
      end

      def build_request(kind, request_class, args)
        @raw.build_request(kind, request_class, args)
      end

      def decode_frame(header, payload, _reply_class)
        if header.type < Nl::Core::NLMSG_MIN_TYPE
          @raw.decode_frame(header, payload, nil)
        else
          Nl::Protocols::Raw::DataFrame.new(header:, message: payload.get_string)
        end
      end


      def notification_frame?(header, _payload) = header.type == 43
      def notification_class(header, _payload, classes) = classes[header.type]
      def decode_notification(_header, payload, _message_class) = payload.get_string
    end

    def frame(type:, sequence:, flags: 0, payload: ''.b)
      encoder = Nl::Encoder.new
      encoder.measure(Nl::Endian::Host::U32) do
        Nl::Core::NlMsgHdr.new(0, type, flags, sequence, 77).encode(encoder)
        encoder.put_string(payload)
      end
      encoder.align_to(Nl::Core::NLMSG_ALIGNTO)
      encoder.buffer.get_string
    end

    def control_frame(type:, sequence:, errno: nil)
      payload = errno.nil? ? ''.b : [errno].pack('i!')
      frame(type:, sequence:, payload:)
    end

    before do
      receiver, @sender = ::Socket.pair(:UNIX, :STREAM, 0)
      @socket = FakeSocket.new(receiver)
      @protocol = FakeProtocol.new
      @notifications = Nl::NotificationRouter.new(
        routing: Nl::Protocols::Raw.new('fake', 0).notification_routing,
        capacity: 1_024,
      )
      @dispatcher = described_class.new(
        @socket,
        executor: :thread,
        notifications: @notifications,
      )
    end

    after do
      @dispatcher.close
      @sender.close
    end

    it 'is async-capable' do
      expect(@dispatcher).to be_async_capable
    end

    it 'fails pending and new operations with the public closed error' do
      future = @dispatcher.exchange_async(@protocol, :do, FakeRequest, String, {})

      @dispatcher.close

      expect { future.await }.to raise_error(Nl::ClosedError, 'dispatcher is closed')
      expect do
        @dispatcher.exchange_async(@protocol, :do, FakeRequest, String, {})
      end.to raise_error(Nl::ClosedError, 'dispatcher is closed')
    end

    it 'waits for ACK before completing a request' do
      future = @dispatcher.exchange_async(@protocol, :do, FakeRequest, String, {})
      @sender.write(
        frame(type: 42, sequence: 1, payload: 'reply') +
          control_frame(type: Nl::Core::NLMSG_ERROR, sequence: 1, errno: 0),
      )

      expect(future.await(timeout: 1)).to eq('reply')
    end

    it 'routes interleaved replies by sequence number' do
      first = @dispatcher.exchange_async(@protocol, :do, FakeRequest, String, {})
      second = @dispatcher.exchange_async(@protocol, :do, FakeRequest, String, {})
      @sender.write(
        frame(type: 42, sequence: 2, payload: 'second') +
          control_frame(type: Nl::Core::NLMSG_ERROR, sequence: 2, errno: 0) +
          frame(type: 42, sequence: 1, payload: 'first') +
          control_frame(type: Nl::Core::NLMSG_ERROR, sequence: 1, errno: 0),
      )

      expect(first.await(timeout: 1)).to eq('first')
      expect(second.await(timeout: 1)).to eq('second')
    end

    it 'routes unsolicited notifications without disturbing a pending exchange' do
      @notifications.register(@protocol, 43 => String)
      future = @dispatcher.exchange_async(@protocol, :do, FakeRequest, String, {})
      @sender.write(
        frame(type: 43, sequence: 0, payload: 'notice') +
          frame(type: 42, sequence: 1, payload: 'reply') +
          control_frame(type: Nl::Core::NLMSG_ERROR, sequence: 1, errno: 0),
      )

      expect(future.await(timeout: 1)).to eq('reply')
      expect(@dispatcher.receive_notification(@protocol, timeout: 1)).to eq('notice')
    end

    it 'reports ENOBUFS to blocking exchanges and notification waiters' do
      @notifications.register(@protocol, 43 => String)
      original_receive = @socket.method(:recvmsg_nonblock)
      first_receive = true
      allow(@socket).to receive(:recvmsg_nonblock) do |exception: true|
        value = original_receive.call(exception:)
        if first_receive
          first_receive = false
          raise Errno::ENOBUFS
        end
        value
      end
      sent = Queue.new
      allow(@protocol).to receive(:send_message).and_wrap_original do |method, *args, **kwargs|
        method.call(*args, **kwargs).tap { sent << kwargs[:seq] }
      end

      notification = Thread.new do
        @dispatcher.receive_notification(@protocol, timeout: 1)
      rescue StandardError => error
        error
      end
      exchange = Thread.new do
        @dispatcher.exchange(@protocol, :do, FakeRequest, String, {})
      rescue StandardError => error
        error
      end
      expect(sent.pop(timeout: 1)).to eq(1)
      @sender.write('wake')

      expect(exchange.value).to be_a(Errno::ENOBUFS)
      expect(notification.value).to be_a(Nl::NotificationLossError)

      next_exchange = Thread.new do
        @dispatcher.exchange(@protocol, :do, FakeRequest, String, {})
      end
      expect(sent.pop(timeout: 1)).to eq(2)
      @sender.write(
        frame(type: 42, sequence: 2, payload: 'reply') +
          control_frame(type: Nl::Core::NLMSG_ERROR, sequence: 2, errno: 0),
      )
      expect(next_exchange.value).to eq('reply')
    end

    it 'retains a request when ACK arrives before its reply' do
      future = @dispatcher.exchange_async(@protocol, :do, FakeRequest, String, {})
      @sender.write(
        control_frame(type: Nl::Core::NLMSG_ERROR, sequence: 1, errno: 0) +
          frame(type: 42, sequence: 1, payload: 'reply'),
      )

      expect(future.await(timeout: 1)).to eq('reply')
    end

    it 'streams multipart replies until DONE' do
      stream = @dispatcher.exchange_async(@protocol, :dump, FakeRequest, String, {})
      @sender.write(
        frame(type: 42, sequence: 1, flags: Nl::Core::NLM_F_MULTI, payload: 'one') +
          frame(type: 42, sequence: 1, flags: Nl::Core::NLM_F_MULTI, payload: 'two') +
          control_frame(type: Nl::Core::NLMSG_DONE, sequence: 1, errno: 0),
      )

      expect(stream.to_a).to eq(%w[one two])
    end

    it 'returns the first multipart do reply after header-only DONE' do
      future = @dispatcher.exchange_async(@protocol, :do, FakeRequest, String, {})
      @sender.write(
        frame(type: 42, sequence: 1, flags: Nl::Core::NLM_F_MULTI, payload: 'one') +
          control_frame(type: Nl::Core::NLMSG_ERROR, sequence: 1, errno: 0) +
          frame(type: 42, sequence: 1, flags: Nl::Core::NLM_F_MULTI, payload: 'two') +
          control_frame(type: Nl::Core::NLMSG_DONE, sequence: 1),
      )

      expect(future.await(timeout: 1)).to eq('one')
    end

    it 'fails a multipart do reply with inconsistent data flags' do
      future = @dispatcher.exchange_async(@protocol, :do, FakeRequest, String, {})
      @sender.write(
        frame(type: 42, sequence: 1, flags: Nl::Core::NLM_F_MULTI, payload: 'one') +
          frame(type: 42, sequence: 1, payload: 'two'),
      )

      expect { future.await(timeout: 1) }.to raise_error(Nl::ProtocolViolation)
    end

    it 'turns NLMSG_ERROR into a failed operation' do
      future = @dispatcher.exchange_async(@protocol, :do, FakeRequest, String, {})
      @sender.write(control_frame(type: Nl::Core::NLMSG_ERROR, sequence: 1, errno: -22))

      expect { future.await(timeout: 1) }.to raise_error(Errno::EINVAL)
    end

    it 'yields partial dump replies before raising an error carried by DONE' do
      stream = @dispatcher.exchange_async(@protocol, :dump, FakeRequest, String, {})
      @sender.write(
        frame(type: 42, sequence: 1, flags: Nl::Core::NLM_F_MULTI, payload: 'one') +
          control_frame(type: Nl::Core::NLMSG_DONE, sequence: 1, errno: -Errno::EINVAL::Errno),
      )
      replies = []

      expect do
        stream.each { replies << it }
      end.to raise_error(Errno::EINVAL)
      expect(replies).to eq(['one'])
    end

    it 'fails only an overflowing stream' do
      stream = @dispatcher.exchange_async(@protocol, :dump, FakeRequest, String, {}, stream_capacity: 1)
      @sender.write(
        frame(type: 42, sequence: 1, flags: Nl::Core::NLM_F_MULTI, payload: 'one') +
          frame(type: 42, sequence: 1, flags: Nl::Core::NLM_F_MULTI, payload: 'two'),
      )

      expect { stream.to_a }.to raise_error(Nl::Async::StreamOverflowError)
    end

    it 'closes notification channels when the receive loop fails' do
      @notifications.register(@protocol, 43 => String)
      allow(@socket).to receive(:recvmsg_nonblock).and_raise(IOError, 'receive failed')
      @sender.write('wake')

      expect do
        @dispatcher.receive_notification(@protocol, timeout: 1)
      end.to raise_error(Nl::ClosedError, 'notification channel is closed')
    end

  end
end
