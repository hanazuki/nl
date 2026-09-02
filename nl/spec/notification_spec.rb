# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::NotificationChannel do
  it 'reports a full queue once and resumes with later notifications' do
    channel = described_class.new(capacity: 1)
    channel.push(:stale)
    channel.push(:overflow)
    channel.push(:after_loss)

    expect { channel.pop }.to raise_error(Nl::NotificationLossError)
    expect(channel.pop).to eq(:after_loss)
  end

  it 'supports notification receive timeouts' do
    channel = described_class.new(capacity: 1)

    expect { channel.pop(timeout: 0) }.to raise_error(Nl::TimeoutError)
  end

  it 'wakes a waiting consumer when closed' do
    channel = described_class.new(capacity: 1)
    result = Queue.new
    waiter = Thread.new do
      channel.pop
    rescue Exception => error
      result << error
    end

    channel.close

    expect(result.pop).to be_a(Nl::ClosedError)
    waiter.join
  end
end

RSpec.describe Nl::NotificationRouter do
  NotificationHeader = Data.define(:type)

  NotificationProtocol = Class.new do
    def family_key(endpoint) = endpoint
    def frame_key(header) = header.type
    def notification_frame?(_endpoint, _header, _payload) = true
    def notification_class(_endpoint, _header, _payload, _classes) = nil
    def decode_notification(*) = raise 'must not decode an unknown notification'
  end

  it 'consumes a notification without a decoder without enqueueing it' do
    router = described_class.new(protocol: NotificationProtocol.new, capacity: 1)
    channel = router.register(42, {})

    expect(router.route(NotificationHeader.new(type: 42), IO::Buffer.for('payload'))).to be(true)
    expect(channel).to be_empty
  ensure
    router&.close
  end
end
