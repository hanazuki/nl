require 'nl'

RSpec.describe Nl::Selector::State do
  describe '.for' do
    it 'reuses the empty state' do
      first = described_class.for(0, [])
      second = described_class.for(0, [])

      expect(first).to equal(second)
    end

    it 'allocates state for local selectors' do
      first = described_class.for(1, [])
      second = described_class.for(1, [])

      expect(first).not_to equal(second)
    end

    it 'allocates state for external selectors' do
      selectors = [1]
      first = described_class.for(0, selectors)
      second = described_class.for(0, selectors)

      expect(first).not_to equal(second)
      expect(first.fetch_external(0)).to eq(1)
    end
  end
end
