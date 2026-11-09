# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::DataTypes::Checked do
  it 'checks supplied values unchanged and ignores the check return value' do
    seen = []
    datatype = described_class.new(
      Nl::DataTypes::Scalar[:U8].new,
      check: -> { seen << it; false },
    )
    encoder = Nl::Encoder.new

    expect { datatype.encode(encoder, nil) }.to raise_error(TypeError)
    expect { datatype.encode(encoder, false) }.to raise_error(TypeError)
    datatype.encode(encoder, 3)
    expect(encoder.buffer.get_string).to eq("\x03".b)
    expect(datatype.decode(Nl::Decoder.new(IO::Buffer.for("\x07".b)))).to eq(7)
    expect(seen).to eq([nil, false, 3, 7])
  end

  it 'checks strings as decoded values rather than their terminated wire representation' do
    datatype = described_class.new(
      Nl::DataTypes::String.new,
      check: -> { raise ArgumentError, 'too long' if it.bytesize > 2 },
    )

    expect(datatype.decode(Nl::Decoder.new(IO::Buffer.for("ab\0".b)))).to eq('ab')
    expect { datatype.decode(Nl::Decoder.new(IO::Buffer.for("abc\0".b))) }
      .to raise_error(ArgumentError, 'too long')
    expect { datatype.encode(Nl::Encoder.new, 'abc') }
      .to raise_error(ArgumentError, 'too long')
  end

  it 'checks only the configured binary length and leaves following bytes unread' do
    datatype = described_class.new(
      Nl::DataTypes::Binary.new(length: 2),
      check: -> { raise ArgumentError unless it == 'ab' },
    )
    decoder = Nl::Decoder.new(IO::Buffer.for('abcd'))

    expect(datatype.decode(decoder)).to eq('ab')
    expect(decoder.get_string).to eq('cd')
  end

  it 'preserves coercion and flags for a wrapped datatype' do
    nested = Nl::DataTypes::NestedAttributes.new(Class.new)
    datatype = described_class.new(nested, check: -> {})
    value = Object.new

    expect(datatype.coerce(value)).to equal(value)
    expect(datatype.nlattr_type_flags(value)).to eq(Nl::Raw::NLA_F_NESTED)
  end
end

RSpec.describe Nl::DataTypes::CheckedPayload do
  let(:record) do
    Class.new(::Struct.new(:value)) do
      def self.decode(decoder)
        new(decoder.get_U8)
      end

      def self.from_params(params, context: nil)
        new(params.fetch(:value))
      end

      def encode(encoder)
        encoder.put_value(:U8, value)
      end
    end
  end

  it 'validates structured bytes while preserving coercion and decoded objects' do
    datatype = described_class.new(
      Nl::DataTypes::Struct.new(record),
      check: -> { raise ArgumentError, 'wrong length' unless it.bytesize == 1 },
    )
    value = datatype.coerce({value: 7})
    encoder = Nl::Encoder.new

    datatype.encode(encoder, value)

    expect(encoder.buffer.get_string).to eq("\x07".b)
    expect(datatype.decode(Nl::Decoder.new(encoder.buffer))).to eq(value)
    expect { datatype.decode(Nl::Decoder.new(IO::Buffer.for("\x07\0".b))) }
      .to raise_error(ArgumentError, 'wrong length')
  end

  it 'retains the structured datatype policy for extension bytes' do
    check = -> { raise ArgumentError unless it.bytesize == 2 }
    bytes = IO::Buffer.for("\x07\0".b)
    strict = described_class.new(Nl::DataTypes::Struct.new(record), check:)
    extensible = described_class.new(
      Nl::DataTypes::Struct.new(record, consume_remaining: true), check:,
    )

    expect { strict.decode(Nl::Decoder.new(bytes)) }
      .to raise_error(RuntimeError, /Not all bytes/)
    expect(extensible.decode(Nl::Decoder.new(bytes))).to eq(record.new(7))
  end
end
