# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Bitfield32 do
  it 'distinguishes set, cleared, and unselected bits' do
    bitfield = described_class.new(0, 0)

    bitfield[1] = 1
    bitfield[2] = 0

    expect(bitfield[1]).to eq(1)
    expect(bitfield[2]).to eq(0)
    expect(bitfield[3]).to be_nil
    expect(bitfield.value).to eq(0b0010)
    expect(bitfield.selector).to eq(0b0110)
  end

  it 'unselects a bit when nil is assigned' do
    bitfield = described_class.new(0b0010, 0b0010)

    bitfield[1] = nil

    expect(bitfield[1]).to be_nil
    expect(bitfield.value).to eq(0)
    expect(bitfield.selector).to eq(0)
  end

  it 'rejects values outside the selector' do
    expect { described_class.new(0b0010, 0) }.to raise_error(
      ArgumentError,
      'value contains bits which are not selected',
    )
  end

  it 'requires both value and selector' do
    expect { described_class.new }.to raise_error(ArgumentError)
    expect { described_class.new(0) }.to raise_error(ArgumentError)
  end

  it 'rejects invalid bit indexes and states' do
    bitfield = described_class.new(0, 0)

    expect { bitfield[-1] }.to raise_error(RangeError)
    expect { bitfield[32] }.to raise_error(RangeError)
    expect { bitfield['1'] }.to raise_error(TypeError)
    expect { bitfield[1] = true }.to raise_error(TypeError)
  end
end
