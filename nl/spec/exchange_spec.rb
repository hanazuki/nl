# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Exchange do
  Reply = Data.define(:value, :nlmsg_header)

  let(:reply) { make_reply(:first) }

  def make_reply(value, flags: 0)
    Reply.new(value:, nlmsg_header: Nl::Core::NlMsgHdr.new(0, 42, flags, 1, 77))
  end

  it 'defines protocol violations as Nl errors' do
    expect(Nl::ProtocolViolation).to be < Nl::Error
  end

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
    reply = make_reply(:first, flags: Nl::Core::NLM_F_MULTI)

    expect(exchange.accept(reply)).to eq(Nl::Exchange::Item.new(reply))
    expect(exchange.accept(Nl::Protocols::Raw::Done.new(error: nil))).to eq(Nl::Exchange::Complete.new(nil))
  end

  it 'rejects a dump data frame without NLM_F_MULTI' do
    exchange = described_class.new(kind: :dump, expects_reply: true)

    outcome = exchange.accept(reply)

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Nl::ProtocolViolation)
  end

  it 'keeps a dump exchange open when ACK arrives before DONE' do
    exchange = described_class.new(kind: :dump, expects_reply: true)

    expect(exchange.accept(Nl::Protocols::Raw::Ack.new)).to be_a(Nl::Exchange::Ignore)
    expect(exchange).not_to be_complete
    expect(exchange.accept(Nl::Protocols::Raw::Done.new(error: nil))).to eq(Nl::Exchange::Complete.new(nil))
  end

  it 'rejects inconsistent data flags in a multipart dump' do
    exchange = described_class.new(kind: :dump, expects_reply: true)

    expect(exchange.accept(make_reply(:first, flags: Nl::Core::NLM_F_MULTI))).to be_a(Nl::Exchange::Item)
    outcome = exchange.accept(make_reply(:second))

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Nl::ProtocolViolation)
  end

  it 'returns the first reply when DONE terminates a multipart do exchange' do
    exchange = described_class.new(kind: :do, expects_reply: true)
    first = make_reply(:first, flags: Nl::Core::NLM_F_MULTI)
    second = make_reply(:second, flags: Nl::Core::NLM_F_MULTI)
    exchange.accept(first)
    exchange.accept(second)

    expect(exchange.accept(Nl::Protocols::Raw::Done.new(error: nil))).to eq(Nl::Exchange::Complete.new(first))
    expect(exchange.result).to equal(first)
  end

  it 'keeps a multipart do exchange open when ACK arrives before DONE' do
    exchange = described_class.new(kind: :do, expects_reply: true)
    first = make_reply(:first, flags: Nl::Core::NLM_F_MULTI)

    expect(exchange.accept(first)).to be_a(Nl::Exchange::Ignore)
    expect(exchange.accept(Nl::Protocols::Raw::Ack.new)).to be_a(Nl::Exchange::Ignore)
    expect(exchange.accept(Nl::Protocols::Raw::Done.new(error: nil))).to eq(Nl::Exchange::Complete.new(first))
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

    outcome = exchange.accept(make_reply(:second))

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Nl::ProtocolViolation)
  end

  it 'rejects a non-multipart data frame in a multipart do exchange' do
    exchange = described_class.new(kind: :do, expects_reply: true)
    exchange.accept(make_reply(:first, flags: Nl::Core::NLM_F_MULTI))

    outcome = exchange.accept(make_reply(:second))

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Nl::ProtocolViolation)
  end

  it 'rejects a multipart data frame after a non-multipart one' do
    exchange = described_class.new(kind: :do, expects_reply: true)
    exchange.accept(reply)

    outcome = exchange.accept(make_reply(:second, flags: Nl::Core::NLM_F_MULTI))

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Nl::ProtocolViolation)
  end

  it 'discards replies after cancellation and completes on ACK' do
    exchange = described_class.new(kind: :do, expects_reply: true)
    exchange.cancel

    expect(exchange.accept(reply)).to be_a(Nl::Exchange::Ignore)
    expect(exchange.accept(Nl::Protocols::Raw::Ack.new)).to eq(Nl::Exchange::Complete.new(nil))
    expect(exchange).to be_cancelled
  end
end
