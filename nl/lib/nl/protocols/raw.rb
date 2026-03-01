require_relative '../encoder'
require_relative '../decoder'

module Nl
  module Protocols
    # The raw Netlink protocol
    class Raw
      class Done
      end
      class Ack
      end

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

      def send_message(socket, message)
        seq_pid = socket.complete(message.header)
        encoder = Encoder.new
        encode_message(encoder, message)
        socket.sendmsg(encoder.buffer.get_string, 0, Socket.sockaddr_nl(0, 0))
        seq_pid
      end

      def recv_message(socket, seq_pid, message_class)
        data, = socket.recvmsg

        decoder = Decoder.new(IO::Buffer.for(data))
        while decoder.available?(Core::NLMSG_HDRLEN)
          header = Core::NlMsgHdr.decode(decoder)
          decoder.align_to(Core::NLMSG_ALIGNTO)
          raise binding.irb unless [header.seq, header.pid] == seq_pid
          if header.type < Core::NLMSG_MIN_TYPE
            # Control messages
            case header.type
            when Core::NLMSG_ERROR
              errno = decoder.get_value(Endian::Host::SINT)
              if errno == 0
                yield Ack.new
              else
                yield SystemCallError.new(-errno)
              end
              decoder.skip(header.len - Core::NLMSG_HDRLEN - 4)
            when Core::NLMSG_DONE
              yield Done.new
              decoder.skip(header.len - Core::NLMSG_HDRLEN)
            else
              # just ignore NLMSG_NOOP and other unknown control messages
              decoder.skip(header.len - Core::NLMSG_HDRLEN)
            end
          else
            # Subsystem-specific messages
            decoder.limit(header.len - Core::NLMSG_HDRLEN) do
              decoder.align_to(Core::NLMSG_ALIGNTO)
              yield message_class.decode(decoder, header)
            end
          end
        end
      end

      # @param socket [Socket] Netlink socket
      # @param type [:do, :dump] Request type
      # @param request_class [Class] Request message class
      # @param reply_class [Class] Reply message class
      # @param args [Hash] Request arguments
      def exchange_message(socket, type, request_class, reply_class, args)
        flags = Core::NLM_F_REQUEST
        flags |= type == :dump ? Core::NLM_F_DUMP : Core::NLM_F_ACK

        request = request_class.from_params(args)
        request.header.flags = flags
        seq_pid = send_message(socket, request)

        result = [] unless block_given?

        done = false
        begin
          recv_message(socket, seq_pid, reply_class) do |message|
            case message
            when Done, Ack
              done = true
            when Exception
              raise message
            else
              if block_given?
                yield message
              else
                result << message
              end
            end
          end
        end until done

        unless block_given?
          type == :dump ? result : result.first
        end
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
            attrs.compact
          end

          private def encode1(encoder, attr)
            nlattr = Core::NlAttr.new(0, attr.class::TYPE)
            encoder.measure(Endian::Host::U16) do
              nlattr.encode(encoder)
              attr.encode(encoder)
            end
            encoder.align_to(Core::NLA_ALIGNTO)
          end

          def encode(encoder, attrs)
            attrs.each do |attr|
              encode1(encoder, attr)
            end
          end

          def build_attributes(**params)
            params.map do |name, value|
              attr_class = self::BY_NAME[name] or raise "Unknown attribute #{name}"
              attr_class.new(value)
            end
          end
        end
      end

      class Message
        attr_accessor :header, :fixed_header, :attributes

        def initialize(header, fixed_header = nil, attributes = [])
          @header = header
          @fixed_header = fixed_header
          @attributes = attributes
        end

        def self.from_params(params)
          if self::FIXED_HEADER
            header_params = params.slice(*self::FIXED_HEADER.members.map(&:name))
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
            @header.encode(encoder)
            @fixed_header.encode(encoder) if @fixed_header
            self.class::ATTRIBUTE_SET.encode(encoder, @attributes)
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

        def to_h
          to_h_rec(@attributes, @fixed_header&.to_h || {})
        end

        # FIXME:
        private def to_h_rec(attributes, init = {})
          attributes.each_with_object(init) do |attr, h|
            if attr.class::DATATYPE.is_a?(DataTypes::NestedAttributes)
              h[attr.class::NAME] = to_h_rec(attr.value)
            else
              h[attr.class::NAME] = attr.value
            end
          end
        end
      end

      module DataTypes
        class Scalar
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

        class String
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

        class Binary
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

        class Flag
          def encode(encoder, value)
            # flag attribute has no payload; presence encodes true
          end

          def decode(decoder)
            true
          end
        end

        # A 32-bit value paired with a selector mask (8 bytes total: value u32 + selector u32)
        class Bitfield32
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

        class Pad
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

        class NestedAttributes
          def initialize(attribute_set)
            @attribute_set = attribute_set
          end

          def encode(encoder, value)
            @attribute_set.encode(encoder, value)
          end

          def decode(decoder)
            @attribute_set.decode(decoder)
          end
        end

        class IndexedArray
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
