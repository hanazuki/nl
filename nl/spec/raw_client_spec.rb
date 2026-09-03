# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Raw::Client do
  RawClientFakeSocket = Struct.new(:bound_address, :closed) do
    def bind(address) = self.bound_address = address
    def close = self.closed = true
    def closed? = !!closed
    def add_membership(_group_id) = nil
    def drop_membership(_group_id) = nil
  end

  RawClientNotification = Class.new do
    def self.decode(decoder, type:)
      [type, decoder.get_string]
    end
  end

  RawClientFirstFamily = Class.new(Nl::Raw::Family)
  RawClientFirstFamily.const_set(:NAME, 'first')
  RawClientFirstFamily.const_set(:PROTONUM, 12)
  RawClientFirstFamily.const_set(:NOTIFICATIONS, {41 => RawClientNotification}.freeze)

  RawClientSecondFamily = Class.new(Nl::Raw::Family)
  RawClientSecondFamily.const_set(:NAME, 'second')
  RawClientSecondFamily.const_set(:PROTONUM, 12)
  RawClientSecondFamily.const_set(:NOTIFICATIONS, {42 => RawClientNotification}.freeze)

  RawClientOtherProtocolFamily = Class.new(Nl::Raw::Family)
  RawClientOtherProtocolFamily.const_set(:NAME, 'other')
  RawClientOtherProtocolFamily.const_set(:PROTONUM, 15)

  RawClientConflictingFamily = Class.new(Nl::Raw::Family)
  RawClientConflictingFamily.const_set(:NAME, 'conflicting')
  RawClientConflictingFamily.const_set(:PROTONUM, 12)
  RawClientConflictingFamily.const_set(:NOTIFICATIONS, {41 => RawClientNotification}.freeze)

  it 'shares one connection across families with the same protonum' do
    socket = RawClientFakeSocket.new
    expect(Nl::Socket).to receive(:new).once.with(12).and_return(socket)

    client = described_class.new(protonum: 12)
    first = client.family(RawClientFirstFamily)
    second = client.family(RawClientSecondFamily)

    connection = client.instance_variable_get(:@connection)
    expect(first.instance_variable_get(:@connection)).to equal(connection)
    expect(second.instance_variable_get(:@connection)).to equal(connection)
    expect(first).not_to respond_to(:close)
    expect(second).not_to respond_to(:close)
  ensure
    client&.close
  end

  it 'routes notifications by message type to separate family channels' do
    socket = RawClientFakeSocket.new
    allow(Nl::Socket).to receive(:new).with(12).and_return(socket)
    client = described_class.new(protonum: 12)
    first = client.family(RawClientFirstFamily)
    second = client.family(RawClientSecondFamily)
    router = client.instance_variable_get(:@connection).instance_variable_get(:@notifications)

    first_header = Nl::Raw::NlMsgHdr.new(0, 41, 0, 0, 0)
    second_header = Nl::Raw::NlMsgHdr.new(0, 42, 0, 0, 0)
    router.route(first_header, IO::Buffer.for('first'))
    router.route(second_header, IO::Buffer.for('second'))

    expect(first.receive_notification(timeout: 0)).to eq([41, 'first'])
    expect(second.receive_notification(timeout: 0)).to eq([42, 'second'])
  ensure
    client&.close
  end

  it 'rejects a family using another protonum' do
    socket = RawClientFakeSocket.new
    allow(Nl::Socket).to receive(:new).with(12).and_return(socket)
    client = described_class.new(protonum: 12)

    expect do
      client.family(RawClientOtherProtocolFamily)
    end.to raise_error(ArgumentError, 'family protonum 15 does not match client protonum 12')
  ensure
    client&.close
  end

  it 'rejects notification types claimed by two families' do
    socket = RawClientFakeSocket.new
    allow(Nl::Socket).to receive(:new).with(12).and_return(socket)
    client = described_class.new(protonum: 12)
    client.family(RawClientFirstFamily)

    expect do
      client.family(RawClientConflictingFamily)
    end.to raise_error(ArgumentError, 'notification route 41 is already registered')
  ensure
    client&.close
  end

  it 'owns and closes its connection around a block' do
    socket = RawClientFakeSocket.new
    expect(Nl::Socket).to receive(:new).once.with(12).and_return(socket)

    result = described_class.open(protonum: 12) do |client|
      expect(socket).not_to be_closed
      expect(client.family(RawClientFirstFamily)).to be_a(RawClientFirstFamily)
      :result
    end

    expect(result).to eq(:result)
    expect(socket).to be_closed
  end
end
