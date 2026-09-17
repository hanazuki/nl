# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Decoder do
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
end
