# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Family do
  FamilyFakeSocket = Struct.new(:bound_address, :closed) do
    def bind(address) = self.bound_address = address
    def close = self.closed = true
    def closed? = !!closed
    def add_membership(_group_id) = nil
    def drop_membership(_group_id) = nil
  end

  StandaloneFamily = Class.new(described_class)
  StandaloneFamily.const_set(:PROTOCOL, Nl::Protocols::Raw.new('standalone', 12))
  StandaloneFamily.const_set(:MCAST_GROUPS, {events: 7}.freeze)
  StandaloneFamily.class_eval do
    def do_action(value, option:, &block) = [value, option, block&.call]
    def dump_items(limit:) = (1..limit).to_a
    def async(stream_capacity: nil) = [:async, stream_capacity]
  end

  it 'returns an owning session without a block' do
    socket = FamilyFakeSocket.new
    expect(Nl::Socket).to receive(:new).once.with(12).and_return(socket)

    session = StandaloneFamily.open

    expect(session).to be_a(StandaloneFamily)
    expect(socket).not_to be_closed

    session.close
    expect(socket).to be_closed
  end

  it 'owns and closes its connection around the block' do
    socket = FamilyFakeSocket.new
    family = nil
    expect(Nl::Socket).to receive(:new).once.with(12).and_return(socket)

    result = StandaloneFamily.open do |opened_family|
      family = opened_family
      expect(family).to be_a(StandaloneFamily)
      expect(family).to respond_to(:close)
      expect(socket).not_to be_closed
      :result
    end

    expect(result).to eq(:result)
    expect(socket).to be_closed
  end

  it 'closes its connection when the block raises' do
    socket = FamilyFakeSocket.new
    expect(Nl::Socket).to receive(:new).once.with(12).and_return(socket)

    expect do
      StandaloneFamily.open { raise 'failed' }
    end.to raise_error(RuntimeError, 'failed')

    expect(socket).to be_closed
  end


  it 'adds and removes memberships on its existing socket' do
    socket = FamilyFakeSocket.new
    expect(Nl::Socket).to receive(:new).once.with(12).and_return(socket)
    expect(socket).to receive(:add_membership).twice.with(7)
    expect(socket).to receive(:drop_membership).once.with(7)

    StandaloneFamily.open do |family|
      expect(family.subscribe(:events)).to equal(family)
      family.subscribe(:events)
      expect(family.unsubscribe(:events)).to equal(family)
    end
  end

  it 'rejects an unknown multicast group before changing the socket' do
    socket = FamilyFakeSocket.new
    expect(Nl::Socket).to receive(:new).once.with(12).and_return(socket)
    expect(socket).not_to receive(:add_membership)

    StandaloneFamily.open do |family|
      expect { family.subscribe(:missing) }.to raise_error(Nl::UnknownMulticastGroupError)
    end
  end
end
