require 'nl'

RSpec.describe Nl::DataTypes::NestTypeValue do
  let(:leaf_type) do
    Class.new do
      def self.decode(decoder)
        decoder.get_value(Nl::Endian::Host::U32)
      end
    end
  end

  it 'decodes type values as keys at every nesting level' do
    nested = Nl::Raw::NLA_F_NESTED
    data = [12, nested | 7, 8, nested | 9, 0x12345678].pack('S<S<S<S<L<')
    decoder = Nl::Decoder.new(IO::Buffer.for(data))

    value = described_class.new(leaf_type, 2).decode(decoder)

    expect(value).to eq(7 => { 9 => 0x12345678 })
    expect(decoder).not_to be_available
  end

  it 'coerces hashes at the innermost level to attribute sets' do
    attribute_set = Class.new(Nl::AttributeSet).tap do |set|
      attribute = Class.new(set::Attribute)
      attribute.const_set(:TYPE, 1)
      attribute.const_set(:NAME, :type)
      attribute.const_set(:DATATYPE, Nl::DataTypes::Scalar.new(Nl::Endian::Host::U32, check: nil))
      set.const_set(:Type, attribute)
      set.const_set(:BY_NAME, { type: attribute }.freeze)
      set.const_set(:BY_TYPE, { 1 => attribute }.freeze)
      set.define_singleton_method(:by_name) { const_get(:BY_NAME, false).fetch(it) }
      set.define_singleton_method(:by_type) { const_get(:BY_TYPE, false).fetch(it) }
    end

    value = described_class.new(attribute_set, 2).coerce(7 => { 9 => { type: 42 } })

    expect(value.dig(7, 9)).to be_a(attribute_set)
    expect(value.dig(7, 9)[:type].value).to eq 42
  end
end
