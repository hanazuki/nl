# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Decoder do
  {
    get_U8: ['C', 0xff], get_S8: ['c', -128],
    get_u16: ['S<', 0xfedc], get_U16: ['S>', 0xfedc],
    get_s16: ['s<', -12345], get_S16: ['s>', -12345],
    get_u32: ['L<', 0xfedcba98], get_U32: ['L>', 0xfedcba98],
    get_s32: ['l<', -123456789], get_S32: ['l>', -123456789],
    get_u64: ['Q<', 0xfedcba9876543210], get_U64: ['Q>', 0xfedcba9876543210],
    get_s64: ['q<', -123456789012345], get_S64: ['q>', -123456789012345],
    get_f32: ['e', 1.25], get_F32: ['g', 1.25],
    get_f64: ['E', -1.25], get_F64: ['G', -1.25],
  }.each do |reader, (format, value)|
    describe "##{reader}" do
      let(:bytes) { [value].pack(format) }

      it 'reads the wire value from the current position and advances by its width' do
        decoder = described_class.new(IO::Buffer.for("!#{bytes}?".b), 1)

        expect(decoder.public_send(reader)).to eq(value)
        expect(decoder.get_string).to eq('?')
      end

      it 'respects a payload limit even when the backing buffer has enough bytes' do
        decoder = described_class.new(IO::Buffer.for(bytes))

        decoder.limit(bytes.bytesize - 1) do
          expect { decoder.public_send(reader) }.to raise_error(Nl::Decoder::OutOfBounds)
          decoder.skip
        end
        expect(decoder.remaining).to eq(1)
      end

      it 'rejects truncated input without advancing' do
        decoder = described_class.new(IO::Buffer.for(bytes.byteslice(0...-1)))

        expect { decoder.public_send(reader) }.to raise_error(Nl::Decoder::OutOfBounds)
        expect(decoder.remaining).to eq(bytes.bytesize - 1)
      end
    end
  end

  it 'rejects a negative string length without advancing' do
    decoder = described_class.new(IO::Buffer.for('data'))

    expect { decoder.get_string(-1) }.to raise_error(Nl::Decoder::OutOfBounds)
    expect(decoder.get_string).to eq('data')
  end

  describe '#slice' do
    it 'returns a bounded decoder sharing the buffer and advances the parent' do
      source = IO::Buffer.for('data')
      decoder = described_class.new(source)
      decoder.skip(1)

      value = decoder.slice(2)

      expect(value.get_string).to eq('at')
      expect(decoder.get_string).to eq('a')
    end

    it 'rejects invalid lengths without advancing' do
      decoder = described_class.new(IO::Buffer.for('data'))

      expect { decoder.slice(-1) }.to raise_error(Nl::Decoder::OutOfBounds)
      expect { decoder.slice(5) }.to raise_error(Nl::Decoder::OutOfBounds)
      expect(decoder.get_string).to eq('data')
    end
  end

  describe '#limit' do
    it 'rejects a limit outside the current bounds without advancing' do
      decoder = described_class.new(IO::Buffer.for('data'))

      expect { decoder.limit(-1) {} }.to raise_error(Nl::Decoder::OutOfBounds)
      expect { decoder.limit(5) {} }.to raise_error(Nl::Decoder::OutOfBounds)
      expect(decoder.get_string).to eq('data')
    end
  end

  describe '#lookahead' do
    it 'restores the position after reading' do
      decoder = described_class.new(IO::Buffer.for('data'))

      expect(decoder.lookahead { it.get_string(2) }).to eq('da')
      expect(decoder.get_string).to eq('data')
    end

    it 'restores the position after an exception' do
      decoder = described_class.new(IO::Buffer.for('data'))

      expect do
        decoder.lookahead do
          it.get_string(2)
          raise 'failure'
        end
      end.to raise_error('failure')
      expect(decoder.get_string).to eq('data')
    end
  end
  {
    U8: ['C', 255], S8: ['c', -128],
    U16: ['S', 0xfedc], S16: ['s', -12345],
    U32: ['L', 0xfedcba98], S32: ['l', -123456789],
    U64: ['Q', 0xfedcba9876543210], S64: ['q', -123456789012345],
    F32: ['f', 1.25], F64: ['d', -1.25],
    UINT: ['I!', 12345], SINT: ['i!', -12345],
    ULONG: ['L!', 12345], SLONG: ['l!', -12345],
    ULLONG: ['Q!', 12345], SLLONG: ['q!', -12345],
  }.each do |name, (format, value)|
    it "reads native #{name} through a direct alias" do
      bytes = [value].pack(format)
      decoder = described_class.new(IO::Buffer.for(bytes))
      reader = decoder.method(:"get_host_#{name.downcase}")

      expect(reader.original_name).to eq(:"get_#{Nl::Endian::Host.const_get(name)}")
      expect(reader.call).to eq(value)
      expect(decoder.remaining).to eq(0)
    end
  end
end
