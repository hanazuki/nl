# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Raw::Protocol do
  FrameMessage = Class.new do
    const_set(:TYPE, 42)

    def self.decode(decoder, type:)
      raise "expected type #{self::TYPE}, got #{type}" unless type == self::TYPE

      decoder.get_string
    end
  end

  FakeFamily = Class.new do
    const_set(:NAME, 'fake')
  end

  subject(:protocol) { described_class.new(0) }
  let(:endpoint) { Nl::Raw::Endpoint.new(FakeFamily) }

  def decode_control(type, errno: nil)
    header = Nl::Raw::NlMsgHdr.new(0, type, 0, 1, 77)
    payload = errno.nil? ? ''.b : [errno].pack('i!')
    [header, protocol.decode_frame(endpoint, header, IO::Buffer.for(payload), nil)]
  end

  it 'decodes NLMSG_ERROR errno as data' do
    header, frame = decode_control(Nl::Raw::NLMSG_ERROR, errno: -Errno::EINVAL::Errno)
    expect(frame).to eq(Nl::Raw::ErrorFrame.new(header:, errno: Errno::EINVAL::Errno))
  end

  it 'decodes an ACK with its header' do
    header, frame = decode_control(Nl::Raw::NLMSG_ERROR, errno: 0)
    expect(frame).to eq(Nl::Raw::AckFrame.new(header:))
  end

  it 'decodes NLMSG_DONE errno as data' do
    header, frame = decode_control(Nl::Raw::NLMSG_DONE, errno: -Errno::EINVAL::Errno)
    expect(frame).to eq(Nl::Raw::DoneFrame.new(header:, errno: Errno::EINVAL::Errno))
  end

  it 'decodes a header-only NLMSG_DONE as successful completion' do
    header, frame = decode_control(Nl::Raw::NLMSG_DONE)
    expect(frame).to eq(Nl::Raw::DoneFrame.new(header:, errno: nil))
  end

  it 'decodes an unknown control message with its header' do
    header, frame = decode_control(Nl::Raw::NLMSG_NOOP)
    expect(frame).to eq(Nl::Raw::UnknownFrame.new(header:))
  end

  it 'decodes a data message into a frame' do
    header = Nl::Raw::NlMsgHdr.new(0, FrameMessage::TYPE, Nl::Raw::NLM_F_MULTI, 1, 77)
    frame = protocol.decode_frame(endpoint, header, IO::Buffer.for('reply'), FrameMessage)
    expect(frame).to eq(Nl::Raw::DataFrame.new(header:, message: 'reply'))
  end
end
