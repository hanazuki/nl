require_relative 'socket'

module Nl
  class Family
    def initialize(socket)
      @socket = socket
    end

    def self.open
      begin
        socket = Socket.new(self::PROTONUM)
        socket.bind(Socket.sockaddr_nl(0, 0))
        if block_given?
          yield new(socket)
        else
          return new(socket)
        end
      ensure
        socket&.close if block_given?
      end
    end

    def exchange_message(type, request_class, reply_class, args)
      self.class::PROTOCOL.exchange_message(@socket, type, request_class, reply_class, args)
    end

    class Message
      attr_accessor :header, :fixed_header, :attributes

      def initialize(header, fixed_header = nil, attributes = [])
        @header = header
        @fixed_header = fixed_header
        @attributes = attributes
      end

      def self.from_params(params)
        header_params = params.slice(*self::HEADER_PARAMS)
        attribute_params = params.slice(*self::ATTRIBUTE_PARAMS)
        # TODO: Reject unknown params

        header = Core::NlMsgHdr.new(0, self::TYPE, nil, nil, nil)
        fixed_header = self::FIXED_HEADER&.new(**header_params)
        attributes = self::ATTRIBUTE_SET.build_attributes(**attribute_params)
        new(header, fixed_header, attributes)
      end

      def append_attribute(attribute)
        @attributes << attribute
      end

      def encode(encoder)
        validate!

        encoder.measure(Endian::Host::U16) do
          @header.encode(encoder)
          @fixed_header.encode(encoder) if @fixed_header
          @attributes.each do |attr|
            attr.encode(encoder)
          end
        end
      end

      def self.decode(decoder, header)
        unless self::TYPE == header.type
          raise "Expected message type #{self::TYPE}, got #{header.type}"
        end

        if fixed_header_class = self::FIXED_HEADER
          fixed_header = fixed_header_class.decode(decoder)
        end

        attributes = self::ATTRIBUTE_SET.decode(decoder)

        new(header, fixed_header, attributes).tap(&:validate!)
      end

      def validate!
        unless self.class::TYPE == header.type
          raise "Expected message type #{self.class::FIXED_HEADER}, got #{header.type}"
        end
        # TODO: Validate fixed header and attributes
        # @fixed_header&.validate!
        # @attributes.each(&:validate!)
      end

      def to_h
        @attributes.each_with_object(@fixed_header&.to_h || {}) do |attr, h|
          h[attr.class::NAME] = attr.value
        end
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
            if attr_class = self::BY_TYPE[nlattr.type]
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
          nlattr = Core::NlAttr.new(attr.class::TYPE, 0)
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
  end
end
