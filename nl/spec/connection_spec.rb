# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Connection do
  ConnectionFakeSocket = Struct.new(:bound_address, :closed) do
    def bind(address) = self.bound_address = address
    def close = self.closed = true
    def closed? = !!closed
    def add_membership(_group_id) = nil
    def drop_membership(_group_id) = nil
  end

  let(:protocol) { Nl::Protocols::Raw.new('fake', 12) }

  it 'owns the socket and multicast memberships' do
    socket = ConnectionFakeSocket.new
    expect(Nl::Socket).to receive(:new).once.with(12).and_return(socket)
    expect(socket).to receive(:add_membership).with(7)
    expect(socket).to receive(:add_membership).with(8)
    expect(socket).to receive(:drop_membership).with(7)

    connection = described_class.new(protocol:)
    connection.add_memberships([7, 8])
    connection.drop_memberships([7])
    connection.close

    expect(socket.bound_address).to eq(Nl::Socket.sockaddr_nl(0, 0))
    expect(socket).to be_closed
  end

  it 'closes notification channels when transport shutdown fails' do
    socket = ConnectionFakeSocket.new
    allow(Nl::Socket).to receive(:new).with(12).and_return(socket)
    allow(socket).to receive(:close).and_raise(IOError, 'socket close failed')
    connection = described_class.new(protocol:)
    channel = connection.register_notifications(protocol, {})

    expect { connection.close }.to raise_error(IOError, 'socket close failed')
    expect { channel.pop }.to raise_error(Nl::ClosedError, 'notification channel is closed')
  end
end
