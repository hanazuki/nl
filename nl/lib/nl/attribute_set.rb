require_relative 'datatypes'

module Nl
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
      nlattr = Raw::NlAttr.new(0, type)
      encoder.measure(Endian::Host::U16) do
        nlattr.encode(encoder)
        attr.encode(encoder)
      end
      encoder.align_to(Raw::NLA_ALIGNTO)
    end

    def encode(encoder)
      @attributes.each do |attr|
        encode1(encoder, attr)
      end
    end

    class << self
      private def decode1(decoder)
        nlattr = Raw::NlAttr.decode(decoder)
        attr = decoder.limit(nlattr.len - Raw::NLA_HDRLEN) do
          if attr_class = self::BY_TYPE[nlattr.type & Raw::NLA_TYPE_MASK]
            attr_class.decode(decoder)
          else
            decoder.skip
            nil
          end
        end
        decoder.align_to(Raw::NLA_ALIGNTO)
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
end
