# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Encoder do
  describe '#align_to_4' do
    it 'pads to the next four-byte boundary, growing the buffer when needed' do
      {'' => '', 'a' => "a\0\0\0", 'abcd' => 'abcd', 'abcde' => "abcde\0\0\0"}.each do |value, padded|
        encoder = described_class.new(1)
        encoder.put_string(value)

        encoder.align_to_4
        encoder.put_string('?')

        expect(encoder.buffer.get_string).to eq(padded + '?')
      end
    end
  end
end
