require_relative 'raw/wire'
require_relative 'bitfield32'
require_relative 'datatypes/defaults'
require_relative 'datatypes/checked'
require_relative 'datatypes/scalar'

module Nl
  # @rbs!
  #   interface _DataType
  #     def encode: (Encoder, untyped, ?context: untyped) -> void
  #     def decode: (Decoder, ?context: untyped, ?nlattr_type_flags: Integer) -> untyped
  #     def nlattr_type_flags: (?untyped, ?context: untyped) -> Integer
  #     def coerce: (untyped, ?context: untyped) -> untyped
  #   end

  module DataTypes
    class VariableInteger
      include Defaults

      UINT32_RANGE = (0...2**32)
      UINT64_RANGE = (0...2**64)
      SINT32_RANGE = (-(2**31)...2**31)
      SINT64_RANGE = (-(2**63)...2**63)

      def initialize(byte_order, signed:)
        prefix = signed ? 'S' : 'U'
        @type32 = byte_order.const_get("#{prefix}32")
        @type64 = byte_order.const_get("#{prefix}64")
        @scalar32 = Scalar[@type32].new
        @scalar64 = Scalar[@type64].new
        @range32 = signed ? SINT32_RANGE : UINT32_RANGE
        @range64 = signed ? SINT64_RANGE : UINT64_RANGE
      end

      def encode(encoder, value, context: nil)
        unless @range64.cover?(value)
          raise RangeError, "integer #{value.inspect} is outside the #{@range64.begin}...#{@range64.end} range"
        end

        type = @range32.cover?(value) ? @type32 : @type64
        encoder.put_value(type, value)
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        scalar = case decoder.remaining
        when 4 then @scalar32
        when 8 then @scalar64
        else
          raise Decoder::Error, "variable integer payload must be 4 or 8 bytes, got #{decoder.remaining}"
        end
        scalar.decode(decoder)
      end
    end

    class String
      include Defaults

      def encode(encoder, value, context: nil)
        encoder.put_zstring(value)
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        decoder.get_zstring
      end
    end

    class Binary
      include Defaults

      def initialize(length: nil)
        @length = length
      end

      def encode(encoder, value, context: nil)
        if @length && value.bytesize != @length
          raise ArgumentError, "binary value must be exactly #{@length} bytes, got #{value.bytesize}"
        end
        encoder.put_string(value)
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        decoder.get_string(@length || decoder.remaining)
      end
    end

    # An array whose elements are packed consecutively without per-element
    # headers or alignment padding.
    class PackedArray
      include Defaults

      def initialize(sub_type)
        @sub_type = sub_type
      end

      def encode(encoder, values, context: nil)
        values = coerce(values, context:)
        values.each { @sub_type.encode(encoder, it, context:) }
      end

      def coerce(values, context: nil)
        values.map { @sub_type.coerce(it, context:) }
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        result = []
        result << @sub_type.decode(decoder, context:, nlattr_type_flags: 0) while decoder.available?
        result
      end
    end

    class Struct
      include Defaults

      def initialize(type, consume_remaining: false)
        @type = type
        @consume_remaining = consume_remaining
      end

      def coerce(value, context: nil)
        return value unless value.is_a?(Hash)

        @type.from_params(value, context:)
      end

      def encode(encoder, value, context: nil)
        unless value.is_a?(@type)
          raise TypeError, "value must be an instance of #{@type}"
        end

        value.encode(encoder)
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        value = @type.decode(decoder)
        decoder.skip if @consume_remaining
        value
      end
    end

    class Flag
      include Defaults

      def encode(encoder, value, context: nil)
        # flag attribute has no payload; presence encodes true
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        true
      end
    end

    class Bitfield32
      include Defaults

      def encode(encoder, value, context: nil)
        unless value.is_a?(Nl::Bitfield32)
          raise TypeError, 'bitfield32 value must be an Nl::Bitfield32'
        end

        encoder.put_value(Endian::Host::U32, value.value)
        encoder.put_value(Endian::Host::U32, value.selector)
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        value = decoder.get_host_u32
        selector = decoder.get_host_u32
        Nl::Bitfield32.new(value, selector)
      end
    end

    class Pad
      include Defaults

      def initialize(length = nil)
        @length = length
      end

      def encode(encoder, _value, context: nil)
        encoder.put_string(?\0.b * @length) if @length
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        @length ? decoder.skip(@length) : decoder.skip
        nil
      end
    end

    class NestedAttributes
      include Defaults

      def initialize(attribute_set, selector_bindings: [])
        @attribute_set = attribute_set
        @selector_bindings = selector_bindings
      end

      def nlattr_type_flags(_value = nil, context: nil)
        Raw::NLA_F_NESTED
      end

      def coerce(value, context: nil)
        value.is_a?(Hash) ? @attribute_set.build_instance(value, external_selectors: selectors(context)) : value
      end

      def encode(encoder, value, context: nil)
        unless value.is_a?(@attribute_set)
          raise TypeError, "value must be an instance of #{@attribute_set}"
        end

        value.encode(encoder, external_selectors: selectors(context))
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        @attribute_set.decode(decoder, external_selectors: selectors(context))
      end

      private def selectors(context)
        return Selector::EMPTY_VALUES if @selector_bindings.empty?

        @selector_bindings.map { it.read(context) }
      end
    end

    class SubMessage
      include Defaults

      Format = Data.define(:type, :selector_bindings, :nested)

      def initialize(selector, formats)
        @selector = selector
        @formats = formats.transform_values do |format|
          format.is_a?(Format) ? format : Format.new(*format)
        end.freeze
      end

      def nlattr_type_flags(value = nil, context:)
        if value.is_a?(RawSubMessage)
          @selector.read(context)
          return value.nlattr_type_flags
        end

        format = @selector.select(context, @formats)
        unless value.is_a?(format.type)
          raise TypeError, "value must be an instance of #{format.type}"
        end
        format.nested ? Raw::NLA_F_NESTED : 0
      end

      def coerce(value, context:)
        if value.is_a?(RawSubMessage)
          @selector.read(context)  # ensure selector value is present
          return value
        end

        format = @selector.select(context, @formats)
        return value if value.is_a?(format.type)
        return format.type.build_instance(value, external_selectors: selectors(format, context)) if value.is_a?(Hash)

        raise TypeError, "value must be a Hash or an instance of #{format.type}"
      end

      def encode(encoder, value, context: nil)
        if value.is_a?(RawSubMessage)
          @selector.read(context)
          return value.encode(encoder)
        end

        format = @selector.select(context, @formats)
        unless value.is_a?(format.type)
          raise TypeError, "value must be an instance of #{format.type}"
        end
        value.encode(encoder, external_selectors: selectors(format, context))
      end

      def decode(decoder, context:, nlattr_type_flags: 0)
        format = @selector.select(context, @formats) do
          return RawSubMessage.new(
            decoder.get_string,
            nlattr_type_flags:,
          )
        end
        format.type.decode(decoder, external_selectors: selectors(format, context))
      end

      private def selectors(format, context)
        return Selector::EMPTY_VALUES if format.selector_bindings.empty?

        format.selector_bindings.map { it.read(context) }
      end
    end

    # Nested attributes whose type numbers are keys rather than members of
    # an attribute set. Each level is returned as an Integer-keyed Hash;
    # values at the innermost level are decoded as @attribute_set.
    class NestTypeValue
      include Defaults

      def initialize(attribute_set, levels, selector_bindings: [])
        raise ArgumentError, 'levels must be positive' unless levels.positive?

        @attribute_set = attribute_set
        @levels = levels
        @selector_bindings = selector_bindings
      end

      def encode(encoder, value, context: nil)
        encode_level(encoder, value, @levels, selectors(context))
      end

      def coerce(value = nil, context: nil, **keywords)
        value = keywords unless keywords.empty?
        coerce_level(value, @levels, selectors(context))
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        decode_level(decoder, @levels, selectors(context))
      end

      private def encode_level(encoder, values, levels, external_selectors)
        values.each do |type, value|
          encoder.measure(Endian::Host::U16) do
            encoder.put_value(Endian::Host::U16, 0)  # nla_len
            encoder.put_value(Endian::Host::U16, type | Raw::NLA_F_NESTED)  # nla_type
            if levels == 1
              if external_selectors.empty?
                value.encode(encoder)
              else
                value.encode(encoder, external_selectors:)
              end
            else
              encode_level(encoder, value, levels - 1, external_selectors)
            end
          end
          encoder.align_to(Raw::NLA_ALIGNTO)
        end
      end

      private def coerce_level(values, levels, external_selectors)
        values.transform_values do |value|
          if levels == 1
            if value.is_a?(Hash)
              external_selectors.empty? ? @attribute_set.build_instance(value) :
                @attribute_set.build_instance(value, external_selectors:)
            else
              value
            end
          else
            coerce_level(value, levels - 1, external_selectors)
          end
        end
      end

      private def decode_level(decoder, levels, external_selectors)
        result = {}
        while decoder.available?(Raw::NLA_HDRLEN)
          # Read the attribute header without allocating a wrapper.
          length = decoder.get_host_u16
          type = decoder.get_host_u16 & Raw::NLA_TYPE_MASK
          if length < Raw::NLA_HDRLEN
            raise Decoder::Error,
              "attribute length must be at least #{Raw::NLA_HDRLEN} bytes, got #{length}"
          end
          value = decoder.limit(length - Raw::NLA_HDRLEN) do
            if levels == 1
              external_selectors.empty? ? @attribute_set.decode(decoder) :
                @attribute_set.decode(decoder, external_selectors:)
            else
              decode_level(decoder, levels - 1, external_selectors)
            end
          end
          decoder.align_to(Raw::NLA_ALIGNTO)
          result[type] = value
        end
        result
      end

      private def selectors(context)
        return Selector::EMPTY_VALUES if @selector_bindings.empty?

        @selector_bindings.map { it.read(context) }
      end
    end

    class IndexedArray
      include Defaults

      def initialize(sub_type)
        @sub_type = sub_type
      end

      def encode(encoder, values, context: nil)
        values.each_with_index do |value, i|
          encoder.measure(Endian::Host::U16) do
            encoder.put_value(Endian::Host::U16, 0)  # nla_len
            encoder.put_value(Endian::Host::U16, i + 1)  # nla_type
            @sub_type.encode(encoder, value, context:)
          end
          encoder.align_to(Raw::NLA_ALIGNTO)
        end
      end

      def coerce(values, context: nil)
        values.map { @sub_type.coerce(it, context:) }
      end

      def decode(decoder, context: nil, nlattr_type_flags: 0)
        result = []
        while decoder.available?
          # Read the attribute header without allocating a wrapper.
          length = decoder.get_host_u16
          type = decoder.get_host_u16
          if length < Raw::NLA_HDRLEN
            raise Decoder::Error,
              "attribute length must be at least #{Raw::NLA_HDRLEN} bytes, got #{length}"
          end
          flags = type & (Raw::NLA_F_NESTED | Raw::NLA_F_NET_BYTEORDER)
          element = decoder.limit(length - Raw::NLA_HDRLEN) do
            @sub_type.decode(decoder, context:, nlattr_type_flags: flags)
          end
          decoder.align_to(Raw::NLA_ALIGNTO)
          result << element
        end
        result
      end
    end
  end
end
