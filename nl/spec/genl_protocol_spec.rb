# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Genl::Protocol do
  GenlRequest = Class.new do
    const_set(:TYPE, 7)

    def self.from_params(_params) = new
    def encode(_encoder) = nil
  end

  GenlNotificationAttributes = Class.new(Nl::AttributeSet)
  GenlNotificationAttributes.const_set(:Attribute, Class.new(Nl::AttributeSet::Attribute))
  GenlNotificationAttributes.const_set(:BY_TYPE, {}.freeze)
  GenlNotificationAttributes.const_set(:BY_NAME, {}.freeze)

  GenlNotification = Class.new(Nl::Genl::Message)
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
    payload = IO::Buffer.for([9, 1, 0].pack('CCS!'))
    classes = {9 => GenlNotification}

    expect(protocol.notification_frame?(endpoint, header, payload)).to be(true)
    message_class = protocol.notification_class(endpoint, header, payload, classes)
    expect(message_class).to equal(GenlNotification)
    expect(protocol.decode_notification(endpoint, header, payload, message_class)).to be_a(GenlNotification)
  end

  it 'resolves multicast groups from family information' do
    info = Nl::Genl::FamilyInfo.new(id: 42, multicast_groups: {'events' => 99})
    endpoint = Nl::Genl::Endpoint.new(family, info)
    expect(endpoint.multicast_group_id('events', nil)).to eq(99)
  end
end
