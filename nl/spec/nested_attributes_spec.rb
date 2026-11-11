require 'nl'

RSpec.describe Nl::DataTypes::NestedAttributes do
  let(:inner_attribute_set) do
    Class.new(Nl::AttributeSet).tap do |attribute_set|
      attribute = Nl::AttributeSet::Definition.new(
        id: 2, name: :value,
        datatype: Nl::DataTypes::Scalar[Nl::Endian::Host::U32].new,
      )
      attribute_set.const_set(:Value, attribute)
      attribute_set.const_set(:BY_NAME, { value: attribute }.freeze)
      attribute_set.const_set(:BY_TYPE, { 2 => attribute }.freeze)
    end
  end

  let(:outer_attribute_set) do
    nested_datatype = described_class.new(inner_attribute_set)

    Class.new(Nl::AttributeSet).tap do |attribute_set|
      attribute = Nl::AttributeSet::Definition.new(id: 1, name: :nested, datatype: nested_datatype)
      attribute_set.const_set(:Nested, attribute)
      attribute_set.const_set(:BY_NAME, { nested: attribute }.freeze)
      attribute_set.const_set(:BY_TYPE, { 1 => attribute }.freeze)
    end
  end

  it 'encodes an attribute set as a nested attribute payload' do
    inner = inner_attribute_set.build_instance({ value: 0x12345678 })
    outer = outer_attribute_set.build_instance({ nested: inner })
    encoder = Nl::Encoder.new

    outer.encode(encoder)

    nested = Nl::Raw::NLA_F_NESTED
    expect(encoder.buffer.get_string).to eq(
      [12, nested | 1, 8, 2, 0x12345678].pack('S<S<S<S<L<'),
    )
  end

  it 'builds nested attributes from a hash' do
    outer = outer_attribute_set.build_instance({ nested: { value: 0x12345678 } })
    encoder = Nl::Encoder.new

    outer.encode(encoder)

    nested = Nl::Raw::NLA_F_NESTED
    expect(encoder.buffer.get_string).to eq(
      [12, nested | 1, 8, 2, 0x12345678].pack('S<S<S<S<L<'),
    )
  end

  it 'rejects values that are neither hashes nor nested attribute sets' do
    outer = outer_attribute_set.build_instance({ nested: 123 })

    expect { outer.encode(Nl::Encoder.new) }
      .to raise_error(TypeError, /value must be an instance of/)
  end
end
