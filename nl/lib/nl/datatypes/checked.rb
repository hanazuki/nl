require_relative '../decoder'
require_relative '../encoder'

module Nl
  module DataTypes
    # Validation applies to the decoded value, or the value being encoded.
    class Checked
      def initialize(datatype, check:)
        @datatype = datatype
        @check = check
      end

      def nlattr_type_flags(value = nil, context: nil)
        @datatype.nlattr_type_flags(value, context:)
      end

      def coerce(value, context: nil)
        @datatype.coerce(value, context:)
      end

      def encode(encoder, value, context: nil)
        @check.call(value)
        @datatype.encode(encoder, value, context:)
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        value = @datatype.decode(decoder, context:, nlattr_type_flags:)
        @check.call(value)
        value
      end
    end

    # Structured binary and packed arrays validate their encoded bytes.
    class CheckedPayload
      def initialize(datatype, check:)
        @datatype = datatype
        @check = check
      end

      def nlattr_type_flags(value = nil, context: nil)
        @datatype.nlattr_type_flags(value, context:)
      end

      def coerce(value, context: nil)
        @datatype.coerce(value, context:)
      end

      def encode(encoder, value, context: nil)
        temporary = Encoder.new
        @datatype.encode(temporary, value, context:)
        payload = temporary.buffer.get_string
        @check.call(payload)
        encoder.put_string(payload)
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        payload = decoder.get_string
        @check.call(payload)
        nested = Decoder.new(IO::Buffer.for(payload))
        nested.limit(payload.bytesize) do
          @datatype.decode(nested, context:, nlattr_type_flags:)
        end
      end
    end
  end
end
