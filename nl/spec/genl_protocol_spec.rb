# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Protocols::Genl do
  GenlRequest = Class.new do
    const_set(:TYPE, 7)

    def self.from_params(_params) = new
    def encode(_encoder) = nil
  end


  GenlNotificationAttributes = Class.new(Nl::Protocols::Genl::AttributeSet)
  GenlNotificationAttributes.const_set(:Attribute, Class.new(Nl::Protocols::Genl::AttributeSet::Attribute))
  GenlNotificationAttributes.const_set(:BY_TYPE, {}.freeze)
  GenlNotificationAttributes.const_set(:BY_NAME, {}.freeze)

  GenlNotification = Class.new(Nl::Protocols::Genl::Message)
  GenlNotification.const_set(:TYPE, 9)
  GenlNotification.const_set(:FIXED_HEADER, nil)
  GenlNotification.const_set(:ATTRIBUTE_SET, GenlNotificationAttributes)

  it 'keeps the family ID in the frame header and the command ID in the message' do
    protocol = described_class.new('fake', family_id: 42)
    request = protocol.build_request(:do, GenlRequest, {})
    encoder = Nl::Encoder.new

    protocol.encode_message(encoder, request, seq: 1, pid: 77)

    length, type, = encoder.buffer.get_string.unpack('L<S<S<')
    command, = encoder.buffer.get_string(16, 4).unpack('C')
    expect([length, type, command]).to eq([20, 42, 7])
  end

  it 'does not special-case the nlctrl family ID' do
    protocol = described_class.new('nlctrl')

    expect { protocol.family_id }.to raise_error(NotImplementedError)
  end

  it 'selects and decodes notifications by family ID and command ID' do
    protocol = described_class.new('fake', family_id: 42)
    header = Nl::Core::NlMsgHdr.new(20, 42, 0, 0, 0)
    payload = IO::Buffer.for([9, 1, 0].pack('CCS!'))
    classes = {9 => GenlNotification}

    expect(protocol).to be_notification_frame(header, payload)
    message_class = protocol.notification_class(header, payload, classes)
    expect(message_class).to equal(GenlNotification)
    expect(protocol.decode_notification(header, payload, message_class)).to be_a(GenlNotification)
  end

  it 'resolves multicast groups by name rather than their specification value' do
    protocol = described_class.new('fake', family_id: 42, multicast_groups: {'events' => 99})

    expect(protocol.multicast_group_id('events', nil)).to eq(99)
  end
end
