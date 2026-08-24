# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Exchange do
  let(:reply) { Object.new }

  it 'completes a do exchange after reply followed by ACK' do
    exchange = described_class.new(kind: :do, expects_reply: true)

    expect(exchange.accept(reply)).to be_a(Nl::Exchange::Ignore)
    expect(exchange.accept(Nl::Protocols::Raw::Ack.new)).to eq(Nl::Exchange::Complete.new(reply))
    expect(exchange.result).to equal(reply)
  end

  it 'completes a do exchange when reply arrives after ACK' do
    exchange = described_class.new(kind: :do, expects_reply: true)

    expect(exchange.accept(Nl::Protocols::Raw::Ack.new)).to be_a(Nl::Exchange::Ignore)
    expect(exchange.accept(reply)).to eq(Nl::Exchange::Complete.new(reply))
  end

  it 'completes an operation without a reply on ACK' do
    exchange = described_class.new(kind: :do, expects_reply: false)

    expect(exchange.accept(Nl::Protocols::Raw::Ack.new)).to eq(Nl::Exchange::Complete.new(nil))
  end

  it 'emits dump items until DONE' do
    exchange = described_class.new(kind: :dump, expects_reply: true)

    expect(exchange.accept(reply)).to eq(Nl::Exchange::Item.new(reply))
    expect(exchange.accept(Nl::Protocols::Raw::Done.new(error: nil))).to eq(Nl::Exchange::Complete.new(nil))
  end

  it 'preserves a do reply when DONE terminates the exchange' do
    exchange = described_class.new(kind: :do, expects_reply: true)
    exchange.accept(reply)

    expect(exchange.accept(Nl::Protocols::Raw::Done.new(error: nil))).to eq(Nl::Exchange::Complete.new(reply))
  end

  it 'turns an error carried by DONE into a failure' do
    exchange = described_class.new(kind: :dump, expects_reply: true)
    error = Errno::EINVAL.new

    expect(exchange.accept(Nl::Protocols::Raw::Done.new(error:))).to eq(Nl::Exchange::Failure.new(error))
    expect(exchange).to be_complete
  end

  it 'discards an error carried by DONE after cancellation' do
    exchange = described_class.new(kind: :dump, expects_reply: true)
    exchange.cancel

    outcome = exchange.accept(Nl::Protocols::Raw::Done.new(error: Errno::EINVAL.new))

    expect(outcome).to eq(Nl::Exchange::Complete.new(nil))
    expect(exchange).to be_cancelled
  end

  it 'turns a protocol exception into a failure' do
    exchange = described_class.new(kind: :do, expects_reply: true)
    error = Errno::EINVAL.new

    expect(exchange.accept(error)).to eq(Nl::Exchange::Failure.new(error))
    expect(exchange).to be_complete
  end

  it 'rejects multiple replies for a do exchange' do
    exchange = described_class.new(kind: :do, expects_reply: true)
    exchange.accept(reply)

    outcome = exchange.accept(Object.new)

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Nl::Exchange::UnexpectedReplyError)
  end

  it 'discards replies after cancellation and completes on ACK' do
    exchange = described_class.new(kind: :do, expects_reply: true)
    exchange.cancel

    expect(exchange.accept(reply)).to be_a(Nl::Exchange::Ignore)
    expect(exchange.accept(Nl::Protocols::Raw::Ack.new)).to eq(Nl::Exchange::Complete.new(nil))
    expect(exchange).to be_cancelled
  end
end
