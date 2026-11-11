# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Raw::Protocol do
  FrameMessage = Class.new do
    const_set(:TYPE, 42)

    def self.decode(decoder)
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
    protocol.decode_frame(endpoint, header, Nl::Decoder.new(IO::Buffer.for(payload)), nil)
  end

  it 'decodes NLMSG_ERROR errno as data' do
    frame = decode_control(Nl::Raw::NLMSG_ERROR, errno: -Errno::EINVAL::Errno)
    expect(frame).to eq(Nl::Raw::Error.new(errno: Errno::EINVAL::Errno))
  end

  it 'returns the shared ACK result' do
    frame = decode_control(Nl::Raw::NLMSG_ERROR, errno: 0)
    expect(frame).to equal(Nl::Raw::ACK)
  end

  it 'decodes NLMSG_DONE errno as data' do
    frame = decode_control(Nl::Raw::NLMSG_DONE, errno: -Errno::EINVAL::Errno)
    expect(frame).to eq(Nl::Raw::Done.new(errno: Errno::EINVAL::Errno))
  end

  it 'decodes a header-only NLMSG_DONE as successful completion' do
    frame = decode_control(Nl::Raw::NLMSG_DONE)
    expect(frame).to equal(Nl::Raw::DONE)
  end

  it 'returns the shared unknown control result' do
    frame = decode_control(Nl::Raw::NLMSG_NOOP)
    expect(frame).to equal(Nl::Raw::UNKNOWN)
  end

  it 'reuses successful completion for NLMSG_DONE with zero errno' do
    expect(decode_control(Nl::Raw::NLMSG_DONE, errno: 0)).to equal(Nl::Raw::DONE)
  end

  [Nl::Raw::NLMSG_ERROR, Nl::Raw::NLMSG_DONE].each do |type|
    it "rejects positive errno in control message #{type}" do
      expect { decode_control(type, errno: 1) }.to raise_error(Nl::ProtocolViolation, /expected zero or negative/)
    end
  end

  it 'returns a decoded data message directly' do
    header = Nl::Raw::NlMsgHdr.new(0, FrameMessage::TYPE, Nl::Raw::NLM_F_MULTI, 1, 77)
    frame = protocol.decode_frame(
      endpoint,
      header,
      Nl::Decoder.new(IO::Buffer.for('reply')),
      FrameMessage,
    )
    expect(frame).to eq('reply')
  end

  it 'rejects an unexpected reply type before decoding its payload' do
    header = Nl::Raw::NlMsgHdr.new(0, FrameMessage::TYPE + 1, 0, 1, 77)
    expect(FrameMessage).not_to receive(:decode)

    expect do
      protocol.decode_frame(endpoint, header, Nl::Decoder.new(IO::Buffer.for('reply')), FrameMessage)
    end.to raise_error(Nl::ProtocolViolation, 'Expected message type 42, got 43')
  end

  it 'selects a notification decoder by wire type' do
    header = Nl::Raw::NlMsgHdr.new(0, FrameMessage::TYPE, 0, 0, 0)
    payload = Nl::Decoder.new(IO::Buffer.for('notification'))

    expect(protocol.decode_notification(endpoint, header, payload, {42 => FrameMessage})).to eq('notification')
  end

  it 'ignores unknown notification types without decoding the payload' do
    header = Nl::Raw::NlMsgHdr.new(0, 43, 0, 0, 0)
    payload = Nl::Decoder.new(IO::Buffer.for('unknown'))

    expect(protocol.decode_notification(endpoint, header, payload, {42 => FrameMessage})).to be_nil
    expect(payload.remaining).to eq(7)
  end
end
