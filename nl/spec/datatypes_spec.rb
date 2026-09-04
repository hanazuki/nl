# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::DataTypes::VariableInteger do
  def encode(datatype, value)
    encoder = Nl::Encoder.new
    datatype.encode(encoder, value)
    encoder.buffer
  end

  def decode(datatype, type, value)
    encoder = Nl::Encoder.new
    encoder.put_value(type, value)
    datatype.decode(Nl::Decoder.new(encoder.buffer))
  end

  describe 'unsigned integers' do
    subject(:datatype) do
      described_class.new(Nl::Endian::Host, signed: false, check: nil)
    end

    it 'uses the smallest supported width' do
      aggregate_failures do
        expect(encode(datatype, 0).size).to eq(4)
        expect(encode(datatype, 2**32 - 1).size).to eq(4)
        expect(encode(datatype, 2**32).size).to eq(8)
        expect(encode(datatype, 2**64 - 1).size).to eq(8)
      end
    end

    it 'decodes both supported widths' do
      aggregate_failures do
        expect(decode(datatype, Nl::Endian::Host::U32, 123)).to eq(123)
        expect(decode(datatype, Nl::Endian::Host::U64, 123)).to eq(123)
        expect(decode(datatype, Nl::Endian::Host::U64, 2**32)).to eq(2**32)
      end
    end

    it 'rejects values outside the unsigned 64-bit range' do
      expect { encode(datatype, -1) }.to raise_error(RangeError)
      expect { encode(datatype, 2**64) }.to raise_error(RangeError)
    end
  end

  describe 'signed integers' do
    subject(:datatype) do
      described_class.new(Nl::Endian::Host, signed: true, check: nil)
    end

    it 'uses the smallest supported width at signed boundaries' do
      aggregate_failures do
        expect(encode(datatype, -(2**31) - 1).size).to eq(8)
        expect(encode(datatype, -(2**31)).size).to eq(4)
        expect(encode(datatype, 2**31 - 1).size).to eq(4)
        expect(encode(datatype, 2**31).size).to eq(8)
      end
    end

    it 'decodes both supported widths' do
      aggregate_failures do
        expect(decode(datatype, Nl::Endian::Host::S32, -123)).to eq(-123)
        expect(decode(datatype, Nl::Endian::Host::S64, -123)).to eq(-123)
        expect(decode(datatype, Nl::Endian::Host::S64, -(2**31) - 1)).to eq(-(2**31) - 1)
      end
    end

    it 'rejects values outside the signed 64-bit range' do
      expect { encode(datatype, -(2**63) - 1) }.to raise_error(RangeError)
      expect { encode(datatype, 2**63) }.to raise_error(RangeError)
    end
  end

  it 'honors the configured byte order' do
    datatype = described_class.new(Nl::Endian::Big, signed: false, check: nil)

    expect(encode(datatype, 0x01020304).get_string).to eq("\x01\x02\x03\x04".b)
    expect(encode(datatype, 0x0102030405060708).get_string).to eq("\x01\x02\x03\x04\x05\x06\x07\x08".b)
  end

  it 'rejects payloads whose width is neither 32 nor 64 bits' do
    datatype = described_class.new(Nl::Endian::Host, signed: false, check: nil)

    [0, 3, 5, 12].each do |length|
      decoder = Nl::Decoder.new(IO::Buffer.new(length))
      expect { datatype.decode(decoder) }.to raise_error(
        Nl::Decoder::Error,
        "variable integer payload must be 4 or 8 bytes, got #{length}",
      )
    end
  end
end
