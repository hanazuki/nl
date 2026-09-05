require_relative 'datatypes'

module Nl
  class AttributeSet
    Attribute = Struct.new(:value)
    class Attribute
      MULTI = false
      ORDER = nil
      SELECTOR_SLOT = nil

      def self.multi?
        self::MULTI
      end

      def self.decode(decoder, context: nil, nlattr_type_flags: 0)
        new(self::DATATYPE.decode(decoder, context:, nlattr_type_flags:))
      end

      def encode(encoder, context: nil)
        self.class::DATATYPE.encode(encoder, self.value, context:)
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

      attributes = @attributes.select { it.kind_of?(attr_class) }
      attr_class.multi? ? attributes : attributes.first
    end

    def <<(attr)
      attr_class = self.class::Attribute
      unless attr.kind_of?(attr_class)
        raise TypeError, "attribute must be an instance of #{attr_class}"
      end

      @attributes << attr
    end

    SELECTOR_NAMES = {local: [].freeze, external: [].freeze}.freeze

    private def encode1(encoder, attr, context)
      datatype = attr.class::DATATYPE
      flags = datatype.nlattr_type_flags(attr.value, context:)
      type = attr.class::TYPE | flags
      nlattr = Raw::NlAttr.new(0, type)
      encoder.measure(Endian::Host::U16) do
        nlattr.encode(encoder)
        attr.encode(encoder, context:)
      end
      encoder.align_to(Raw::NLA_ALIGNTO)
    end

    def encode(encoder, external_selectors: [])
      context = Selector::State.new(self.class::SELECTOR_NAMES.fetch(:local).length, external_selectors)
      @attributes.each do |attr|
        if slot = attr.class::SELECTOR_SLOT
          context.set_local(slot, attr.value)
        end
      end

      attributes = @attributes.sort_by { it.class::ORDER }
      attributes.each do |attr|
        encode1(encoder, attr, context)
      end
    rescue Selector::MissingSelectorValueError => error
      raise ArgumentError, "selector #{selector_name(error).inspect} is required by a dependent attribute"
    rescue Selector::UnknownSelectorValueError => error
      raise ArgumentError, "unknown sub-message selector value: #{error.value.inspect}"
    end

    private def selector_name(error)
      self.class::SELECTOR_NAMES.fetch(error.scope).fetch(error.index)
    end

    class << self
      private def decode1(decoder, context)
        nlattr = Raw::NlAttr.decode(decoder)
        flags = nlattr.type & (Raw::NLA_F_NESTED | Raw::NLA_F_NET_BYTEORDER)
        attr = decoder.limit(nlattr.len - Raw::NLA_HDRLEN) do
          if attr_class = self::BY_TYPE[nlattr.type & Raw::NLA_TYPE_MASK]
            attr_class.decode(decoder, context:, nlattr_type_flags: flags)
          else
            decoder.skip
            nil
          end
        end
        decoder.align_to(Raw::NLA_ALIGNTO)
        if attr && (slot = attr.class::SELECTOR_SLOT)
          context.set_local(slot, attr.value)
        end
        attr
      end

      def decode(decoder, external_selectors: [])
        context = Selector::State.new(self::SELECTOR_NAMES.fetch(:local).length, external_selectors)
        attrs = []
        while decoder.available?
          attr = decode1(decoder, context)
          attrs << attr
        end
        new(attrs.compact)
      rescue Selector::MissingSelectorValueError => error
        raise Decoder::Error,
          "selector #{selector_name(error).inspect} must precede the dependent attribute"
      rescue Selector::UnknownSelectorValueError => error
        raise Decoder::Error, "unknown sub-message selector value: #{error.value.inspect}"
      end

      def build_attributes(params = nil, external_selectors: [], **keywords)
        params = (params || {}).merge(keywords)
        unknown = params.keys - self::BY_NAME.keys
        raise ArgumentError, "unknown attributes: #{unknown.join(', ')}" unless unknown.empty?

        context = Selector::State.new(self::SELECTOR_NAMES.fetch(:local).length, external_selectors)
        coerced_selectors = {}
        self::SELECTOR_NAMES.fetch(:local).each_with_index do |name, slot|
          next unless params.key?(name)
          attr_class = self::BY_NAME.fetch(name)
          value = attr_class::DATATYPE.coerce(params.fetch(name))
          coerced_selectors[name] = value
          context.set_local(slot, value)
        end

        attrs = params.sort_by { |name, _| self::BY_NAME.fetch(name)::ORDER }.flat_map do |name, value|
          attr_class = self::BY_NAME[name] or raise "Unknown attribute #{name}"
          if attr_class.multi?
            unless value.is_a?(Array)
              raise TypeError, "value for multi-attribute #{name} must be an Array"
            end
            value.map { attr_class.new(coerce(attr_class::DATATYPE, it, context)) }
          else
            value = coerced_selectors.fetch(name) { coerce(attr_class::DATATYPE, value, context) }
            attr_class.new(value)
          end
        end
        new(attrs)
      rescue Selector::MissingSelectorValueError => error
        raise ArgumentError, "selector #{selector_name(error).inspect} is required by a dependent attribute"
      rescue Selector::UnknownSelectorValueError => error
        raise ArgumentError, "unknown sub-message selector value: #{error.value.inspect}"
      end

      private def coerce(datatype, value, context)
        datatype.coerce(value, context:)
      end

      private def selector_name(error)
        self::SELECTOR_NAMES.fetch(error.scope).fetch(error.index)
      end

    end
  end
end
