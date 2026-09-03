require 'nl'

RSpec.describe Nl::AttributeSet do
  let(:attribute_set) do
    Class.new(described_class).tap do |set|
      singular = Class.new(set::Attribute)
      singular.const_set(:TYPE, 1)
      singular.const_set(:NAME, :singular)
      singular.const_set(:DATATYPE, Nl::DataTypes::Scalar.new(Nl::Endian::Host::U32, check: nil))

      repeated = Class.new(set::Attribute)
      repeated.const_set(:TYPE, 2)
      repeated.const_set(:NAME, :repeated)
      repeated.const_set(:MULTI, true)
      repeated.const_set(:DATATYPE, Nl::DataTypes::Scalar.new(Nl::Endian::Host::U32, check: nil))

      set.const_set(:Singular, singular)
      set.const_set(:Repeated, repeated)
      set.const_set(:BY_NAME, {singular:, repeated:}.freeze)
      set.const_set(:BY_TYPE, {1 => singular, 2 => repeated}.freeze)
      set.define_singleton_method(:by_name) { const_get(:BY_NAME, false).fetch(it) }
      set.define_singleton_method(:by_type) { const_get(:BY_TYPE, false).fetch(it) }
    end
  end

  it 'builds, encodes, and decodes repeated attributes in order' do
    attributes = attribute_set.build_attributes(singular: 10, repeated: [20, 30])
    encoder = Nl::Encoder.new

    attributes.encode(encoder)
    decoded = attribute_set.decode(Nl::Decoder.new(encoder.buffer))

    expect(decoded[:singular].value).to eq 10
    expect(decoded[2].map(&:value)).to eq [20, 30]
  end

  it 'returns an empty array when a repeated attribute is absent' do
    attributes = attribute_set.build_attributes(singular: 10)

    expect(attributes[:repeated]).to eq []
  end

  it 'requires an array when building a repeated attribute' do
    expect { attribute_set.build_attributes(repeated: 20) }
      .to raise_error(TypeError, 'value for multi-attribute repeated must be an Array')
  end

  it 'retains singular lookup behavior' do
    attributes = attribute_set.new([
      attribute_set::Singular.new(10),
      attribute_set::Singular.new(20),
    ])

    expect(attributes[:singular].value).to eq 10
  end
end
