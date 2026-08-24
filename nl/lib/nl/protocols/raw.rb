require_relative '../encoder'
require_relative '../decoder'

module Nl
  module Protocols
    # The raw Netlink protocol
    class Raw
      Done = Data.define(:error)
      Ack = Data.define
      Ignored = Data.define

      attr_reader :name, :protonum

      def initialize(name, protonum)
        @name = name
        @protonum = protonum
      end

      def encode_message(encoder, message)
        message.encode(encoder)
      end

      def decode_message(decoder, message_class)
        header = NlMsgHdr.decode(decoder)
        decoder.limit(header.len - Core::NLMSG_HDRLEN) do
          message_class.decode(decoder, header)
        end
      end

      # Decodes one frame using the reply class associated with its sequence.
      def decode_frame(header, payload, message_class)
        decoder = Decoder.new(payload)
        if header.type < Core::NLMSG_MIN_TYPE
          case header.type
          when Core::NLMSG_ERROR
            errno = decoder.get_value(Endian::Host::SINT)
            errno == 0 ? Ack.new : SystemCallError.new(-errno)
          when Core::NLMSG_DONE
            return Done.new(error: nil) unless decoder.available?

            errno = decoder.get_value(Endian::Host::SINT)
            if errno.positive?
              raise Decoder::Error, "expected zero or negative NLMSG_DONE errno, got #{errno}"
            end

            error = SystemCallError.new(-errno) if errno.negative?
            Done.new(error:)
          else
            Ignored.new
          end
        else
          raise ArgumentError, 'reply class is required for a data message' unless message_class

          message_class.decode(decoder, header)
        end
      end

      def send_message(socket, message)
        seq_pid = socket.complete(message.nlmsg_header)
        encoder = Encoder.new
        encode_message(encoder, message)
        socket.sendmsg(encoder.buffer.get_string, 0, Socket.sockaddr_nl(0, 0))
        seq_pid
      end

      def build_request(kind, request_class, args)
        flags = Core::NLM_F_REQUEST
        flags |= kind == :dump ? Core::NLM_F_DUMP : Core::NLM_F_ACK

        request = request_class.from_params(args)
        request.nlmsg_header.flags = flags
        request
      end

      class AttributeSet
        Attribute = Struct.new(:value)
        class Attribute
          def self.decode(decoder)
            value = self::DATATYPE.decode(decoder)
            new(value)
          end

          def encode(encoder)
            self.class::DATATYPE.encode(encoder, self.value)
          end
        end

        def initialize(attributes)
          attr_class = self.class::Attribute

          attributes.each do |attr|
            unless attr.kind_of?(attr_class)
              raise TypeError, "attribute must be an instance of #{attr_class}"
            end
          end

          @attributes = Array(attributes)
        end

        def [](type)
          case type
          when Symbol
            attr_class = self.class.by_name(type)
          when Integer
            attr_class = self.class.by_type(type)
          else
            raise TypeError, "attribute type must be a Symbol or an Integer"
          end

          # TODO: multi-attr
          @attributes.find { it.kind_of?(attr_class) } rescue binding.irb
        end

        def <<(attr)
          attr_class = self.class::Attribute
          unless attr.kind_of?(attr_class)
            raise TypeError, "attribute must be an instance of #{attr_class}"
          end

          @attributes << attr
        end

        private def encode1(encoder, attr)
          datatype = attr.class::DATATYPE
          type = attr.class::TYPE | datatype.nlattr_type_flags
          nlattr = Core::NlAttr.new(0, type)
          encoder.measure(Endian::Host::U16) do
            nlattr.encode(encoder)
            attr.encode(encoder)
          end
          encoder.align_to(Core::NLA_ALIGNTO)
        end

        def encode(encoder)
          @attributes.each do |attr|
            encode1(encoder, attr)
          end
        end

        class << self
          private def decode1(decoder)
            nlattr = Core::NlAttr.decode(decoder)
            attr = decoder.limit(nlattr.len - Core::NLA_HDRLEN) do
              if attr_class = self::BY_TYPE[nlattr.type & Core::NLA_TYPE_MASK]
                attr_class.decode(decoder)
              else
                decoder.skip
                nil
              end
            end
            decoder.align_to(Core::NLA_ALIGNTO)
            attr
          end

          def decode(decoder)
            attrs = []
            while decoder.available?
              attr = decode1(decoder)
              attrs << attr
            end
            new(attrs.compact)
          end

          def build_attributes(**params)
            attrs = params.map do |name, value|
              attr_class = self::BY_NAME[name] or raise "Unknown attribute #{name}"
              attr_class.new(value)
            end
            new(attrs)
          end
        end
      end

      class Message
        attr_accessor :nlmsg_header, :fixed_header, :attributes

        def initialize(header, fixed_header = nil, attributes = self.class::ATTRIBUTE_SET.new)
          @nlmsg_header = header
          @fixed_header = fixed_header
          @attributes = attributes
        end

        def self.from_params(params)
          if self::FIXED_HEADER
            header_params = params.slice(*self::FIXED_HEADER.members)
            fixed_header = self::FIXED_HEADER.new(**header_params)
          end
          attribute_params = params.slice(*self::ATTRIBUTES)
          attributes = self::ATTRIBUTE_SET.build_attributes(**attribute_params)

          unknown = params.keys - attribute_params.keys
          unknown -= header_params.keys if header_params
          unless unknown.empty?
            raise ArgumentError, "unknown parameters: #{unknown.join(', ')}"
          end

          header = Core::NlMsgHdr.new(0, self::TYPE, nil, nil, nil)
          new(header, fixed_header, attributes)
        end

        def append_attribute(attribute)
          @attributes << attribute
        end

        def encode(encoder)
          encoder.measure(Endian::Host::U16) do
            @nlmsg_header.encode(encoder)
            @fixed_header&.encode(encoder)
            @attributes.encode(encoder)
          end
        end

        def self.decode(decoder, header, type: header.type)
          unless self::TYPE == type
            raise "Expected message type #{self::TYPE}, got #{type}"
          end

          if fixed_header_class = self::FIXED_HEADER
            fixed_header = fixed_header_class.decode(decoder)
          end

          attributes = self::ATTRIBUTE_SET.decode(decoder)

          new(header, fixed_header, attributes)
        end
      end

      module DataTypes
        class Base
          def nlattr_type_flags
            0
          end
        end

        class Scalar < Base
          def initialize(type, check)
            @type = type
            @check = check
          end

          def encode(encoder, value)
            value ||= 0
            encoder.put_value(@type, value.tap(&@check))
          end

          def decode(decoder)
            value = decoder.get_value(@type).tap(&@check)
          end
        end

        class String < Base
          def initialize(check)
            @check = check
          end

          def encode(encoder, value)
            encoder.put_zstring(value)
          end

          def decode(decoder)
            decoder.get_zstring
          end
        end

        class Binary < Base
          def initialize(check)
            @check = check
          end

          def encode(encoder, value)
            encoder.put_string(value)
          end

          def decode(decoder)
            decoder.get_string
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
            Core::NLA_F_NESTED
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

          def decode(decoder)
            decode_level(decoder, @levels)
          end

          private def encode_level(encoder, values, levels)
            values.each do |type, value|
              nlattr = Core::NlAttr.new(0, type | Core::NLA_F_NESTED)
              encoder.measure(Endian::Host::U16) do
                nlattr.encode(encoder)
                if levels == 1
                  value.encode(encoder)
                else
                  encode_level(encoder, value, levels - 1)
                end
              end
              encoder.align_to(Core::NLA_ALIGNTO)
            end
          end

          private def decode_level(decoder, levels)
            result = {}
            while decoder.available?(Core::NLA_HDRLEN)
              nlattr = Core::NlAttr.decode(decoder)
              type = nlattr.type & Core::NLA_TYPE_MASK
              value = decoder.limit(nlattr.len - Core::NLA_HDRLEN) do
                if levels == 1
                  @attribute_set.decode(decoder)
                else
                  decode_level(decoder, levels - 1)
                end
              end
              decoder.align_to(Core::NLA_ALIGNTO)
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
              nlattr = Core::NlAttr.new(0, i + 1)
              encoder.measure(Endian::Host::U16) do
                nlattr.encode(encoder)
                @sub_type.encode(encoder, value)
              end
              encoder.align_to(Core::NLA_ALIGNTO)
            end
          end

          def decode(decoder)
            result = []
            while decoder.available?
              nlattr = Core::NlAttr.decode(decoder)
              element = decoder.limit(nlattr.len - Core::NLA_HDRLEN) do
                @sub_type.decode(decoder)
              end
              decoder.align_to(Core::NLA_ALIGNTO)
              result << element
            end
            result
          end
        end
      end
    end
  end
end
