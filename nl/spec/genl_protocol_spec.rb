# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Genl::Protocol do
  GenlRequest = Class.new do
    const_set(:TYPE, 7)

    def self.from_params(_params) = new
    def encode(_encoder) = nil
  end

  GenlNotificationAttributes = Class.new(Nl::AttributeSet)
  GenlNotificationAttributes.const_set(:BY_TYPE, {}.freeze)
  GenlNotificationAttributes.const_set(:BY_NAME, {}.freeze)

  GenlNotification = Class.new(Nl::Message) do
    def self.decode(decoder)
      new(nil, GenlNotificationAttributes.decode(decoder))
    end
  end
  GenlNotification.const_set(:TYPE, 9)
  GenlNotification.const_set(:FIXED_HEADER, nil)
  GenlNotification.const_set(:ATTRIBUTE_SET, GenlNotificationAttributes)

  let(:family) do
    Class.new(Nl::Genl::Family) do
      const_set(:NAME, 'fake')
      const_set(:VERSION, 2)
    end
  end
  let(:info) { Nl::Genl::FamilyInfo.new(id: 42, multicast_groups: {}) }
  let(:endpoint) { Nl::Genl::Endpoint.new(family, info) }
  subject(:protocol) { described_class.new }

  def reply_payload(command = 9)
    Nl::Decoder.new(IO::Buffer.for([command, 1, 0].pack('CCS!')))
  end

  it 'consumes the Generic header before decoding a reply payload' do
    header = Nl::Raw::NlMsgHdr.new(20, 42, 0, 1, 77)
    payload = reply_payload
    expect(Nl::Genl::GenlMsgHdr).to receive(:decode).once.and_call_original

    frame = protocol.decode_frame(endpoint, header, payload, GenlNotification)

    expect(frame.header).to equal(header)
    expect(frame.message).to be_a(GenlNotification)
    expect(payload.remaining).to eq(0)
  end

  it 'rejects an unexpected reply command before decoding the family payload' do
    header = Nl::Raw::NlMsgHdr.new(20, 42, 0, 1, 77)
    expect(GenlNotification).not_to receive(:decode)

    expect do
      protocol.decode_frame(endpoint, header, reply_payload(8), GenlNotification)
    end.to raise_error(Nl::ProtocolViolation, 'Expected command 9, got 8')
  end

  it 'rejects replies from another family before reading the Generic header' do
    header = Nl::Raw::NlMsgHdr.new(20, 43, 0, 1, 77)
    expect(Nl::Genl::GenlMsgHdr).not_to receive(:decode)

    expect do
      protocol.decode_frame(endpoint, header, reply_payload, GenlNotification)
    end.to raise_error(Nl::ProtocolViolation, 'Expected family ID 42, got 43')
  end

  it 'rejects a truncated Generic header' do
    header = Nl::Raw::NlMsgHdr.new(19, 42, 0, 1, 77)
    payload = Nl::Decoder.new(IO::Buffer.for([9, 1, 0].pack('CCC')))
    expect(GenlNotification).not_to receive(:decode)

    expect do
      protocol.decode_frame(endpoint, header, payload, GenlNotification)
    end.to raise_error(Nl::Decoder::OutOfBounds)
  end

  it 'decodes control frames without expecting a Generic header' do
    header = Nl::Raw::NlMsgHdr.new(16, Nl::Raw::NLMSG_DONE, 0, 1, 77)
    expect(Nl::Genl::GenlMsgHdr).not_to receive(:decode)

    frame = protocol.decode_frame(endpoint, header, Nl::Decoder.new(IO::Buffer.for('')), nil)

    expect(frame).to eq(Nl::Raw::DoneFrame.new(header, nil))
  end

  it 'keeps the family ID in the frame header and the command ID in the message' do
    request = protocol.build_request(endpoint, :do, GenlRequest, {})
    encoder = Nl::Encoder.new
    protocol.encode_message(encoder, endpoint, request, seq: 1, pid: 77)

    length, type, = encoder.buffer.get_string.unpack('L<S<S<')
    command, version, = encoder.buffer.get_string(16, 4).unpack('CC')
    expect([length, type, command, version]).to eq([20, 42, 7, 2])
  end

  it 'selects and decodes notifications by family ID and command ID' do
    header = Nl::Raw::NlMsgHdr.new(20, 42, 0, 0, 0)
    payload = Nl::Decoder.new(IO::Buffer.for([9, 1, 0].pack('CCS!')))
    classes = {9 => GenlNotification}

    expect(protocol.notification_frame?(endpoint, header, payload)).to be(true)
    expect(Nl::Genl::GenlMsgHdr).to receive(:decode).once.and_call_original
    expect(protocol.decode_notification(endpoint, header, payload, classes)).to be_a(GenlNotification)
    expect(payload.remaining).to eq(0)
  end

  it 'ignores an unknown notification command after consuming its Generic header' do
    header = Nl::Raw::NlMsgHdr.new(20, 42, 0, 0, 0)
    payload = reply_payload(8)

    expect(protocol.decode_notification(endpoint, header, payload, {9 => GenlNotification})).to be_nil
    expect(payload.remaining).to eq(0)
  end

  it 'ignores notifications from another family without consuming their payload' do
    header = Nl::Raw::NlMsgHdr.new(20, 43, 0, 0, 0)
    payload = reply_payload

    expect(protocol.decode_notification(endpoint, header, payload, {9 => GenlNotification})).to be_nil
    expect(payload.remaining).to eq(4)
  end

  it 'resolves multicast groups from family information' do
    info = Nl::Genl::FamilyInfo.new(id: 42, multicast_groups: {'events' => 99})
    endpoint = Nl::Genl::Endpoint.new(family, info)
    expect(endpoint.multicast_group_id('events', nil)).to eq(99)
  end
end
