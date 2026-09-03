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
      def initialize(check:)
        super(check:)
      end

      def encode(encoder, value)
        encoder.put_string(checked(value))
      end

      def decode(decoder)
        checked(decoder.get_string)
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
