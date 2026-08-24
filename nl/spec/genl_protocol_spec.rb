# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Protocols::Genl do
  GenlRequest = Class.new do
    const_set(:TYPE, 7)

    def self.from_params(_params) = new
    def encode(_encoder) = nil
  end

  it 'keeps the family ID in the frame header and the command ID in the message' do
    protocol = described_class.new('fake', family_id: 42)
    frame = protocol.build_request(:do, GenlRequest, {})
    frame.header.seq = 1
    frame.header.pid = 77
    encoder = Nl::Encoder.new

    protocol.encode_message(encoder, frame)

    length, type, = encoder.buffer.get_string.unpack('L<S<S<')
    command, = encoder.buffer.get_string(16, 4).unpack('C')
    expect([length, type, command]).to eq([20, 42, 7])
  end
end
