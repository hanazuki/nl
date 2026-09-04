require_relative 'raw/wire'

module Nl
  # @rbs!
  #   interface _DataType
  #     def encode: (Encoder, untyped) -> void
  #     def decode: (Decoder) -> untyped
  #     def nlattr_type_flags: () -> Integer
  #     def coerce: (untyped) -> untyped
  #   end

  module DataTypes
    class Base
      def initialize(check: nil)
        @check = check
      end

      def nlattr_type_flags
        0
      end

      def coerce(value)
        value
      end

      private def checked(value)
        @check&.call(value)
        value
      end
    end

    class Scalar < Base
      def initialize(type, check:)
        super(check:)
        @type = type
      end

      def encode(encoder, value)
        encoder.put_value(@type, checked(value || 0))
      end

      def decode(decoder)
        checked(decoder.get_value(@type))
      end
    end

    class VariableInteger < Base
      UINT32_RANGE = (0...2**32)
      UINT64_RANGE = (0...2**64)
      SINT32_RANGE = (-(2**31)...2**31)
      SINT64_RANGE = (-(2**63)...2**63)

      def initialize(byte_order, signed:, check:)
        super(check:)
        prefix = signed ? 'S' : 'U'
        @type32 = byte_order.const_get("#{prefix}32")
        @type64 = byte_order.const_get("#{prefix}64")
        @range32 = signed ? SINT32_RANGE : UINT32_RANGE
        @range64 = signed ? SINT64_RANGE : UINT64_RANGE
      end

      def encode(encoder, value)
        value = checked(value || 0)
        unless @range64.cover?(value)
          raise RangeError, "integer #{value.inspect} is outside the #{@range64.begin}...#{@range64.end} range"
        end

        type = @range32.cover?(value) ? @type32 : @type64
        encoder.put_value(type, value)
      end

      def decode(decoder)
        type = case decoder.remaining
        when 4 then @type32
        when 8 then @type64
        else
          raise Decoder::Error, "variable integer payload must be 4 or 8 bytes, got #{decoder.remaining}"
        end
        checked(decoder.get_value(type))
      end
    end

    class String < Base
      def initialize(check:)
        super(check:)
      end

      def encode(encoder, value)
        encoder.put_zstring(checked(value))
      end

      def decode(decoder)
        checked(decoder.get_zstring)
      end
    end

    class Binary < Base
      def initialize(length: nil, check:)
        super(check:)
        @length = length
      end

      def encode(encoder, value)
        value = checked(value)
        if @length && value.bytesize != @length
          raise ArgumentError, "binary value must be exactly #{@length} bytes, got #{value.bytesize}"
        end
        encoder.put_string(value)
      end

      def decode(decoder)
        checked(decoder.get_string(@length || decoder.remaining))
      end
    end

    class Struct < Base
      def initialize(type, check: nil, consume_remaining: false)
        super(check:)
        @type = type
        @consume_remaining = consume_remaining
      end

      def coerce(value)
        return value unless value.is_a?(Hash)

        unknown = value.keys - @type::MEMBERS.keys
        raise ArgumentError, "unknown struct members: #{unknown.join(', ')}" unless unknown.empty?

        @type.new(*@type::MEMBERS.map { |name, datatype| datatype.coerce(value[name]) })
      end

      def encode(encoder, value)
        unless value.is_a?(@type)
          raise TypeError, "value must be an instance of #{@type}"
        end

        if @check
          temporary = Encoder.new
          value.encode(temporary)
          encoder.put_string(checked(temporary.buffer.get_string))
        else
          value.encode(encoder)
        end
      end

      def decode(decoder)
        unless @check
          value = @type.decode(decoder)
          decoder.skip if @consume_remaining
          return value
        end

        payload = checked(decoder.get_string)
        nested = Decoder.new(IO::Buffer.for(payload))
        nested.limit(payload.bytesize) do
          value = @type.decode(it)
          it.skip if @consume_remaining
          value
        end
      end
    end

    class Flag < Base
      def encode(encoder, value)
        # flag attribute has no payload; presence encodes true
      end

      def decode(decoder)
        true
      end
    end

    # A 32-bit value paired with a selector mask (8 bytes total: value u32 + selector u32)
    class Bitfield32 < Base
      def encode(encoder, value)
        v, selector = value.is_a?(Array) ? value : [value, 0xFFFFFFFF]
        encoder.put_value(Endian::Host::U32, v)
        encoder.put_value(Endian::Host::U32, selector)
      end

      def decode(decoder)
        value = decoder.get_value(Endian::Host::U32)
        selector = decoder.get_value(Endian::Host::U32)
        [value, selector]
      end
    end

    class Pad < Base
      def initialize(length = nil)
        @length = length
      end

      def encode(encoder, _value)
        encoder.put_string(?\0.b * @length) if @length
      end

      def decode(decoder)
        @length ? decoder.skip(@length) : decoder.skip
        nil
      end
    end

    class NestedAttributes < Base
      def initialize(attribute_set)
        @attribute_set = attribute_set
      end

      def nlattr_type_flags
        Raw::NLA_F_NESTED
      end

      def coerce(value)
        value.is_a?(Hash) ? @attribute_set.build_attributes(**value) : value
      end

      def encode(encoder, value)
        unless value.is_a?(@attribute_set)
          raise TypeError, "value must be an instance of #{@attribute_set}"
        end

        value.encode(encoder)
      end

      def decode(decoder)
        @attribute_set.decode(decoder)
      end
    end

    # Nested attributes whose type numbers are keys rather than members of
    # an attribute set. Each level is returned as an Integer-keyed Hash;
    # values at the innermost level are decoded as @attribute_set.
    class NestTypeValue < Base
      def initialize(attribute_set, levels)
        raise ArgumentError, 'levels must be positive' unless levels.positive?

        @attribute_set = attribute_set
        @levels = levels
      end

      def encode(encoder, value)
        encode_level(encoder, value, @levels)
      end

      def coerce(value)
        coerce_level(value, @levels)
      end

      def decode(decoder)
        decode_level(decoder, @levels)
      end

      private def encode_level(encoder, values, levels)
        values.each do |type, value|
          nlattr = Raw::NlAttr.new(0, type | Raw::NLA_F_NESTED)
          encoder.measure(Endian::Host::U16) do
            nlattr.encode(encoder)
            if levels == 1
              value.encode(encoder)
            else
              encode_level(encoder, value, levels - 1)
            end
          end
          encoder.align_to(Raw::NLA_ALIGNTO)
        end
      end

      private def coerce_level(values, levels)
        values.transform_values do |value|
          if levels == 1
            value.is_a?(Hash) ? @attribute_set.build_attributes(**value) : value
          else
            coerce_level(value, levels - 1)
          end
        end
      end

      private def decode_level(decoder, levels)
        result = {}
        while decoder.available?(Raw::NLA_HDRLEN)
          nlattr = Raw::NlAttr.decode(decoder)
          type = nlattr.type & Raw::NLA_TYPE_MASK
          value = decoder.limit(nlattr.len - Raw::NLA_HDRLEN) do
            if levels == 1
              @attribute_set.decode(decoder)
            else
              decode_level(decoder, levels - 1)
            end
          end
          decoder.align_to(Raw::NLA_ALIGNTO)
          result[type] = value
        end
        result
      end
    end

    class IndexedArray < Base
      def initialize(sub_type)
        @sub_type = sub_type
      end

      def encode(encoder, values)
        values.each_with_index do |value, i|
          nlattr = Raw::NlAttr.new(0, i + 1)
          encoder.measure(Endian::Host::U16) do
            nlattr.encode(encoder)
            @sub_type.encode(encoder, value)
          end
          encoder.align_to(Raw::NLA_ALIGNTO)
        end
      end

      def coerce(values)
        values.map { @sub_type.coerce(it) }
      end

      def decode(decoder)
        result = []
        while decoder.available?
          nlattr = Raw::NlAttr.decode(decoder)
          element = decoder.limit(nlattr.len - Raw::NLA_HDRLEN) do
            @sub_type.decode(decoder)
          end
          decoder.align_to(Raw::NLA_ALIGNTO)
          result << element
        end
        result
      end
    end
  end
end
