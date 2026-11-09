require_relative 'datatypes'

module Nl
  class AttributeSet
    Definition = Data.define(:id, :name, :datatype, :multi, :order, :selector_slot) do
      def initialize(id:, name:, datatype:, multi: false, order: 0, selector_slot: nil)
        super(id:, name:, datatype:, multi:, order:, selector_slot:)
      end
    end

    def initialize(attributes = [])
      # Alternating numeric IDs and values preserve duplicates and wire order
      # without allocating a wrapper or a pair array for each attribute.
      @attributes = attributes
    end

    def [](type)
      definition = definition_for(type)
      id = definition.id
      values = [] if definition.multi
      i = 0
      while i < @attributes.length
        if @attributes[i] == id
          return @attributes[i + 1] unless values
          values << @attributes[i + 1]
        end
        i += 2
      end
      values
    end

    def append(type, value)
      @attributes.push(definition_for(type).id, value)
      self
    end

    SELECTOR_NAMES = {local: [].freeze, external: [].freeze}.freeze

    private def definition_for(type)
      case type
      when Symbol then self.class.by_name(type)
      when Integer then self.class.by_type(type)
      else raise TypeError, 'attribute type must be a Symbol or an Integer'
      end
    end

    private def encode1(encoder, definition, value, context)
      datatype = definition.datatype
      flags = datatype.nlattr_type_flags(value, context:)
      type = definition.id | flags
      nlattr = Raw::NlAttr.new(0, type)
      encoder.measure(Endian::Host::U16) do
        nlattr.encode(encoder)
        datatype.encode(encoder, value, context:)
      end
      encoder.align_to(Raw::NLA_ALIGNTO)
    end

    def encode(encoder, external_selectors: Selector::EMPTY_VALUES)
      definitions = self.class::BY_TYPE
      local_count = self.class::SELECTOR_NAMES.fetch(:local).length
      context = Selector::State.for(local_count, external_selectors)
      unless local_count == 0
        i = 0
        while i < @attributes.length
          if slot = definitions.fetch(@attributes[i]).selector_slot
            context.set_local(slot, @attributes[i + 1])
          end
          i += 2
        end
      end

      indices = (0...@attributes.length).step(2).sort_by { definitions.fetch(@attributes[it]).order }
      indices.each do |i|
        encode1(encoder, definitions.fetch(@attributes[i]), @attributes[i + 1], context)
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
      private def decode1(decoder, context, attributes)
        length = decoder.get_host_u16
        type = decoder.get_host_u16
        if length < Raw::NLA_HDRLEN
          raise Decoder::Error,
            "attribute length must be at least #{Raw::NLA_HDRLEN} bytes, got #{length}"
        end
        flags = type & (Raw::NLA_F_NESTED | Raw::NLA_F_NET_BYTEORDER)
        id = type & Raw::NLA_TYPE_MASK
        definition = self::BY_TYPE[id]
        value = decoder.limit(length - Raw::NLA_HDRLEN) do
          if definition
            definition.datatype.decode(decoder, context:, nlattr_type_flags: flags)
          else
            decoder.skip
          end
        end
        decoder.align_to(Raw::NLA_ALIGNTO)
        if definition
          attributes.push(id, value)
          if slot = definition.selector_slot
            context.set_local(slot, value)
          end
        end
      end

      def decode(decoder, external_selectors: Selector::EMPTY_VALUES)
        local_count = self::SELECTOR_NAMES.fetch(:local).length
        context = Selector::State.for(local_count, external_selectors)
        attributes = []
        decode1(decoder, context, attributes) while decoder.available?
        new(attributes)
      rescue Selector::MissingSelectorValueError => error
        raise Decoder::Error,
          "selector #{selector_name(error).inspect} must precede the dependent attribute"
      rescue Selector::UnknownSelectorValueError => error
        raise Decoder::Error, "unknown sub-message selector value: #{error.value.inspect}"
      end

      def build_attributes(params = nil, external_selectors: Selector::EMPTY_VALUES, **keywords)
        params = (params || {}).merge(keywords)
        unknown = params.keys - self::BY_NAME.keys
        raise ArgumentError, "unknown attributes: #{unknown.join(', ')}" unless unknown.empty?

        context = Selector::State.for(
          self::SELECTOR_NAMES.fetch(:local).length,
          external_selectors,
        )
        coerced_selectors = {}
        self::SELECTOR_NAMES.fetch(:local).each_with_index do |name, slot|
          next unless params.key?(name)
          definition = self::BY_NAME.fetch(name)
          value = definition.datatype.coerce(params.fetch(name))
          coerced_selectors[name] = value
          context.set_local(slot, value)
        end

        attributes = []
        params.sort_by { |name, _| self::BY_NAME.fetch(name).order }.each do |name, value|
          definition = self::BY_NAME.fetch(name)
          if definition.multi
            unless value.is_a?(Array)
              raise TypeError, "value for multi-attribute #{name} must be an Array"
            end
            value.each do |entry|
              attributes.push(definition.id, coerce(definition.datatype, entry, context))
            end
          else
            value = coerced_selectors.fetch(name) { coerce(definition.datatype, value, context) }
            attributes.push(definition.id, value)
          end
        end
        new(attributes)
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
