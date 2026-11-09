# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::DataTypes::Scalar do
  {
    U8: ['C', 255], S8: ['c', -128],
    u16: ['S<', 0xfedc], U16: ['S>', 0xfedc],
    s16: ['s<', -12345], S16: ['s>', -12345],
    u32: ['L<', 0xfedcba98], U32: ['L>', 0xfedcba98],
    s32: ['l<', -123456789], S32: ['l>', -123456789],
    u64: ['Q<', 0xfedcba9876543210], U64: ['Q>', 0xfedcba9876543210],
    s64: ['q<', -123456789012345], S64: ['q>', -123456789012345],
    f32: ['e', 1.25], F32: ['g', 1.25],
    f64: ['E', -1.25], F64: ['G', -1.25],
  }.each do |type, (format, value)|
    it "encodes and decodes #{type} with its wire representation" do
      datatype = described_class[type].new
      bytes = [value].pack(format)
      encoder = Nl::Encoder.new

      datatype.encode(encoder, value)

      expect(encoder.buffer.get_string).to eq(bytes)
      expect(datatype.decode(Nl::Decoder.new(IO::Buffer.for(bytes)))).to eq(value)
      expect(datatype.coerce(value)).to eq(value)
      expect(datatype.nlattr_type_flags(value)).to eq(0)
    end
  end

  it 'applies checks during encoding and decoding' do
    datatype = Nl::DataTypes::Checked.new(
      described_class[:U8].new,
      check: ->(value) { raise RangeError if value > 10 },
    )

    expect { datatype.encode(Nl::Encoder.new, 11) }.to raise_error(RangeError)
    expect { datatype.decode(Nl::Decoder.new(IO::Buffer.for("\x0b"))) }.to raise_error(RangeError)
  end

  it 'rejects nil and false instead of encoding them as zero' do
    datatype = described_class[:U16].new

    expect { datatype.encode(Nl::Encoder.new, nil) }.to raise_error(TypeError)
    expect { datatype.encode(Nl::Encoder.new, false) }.to raise_error(TypeError)
  end
end

RSpec.describe Nl::DataTypes::Bitfield32 do
  subject(:datatype) { described_class.new }

  it 'encodes the value followed by the selector' do
    encoder = Nl::Encoder.new

    datatype.encode(encoder, Nl::Bitfield32.new(0x14, 0x34))

    expect(encoder.buffer.get_values([Nl::Endian::Host::U32] * 2, 0)).to eq([0x14, 0x34])
  end

  it 'decodes to a Bitfield32' do
    encoder = Nl::Encoder.new
    encoder.put_values([Nl::Endian::Host::U32] * 2, [0x14, 0x34])

    value = datatype.decode(Nl::Decoder.new(encoder.buffer))

    expect(value).to be_a(Nl::Bitfield32)
    expect(value.value).to eq(0x14)
    expect(value.selector).to eq(0x34)
  end

  it 'rejects values of other types' do
    expect { datatype.encode(Nl::Encoder.new, [0x14, 0x34]) }.to raise_error(
      TypeError,
      'bitfield32 value must be an Nl::Bitfield32',
    )
  end
end

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
      described_class.new(Nl::Endian::Host, signed: false)
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
      expect { encode(datatype, nil) }.to raise_error(RangeError)
      expect { encode(datatype, false) }.to raise_error(RangeError)
    end
  end

  describe 'signed integers' do
    subject(:datatype) do
      described_class.new(Nl::Endian::Host, signed: true)
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
    datatype = described_class.new(Nl::Endian::Big, signed: false)

    expect(encode(datatype, 0x01020304).get_string).to eq("\x01\x02\x03\x04".b)
    expect(encode(datatype, 0x0102030405060708).get_string).to eq("\x01\x02\x03\x04\x05\x06\x07\x08".b)
  end

  it 'rejects payloads whose width is neither 32 nor 64 bits' do
    datatype = described_class.new(Nl::Endian::Host, signed: false)

    [0, 3, 5, 12].each do |length|
      decoder = Nl::Decoder.new(IO::Buffer.new(length))
      expect { datatype.decode(decoder) }.to raise_error(
        Nl::Decoder::Error,
        "variable integer payload must be 4 or 8 bytes, got #{length}",
      )
    end
  end
end

RSpec.describe Nl::DataTypes::Binary do
  subject(:datatype) { described_class.new(length: 3) }

  it 'decodes exactly its configured length' do
    decoder = Nl::Decoder.new(IO::Buffer.for("abcdef".b))

    expect(datatype.decode(decoder)).to eq('abc')
    expect(decoder.get_string).to eq('def')
  end

  it 'rejects truncated input' do
    decoder = Nl::Decoder.new(IO::Buffer.for("ab".b))

    expect { datatype.decode(decoder) }.to raise_error(Nl::Decoder::OutOfBounds)
  end

  it 'rejects values whose encoded length does not match' do
    expect { datatype.encode(Nl::Encoder.new, 'ab') }.to raise_error(
      ArgumentError,
      'binary value must be exactly 3 bytes, got 2',
    )
  end
end

RSpec.describe Nl::DataTypes::IndexedArray do
  it 'rejects an attribute shorter than its header' do
    encoder = Nl::Encoder.new
    encoder.put_value(Nl::Endian::Host::U16, Nl::Raw::NLA_HDRLEN - 1)
    encoder.put_value(Nl::Endian::Host::U16, 1)
    element = Nl::DataTypes::Scalar[Nl::Endian::Host::U32].new

    expect { described_class.new(element).decode(Nl::Decoder.new(encoder.buffer)) }
      .to raise_error(
        Nl::Decoder::Error,
        'attribute length must be at least 4 bytes, got 3',
      )
  end
end
