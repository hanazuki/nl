# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::DataTypes::PackedArray do
  def encode(datatype, values)
    encoder = Nl::Encoder.new
    datatype.encode(encoder, values)
    encoder.buffer.get_string
  end

  def decode(datatype, payload)
    datatype.decode(Nl::Decoder.new(IO::Buffer.for(payload)))
  end

  subject(:datatype) do
    described_class.new(
      Nl::DataTypes::Scalar.new(Nl::Endian::Big::U32, check: nil),
    )
  end

  it 'encodes elements consecutively without headers or padding' do
    expect(encode(datatype, [0x01020304, 0x05060708])).to eq(
      "\x01\x02\x03\x04\x05\x06\x07\x08".b,
    )
  end

  it 'decodes consecutive elements into an array' do
    expect(decode(datatype, "\x01\x02\x03\x04\x05\x06\x07\x08".b)).to eq(
      [0x01020304, 0x05060708],
    )
  end

  it 'encodes and decodes an empty array' do
    expect(encode(datatype, [])).to eq(''.b)
    expect(decode(datatype, ''.b)).to eq([])
  end

  it 'rejects a payload containing a partial element' do
    expect { decode(datatype, "\x01\x02\x03\x04\x05".b) }
      .to raise_error(Nl::Decoder::OutOfBounds)
  end

  it 'applies binary length checks to the packed payload' do
    checked = described_class.new(
      Nl::DataTypes::Scalar.new(Nl::Endian::Big::U32, check: nil),
      check: -> { raise ArgumentError, 'wrong length' unless it.bytesize == 8 },
    )

    expect { encode(checked, [1]) }.to raise_error(ArgumentError, 'wrong length')
    expect { decode(checked, "\0".b * 4) }.to raise_error(ArgumentError, 'wrong length')
  end
end
