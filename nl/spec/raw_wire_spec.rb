# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Raw::NlMsgHdr do
  let(:fields) { [0xfedcba98, 0x8123, 0xc456, 0x89abcdef, 0xfedcba98] }
  let(:native_format) { 'LSSLL' }
  let(:size) { 16 }

  it 'decodes native-endian fields and leaves trailing bytes unread' do
    encoder = Nl::Encoder.new
    described_class.new(*fields).encode(encoder)
    bytes = encoder.buffer.get_string
    expect(bytes).to eq(fields.pack(native_format))
    decoder = Nl::Decoder.new(IO::Buffer.for(bytes + 'tail'))

    expect(described_class.decode(decoder).to_a).to eq(fields)
    expect(decoder.get_string).to eq('tail')
  end

  it 'rejects every truncated header within a larger backing buffer' do
    bytes = fields.pack(native_format)
    size.times do |length|
      decoder = Nl::Decoder.new(IO::Buffer.for(bytes), 0, length)
      expect { described_class.decode(decoder) }.to raise_error(Nl::Decoder::OutOfBounds)
    end
  end
end
