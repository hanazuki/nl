require_relative 'socket'

module Nl
  class Family
    def initialize(socket)
      @socket = socket
    end

    def self.open
      begin
        socket = Socket.new(self::PROTOCOL.protonum)
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
  end
end
