# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Exchange do
  Reply = Data.define(:value)

  let(:reply) { make_reply(:first) }

  def make_reply(value, flags: 0)
    header = Nl::Raw::NlMsgHdr.new(0, 42, flags, 1, 77)
    Nl::Raw::DataFrame.new(header:, message: Reply.new(value:))
  end

  def control_header(type) = Nl::Raw::NlMsgHdr.new(0, type, 0, 1, 77)
  def ack = Nl::Raw::AckFrame.new(header: control_header(Nl::Raw::NLMSG_ERROR))
  def done(errno: nil) = Nl::Raw::DoneFrame.new(header: control_header(Nl::Raw::NLMSG_DONE), errno:)
  def error_frame(errno) = Nl::Raw::ErrorFrame.new(header: control_header(Nl::Raw::NLMSG_ERROR), errno:)

  it 'defines protocol violations as Nl errors' do
    expect(Nl::ProtocolViolation).to be < Nl::Error
  end

  it 'rejects an unknown exchange mode' do
    expect { described_class.new(mode: :unknown) }.to raise_error(ArgumentError, /unknown exchange mode/)
  end

  it 'rejects inputs outside the frame model' do
    exchange = described_class.new(mode: :reply)

    expect { exchange.accept(Object.new) }.to raise_error(ArgumentError, /unexpected exchange input/)
  end

  it 'completes a do exchange after reply followed by ACK' do
    exchange = described_class.new(mode: :reply)

    expect(exchange.accept(reply)).to be_nil
    expect(exchange.accept(ack)).to equal(Nl::Exchange::COMPLETE)
    expect(exchange.result).to equal(reply.message)
  end

  it 'completes a do exchange when reply arrives after ACK' do
    exchange = described_class.new(mode: :reply)

    expect(exchange.accept(ack)).to be_nil
    expect(exchange.accept(reply)).to equal(Nl::Exchange::COMPLETE)
  end

  it 'completes an operation without a reply on ACK' do
    exchange = described_class.new(mode: :no_reply)

    expect(exchange.accept(ack)).to equal(Nl::Exchange::COMPLETE)
  end

  it 'rejects data for an operation without a reply' do
    exchange = described_class.new(mode: :no_reply)

    outcome = exchange.accept(reply)

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Nl::ProtocolViolation)
  end

  it 'emits dump items until DONE' do
    exchange = described_class.new(mode: :dump)
    reply = make_reply(:first, flags: Nl::Raw::NLM_F_MULTI)

    expect(exchange.accept(reply)).to eq(Nl::Exchange::Item.new(reply.message))
    expect(exchange.accept(done)).to equal(Nl::Exchange::COMPLETE)
  end

  it 'emits dump data without NLM_F_MULTI until DONE' do
    exchange = described_class.new(mode: :dump)

    expect(exchange.accept(reply)).to eq(Nl::Exchange::Item.new(reply.message))
    expect(exchange).not_to be_complete
    expect(exchange.accept(done)).to equal(Nl::Exchange::COMPLETE)
  end

  it 'keeps a dump exchange open when ACK arrives before DONE' do
    exchange = described_class.new(mode: :dump)

    expect(exchange.accept(ack)).to be_nil
    expect(exchange).not_to be_complete
    expect(exchange.accept(done)).to equal(Nl::Exchange::COMPLETE)
  end

  it 'accepts mixed NLM_F_MULTI flags in a dump' do
    exchange = described_class.new(mode: :dump)

    expect(exchange.accept(make_reply(:first, flags: Nl::Raw::NLM_F_MULTI))).to be_a(Nl::Exchange::Item)
    expect(exchange.accept(make_reply(:second))).to be_a(Nl::Exchange::Item)
    expect(exchange.accept(done)).to equal(Nl::Exchange::COMPLETE)
  end

  it 'returns the first reply when DONE terminates a multipart do exchange' do
    exchange = described_class.new(mode: :reply)
    first = make_reply(:first, flags: Nl::Raw::NLM_F_MULTI)
    second = make_reply(:second, flags: Nl::Raw::NLM_F_MULTI)
    exchange.accept(first)
    exchange.accept(second)

    expect(exchange.accept(done)).to equal(Nl::Exchange::COMPLETE)
    expect(exchange.result).to equal(first.message)
  end

  it 'keeps a multipart do exchange open when ACK arrives before DONE' do
    exchange = described_class.new(mode: :reply)
    first = make_reply(:first, flags: Nl::Raw::NLM_F_MULTI)

    expect(exchange.accept(first)).to be_nil
    expect(exchange.accept(ack)).to be_nil
    expect(exchange.accept(done)).to equal(Nl::Exchange::COMPLETE)
  end

  it 'turns an error carried by DONE into a failure' do
    exchange = described_class.new(mode: :dump)

    outcome = exchange.accept(done(errno: Errno::EINVAL::Errno))

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Errno::EINVAL)
    expect(exchange).to be_complete
  end

  it 'discards an error carried by DONE after cancellation' do
    exchange = described_class.new(mode: :dump)
    exchange.cancel

    outcome = exchange.accept(done(errno: Errno::EINVAL::Errno))

    expect(outcome).to equal(Nl::Exchange::COMPLETE)
    expect(exchange).to be_cancelled
  end

  it 'turns an error response into a failure' do
    exchange = described_class.new(mode: :reply)

    outcome = exchange.accept(error_frame(Errno::EINVAL::Errno))

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Errno::EINVAL)
    expect(exchange).to be_complete
  end

  it 'rejects multiple replies for a do exchange' do
    exchange = described_class.new(mode: :reply)
    exchange.accept(reply)

    outcome = exchange.accept(make_reply(:second))

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Nl::ProtocolViolation)
  end

  it 'rejects a non-multipart data frame in a multipart do exchange' do
    exchange = described_class.new(mode: :reply)
    exchange.accept(make_reply(:first, flags: Nl::Raw::NLM_F_MULTI))

    outcome = exchange.accept(make_reply(:second))

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Nl::ProtocolViolation)
  end

  it 'rejects a multipart data frame after a non-multipart one' do
    exchange = described_class.new(mode: :reply)
    exchange.accept(reply)

    outcome = exchange.accept(make_reply(:second, flags: Nl::Raw::NLM_F_MULTI))

    expect(outcome).to be_a(Nl::Exchange::Failure)
    expect(outcome.exception).to be_a(Nl::ProtocolViolation)
  end

  it 'discards replies after cancellation and completes on ACK' do
    exchange = described_class.new(mode: :reply)
    exchange.cancel

    expect(exchange.accept(reply)).to be_nil
    expect(exchange.accept(ack)).to equal(Nl::Exchange::COMPLETE)
    expect(exchange).to be_cancelled
  end

  it 'discards an error response after cancellation' do
    exchange = described_class.new(mode: :reply)
    exchange.cancel

    outcome = exchange.accept(error_frame(Errno::EINVAL::Errno))

    expect(outcome).to equal(Nl::Exchange::COMPLETE)
    expect(exchange).to be_cancelled
  end
end
