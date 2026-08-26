# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Genl::Connection do
  GenlFakeSocket = Struct.new(:bound_address, :closed) do
    def bind(address) = self.bound_address = address
    def close = self.closed = true
    def closed? = !!closed
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

  it 'resolves and opens a family through one asynchronous exchanger and socket' do
    socket = GenlFakeSocket.new
    driver = GenlIdleDriver.new
    resolver_calls = 0
    controller = nil
    conn = nil
    resolver = lambda do |connection, name|
      resolver_calls += 1
      expect(connection).to be(conn)
      expect(name).to eq('dynamic-family')
      controller = connection.open(GenlControllerFamily)
      42
    end
    expect(Nl::Socket).to receive(:new).once.with(Nl::Core::NETLINK_GENERIC).and_return(socket)

    conn = described_class.new(resolver:, executor: driver)
    family = conn.open(GenlDynamicFamily)
    cached_family = conn.open(GenlDynamicFamily)

    exchanger = conn.instance_variable_get(:@exchanger)
    expect(exchanger).to be_a(Nl::Async::Dispatcher)
    expect(controller.instance_variable_get(:@exchanger)).to equal(exchanger)
    expect(family.instance_variable_get(:@exchanger)).to equal(exchanger)
    expect(cached_family.instance_variable_get(:@exchanger)).to equal(exchanger)
    expect(exchanger.instance_variable_get(:@socket)).to equal(socket)
    expect(family).not_to respond_to(:close)
    expect(family.instance_variable_get(:@protocol).family_id).to eq(42)
    expect(resolver_calls).to eq(1)
  ensure
    conn&.close
  end

  it 'shares one blocking exchanger across synchronous families' do
    socket = GenlFakeSocket.new
    conn = nil
    expect(Nl::Socket).to receive(:new).once.with(Nl::Core::NETLINK_GENERIC).and_return(socket)

    conn = described_class.new(resolver: ->(_connection, _name) { 42 })
    first = conn.open(GenlDynamicFamily)
    second = conn.open(GenlDynamicFamily)

    exchanger = conn.instance_variable_get(:@exchanger)
    expect(exchanger).to be_a(Nl::BlockingTransport)
    expect(first.instance_variable_get(:@exchanger)).to equal(exchanger)
    expect(second.instance_variable_get(:@exchanger)).to equal(exchanger)
    expect(exchanger.instance_variable_get(:@socket)).to equal(socket)
  ensure
    conn&.close
  end
end
