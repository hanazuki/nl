require 'nl'

RSpec.describe Nl::Protocols::Raw::DataTypes::NestedAttributes do
  let(:inner_attribute_set) do
    Class.new(Nl::Protocols::Raw::AttributeSet).tap do |attribute_set|
      attribute = Class.new(attribute_set::Attribute)
      attribute.const_set(:TYPE, 2)
      attribute.const_set(:NAME, :value)
      attribute.const_set(
        :DATATYPE,
        Nl::Protocols::Raw::DataTypes::Scalar.new(Nl::Endian::Host::U32, check: nil),
      )
      attribute_set.const_set(:Value, attribute)
      attribute_set.const_set(:BY_NAME, { value: attribute }.freeze)
      attribute_set.const_set(:BY_TYPE, { 2 => attribute }.freeze)
    end
  end

  let(:outer_attribute_set) do
    nested_datatype = described_class.new(inner_attribute_set)

    Class.new(Nl::Protocols::Raw::AttributeSet).tap do |attribute_set|
      attribute = Class.new(attribute_set::Attribute)
      attribute.const_set(:TYPE, 1)
      attribute.const_set(:NAME, :nested)
      attribute.const_set(:DATATYPE, nested_datatype)
      attribute_set.const_set(:Nested, attribute)
      attribute_set.const_set(:BY_NAME, { nested: attribute }.freeze)
      attribute_set.const_set(:BY_TYPE, { 1 => attribute }.freeze)
    end
  end

  it 'encodes an attribute set as a nested attribute payload' do
    inner = inner_attribute_set.build_attributes(value: 0x12345678)
    outer = outer_attribute_set.build_attributes(nested: inner)
    encoder = Nl::Encoder.new

    outer.encode(encoder)

    nested = Nl::Core::NLA_F_NESTED
    expect(encoder.buffer.get_string).to eq(
      [12, nested | 1, 8, 2, 0x12345678].pack('S<S<S<S<L<'),
    )
  end

  it 'rejects values that are not instances of the nested attribute set' do
    outer = outer_attribute_set.build_attributes(nested: { value: 0x12345678 })

    expect { outer.encode(Nl::Encoder.new) }
      .to raise_error(TypeError, /value must be an instance of/)
  end
end
