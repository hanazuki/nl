# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Decoder do
  it 'rejects a negative string length without advancing' do
    decoder = described_class.new(IO::Buffer.for('data'))

    expect { decoder.get_string(-1) }.to raise_error(Nl::Decoder::OutOfBounds)
    expect(decoder.get_string).to eq('data')
  end

  describe '#get_buffer' do
    it 'returns a buffer view and advances the decoder' do
      source = IO::Buffer.for('data')
      decoder = described_class.new(source)

      value = decoder.get_buffer(2)

      expect(value).to be_a(IO::Buffer)
      expect(value.get_string).to eq('da')
      expect(decoder.get_string).to eq('ta')
    end

    it 'rejects invalid lengths' do
      decoder = described_class.new(IO::Buffer.for('data'))

      expect { decoder.get_buffer(-1) }.to raise_error(Nl::Decoder::OutOfBounds)
      expect { decoder.get_buffer(5) }.to raise_error(Nl::Decoder::OutOfBounds)
    end
  end
end
