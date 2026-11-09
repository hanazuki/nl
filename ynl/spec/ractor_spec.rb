require 'nl'
require_relative 'support/shareable_constants_matcher'

RSpec.describe 'Ractor compatibility of generated families', fork: true do
  before do
    skip 'Ractor is unavailable' unless defined?(Ractor)
  end

  def ractor_value(worker)
    worker.respond_to?(:value) ? worker.value : worker.take
  end

  def encode_message(message)
    ractor_value(Ractor.new(message) do |value|
      encoder = Nl::Encoder.new
      if value.is_a?(Nl::Genl::Message)
        Nl::Genl::GenlMsgHdr.new(value.class::TYPE, 1, 0).encode(encoder)
      end
      value.encode(encoder)
      encoder.buffer.get_string
    end)
  end

  def decode_message(message_class, bytes)
    ractor_value(Ractor.new(message_class, bytes) do |klass, wire|
      klass.decode(Nl::Decoder.new(IO::Buffer.for(wire)), type: klass::TYPE)
    end)
  end

  context 'with checked structured attributes' do
    let(:family) { Ynl::Family.build(File.join(__dir__, 'fixtures/fixed_struct_members.yaml')) }

    it 'makes every generated constant shareable' do
      expect(family).to have_shareable_constants
    end

    it 'encodes and decodes a struct containing a forward reference to another struct' do
      message_class = family::Messages::DoEchoReply
      message = message_class.from_params(record: {prefix: 1, bytes: 'abc', inner: {value: 2}, suffix: 3})
      decoded = decode_message(message_class, encode_message(message))

      expect(decoded.record).to have_attributes(prefix: 1, bytes: 'abc', suffix: 3)
      expect(decoded.record.inner.value).to eq(2)
      expect(encode_message(decoded)).to eq(encode_message(message))
    end
  end

  context 'with nested sub-messages' do
    let(:family) { Ynl::Family.build(File.join(__dir__, 'fixtures/sub_messages.yaml')) }

    it 'makes every generated constant shareable' do
      expect(family).to have_shareable_constants
    end

    it 'passes local and external selectors through nested attribute sets' do
      message_class = family::Messages::DoSetOuterRequest
      message = message_class.from_params(
        kind: 'foo', child: {leaf: {data: {header_value: 7, payload_value: 11}}},
      )
      decoded = decode_message(message_class, encode_message(message))

      expect(decoded.child.leaf.data).to have_attributes(header_value: 7, payload_value: 11)
      expect(encode_message(decoded)).to eq(encode_message(message))
    end
  end

  context 'with recursive attributes' do
    let(:family) { Ynl::Family.build(File.join(__dir__, 'fixtures/recursive.yaml')) }

    it 'makes every generated constant shareable' do
      expect(family).to have_shareable_constants
    end

    it 'encodes and decodes a notification containing recursive attribute sets' do
      message_class = family::Notifications::Changed
      message = message_class.from_params(encap: {child: {parent: {}}})
      decoded = decode_message(message_class, encode_message(message))

      expect(decoded.encap.child.parent).to be_a(family::AttributeSets::Outer)
      expect(encode_message(decoded)).to eq(encode_message(message))
    end
  end

  context 'with constant-backed checks' do
    let(:family) { Ynl::Family.build(File.join(__dir__, 'fixtures/constants.yaml')) }
    let(:attribute_set_class) { family::AttributeSets::Attrs }

    it 'makes every generated constant shareable' do
      expect(family).to have_shareable_constants
    end

    it 'encodes and decodes a valid checked attribute' do
      attributes = attribute_set_class.build_attributes(payload: 'abcd')
      bytes = ractor_value(Ractor.new(attributes) do |value|
        encoder = Nl::Encoder.new
        value.encode(encoder)
        encoder.buffer.get_string
      end)
      decoded = ractor_value(Ractor.new(attribute_set_class, bytes) do |klass, wire|
        klass.decode(Nl::Decoder.new(IO::Buffer.for(wire)))
      end)

      expect(decoded.payload).to eq('abcd')
    end

    it 'rejects an invalid attribute when encoding inside the Ractor' do
      attributes = attribute_set_class.build_attributes(payload: 'abcde')
      error = ractor_value(Ractor.new(attributes) do |value|
        value.encode(Nl::Encoder.new)
      rescue ArgumentError => caught
        caught
      end)

      expect(error).to be_an(ArgumentError)
      expect(error.message).to eq('Value "abcde" is longer than maximum length 4')
    end

    it 'rejects an invalid attribute when decoding inside the Ractor' do
      invalid = [9, attribute_set_class.by_name(:payload).id].pack('S S') + "abcde\0\0\0"
      error = ractor_value(Ractor.new(attribute_set_class, invalid) do |klass, wire|
        klass.decode(Nl::Decoder.new(IO::Buffer.for(wire)))
      rescue ArgumentError => caught
        caught
      end)

      expect(error).to be_an(ArgumentError)
      expect(error.message).to eq('Value "abcde" is longer than maximum length 4')
    end
  end
end
