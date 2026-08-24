# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl.const_get(:SequenceAllocator) do
  subject(:allocator) { described_class.new }

  it 'allocates nonzero 32-bit sequence numbers and wraps to one' do
    expect(allocator.next).to eq(1)

    allocator.instance_variable_set(:@last, 0xFFFFFFFF)

    expect(allocator.next).to eq(1)
  end

  it 'skips sequence numbers rejected by the caller' do
    expect(allocator.next { it == 1 }).to eq(2)
  end

  it 'uses the public Nl error type for sequence-space exhaustion' do
    expect(Nl::ExhaustedSequenceNumber.superclass).to equal(Nl::Error)
  end

end
