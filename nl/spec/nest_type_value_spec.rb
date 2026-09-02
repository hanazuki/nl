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
end
