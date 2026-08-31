# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Genl::Connection do
  GenlFakeSocket = Struct.new(:bound_address, :closed) do
    def bind(address) = self.bound_address = address
    def close = self.closed = true
    def closed? = !!closed
    def add_membership(_group_id) = nil
    def drop_membership(_group_id) = nil
    def local_port_id = 77
  end

  GenlIdleDriver = Class.new do
    attr_reader :task

    def start(&block)
      @task = block
      Object.new
    end

    def stop(_task) = nil
  end

  GenlControllerFamily = Class.new(Nl::Family)
  GenlControllerFamily.const_set(
    :PROTOCOL,
    Nl::Protocols::Genl.new('nlctrl'),
  )

  GenlDynamicFamily = Class.new(Nl::Family)
  GenlDynamicFamily.const_set(
    :PROTOCOL,
    Nl::Protocols::Genl.new('dynamic-family'),
  )
  GenlDynamicFamily.const_set(
    :MCAST_GROUPS,
    {events: Nl::McastGroup.new('events', nil)}.freeze,
  )

  it 'resolves a family through one asynchronous connection and socket' do
    socket = GenlFakeSocket.new
    driver = GenlIdleDriver.new
    resolver_calls = 0
    controller = nil
    conn = nil
    resolver = lambda do |connection, name|
      resolver_calls += 1
      expect(connection).to be(conn)
      expect(name).to eq('dynamic-family')
      controller = connection.family(GenlControllerFamily)
      42
    end
    expect(Nl::Socket).to receive(:new).once.with(Nl::Core::NETLINK_GENERIC).and_return(socket)

    conn = described_class.new(resolver:, executor: driver)
    family = conn.family(GenlDynamicFamily)
    cached_family = conn.family(GenlDynamicFamily)

    connection = conn.instance_variable_get(:@connection)
    transport = connection.instance_variable_get(:@transport)
    expect(transport).to be_a(Nl::Async::Dispatcher)
    expect(controller.instance_variable_get(:@connection)).to equal(connection)
    expect(family.instance_variable_get(:@connection)).to equal(connection)
    expect(cached_family.instance_variable_get(:@connection)).to equal(connection)
    expect(transport.instance_variable_get(:@socket)).to equal(socket)
    expect(family).not_to respond_to(:close)
    expect(family.instance_variable_get(:@protocol).family_id).to eq(42)
    expect(resolver_calls).to eq(1)
  ensure
    conn&.close
  end

  it 'shares one connection across synchronous families' do
    socket = GenlFakeSocket.new
    conn = nil
    expect(Nl::Socket).to receive(:new).once.with(Nl::Core::NETLINK_GENERIC).and_return(socket)

    conn = described_class.new(resolver: ->(_connection, _name) { 42 })
    first = conn.family(GenlDynamicFamily)
    second = conn.family(GenlDynamicFamily)

    connection = conn.instance_variable_get(:@connection)
    transport = connection.instance_variable_get(:@transport)
    expect(transport).to be_a(Nl::BlockingTransport)
    expect(first.instance_variable_get(:@connection)).to equal(connection)
    expect(second.instance_variable_get(:@connection)).to equal(connection)
    expect(transport.instance_variable_get(:@socket)).to equal(socket)
  ensure
    conn&.close
  end


  it 'uses resolved Generic Netlink multicast group IDs on the shared socket' do
    socket = GenlFakeSocket.new
    expect(Nl::Socket).to receive(:new).once.with(Nl::Core::NETLINK_GENERIC).and_return(socket)
    expect(socket).to receive(:add_membership).once.with(99)

    info = Nl::Genl::FamilyInfo.new(id: 42, multicast_groups: {events: 99})
    conn = described_class.new(resolver: ->(_connection, _name) { info })
    family = conn.family(GenlDynamicFamily)

    expect(family.subscribe(:events)).to equal(family)
  ensure
    conn&.close
  end
end
