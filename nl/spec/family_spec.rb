# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Family do
  FamilyFakeSocket = Struct.new(:bound_address, :closed) do
    def bind(address) = self.bound_address = address
    def close = self.closed = true
    def closed? = !!closed
  end

  StandaloneFamily = Class.new(described_class)
  StandaloneFamily.const_set(:PROTOCOL, Nl::Protocols::Raw.new('standalone', 12))
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

  it 'owns and closes its exchanger around the block' do
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

  it 'closes its exchanger when the block raises' do
    socket = FamilyFakeSocket.new
    expect(Nl::Socket).to receive(:new).once.with(12).and_return(socket)

    expect do
      StandaloneFamily.open { raise 'failed' }
    end.to raise_error(RuntimeError, 'failed')

    expect(socket).to be_closed
  end
end
