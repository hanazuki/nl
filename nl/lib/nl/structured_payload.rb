module Nl
  # Shared handling for a payload containing an optional fixed header followed
  # by an optional attribute set.
  module StructuredPayload
    def self.included(base)
      base.extend(ClassMethods)
    end

    attr_accessor :fixed_header, :attributes

    def initialize(fixed_header = nil, attributes = nil)
      @fixed_header = fixed_header
      @attributes = attributes
    end

    module ClassMethods
      def from_params(params = nil, external_selectors: [], **keywords)
        params = (params || {}).merge(keywords).transform_keys(&:to_sym)

        if self::FIXED_HEADER
          header_params = params.slice(*self::FIXED_HEADER.members)
          fixed_header = self::FIXED_HEADER.new(**header_params)
        else
          header_params = {}
        end

        if self::ATTRIBUTE_SET
          attribute_params = params.slice(*attribute_names)
          attributes = self::ATTRIBUTE_SET.build_attributes(
            attribute_params,
            external_selectors:,
          )
        else
          attribute_params = {}
        end

        unknown = params.keys - header_params.keys - attribute_params.keys
        unless unknown.empty?
          raise ArgumentError, "unknown parameters: #{unknown.join(', ')}"
        end

        new(fixed_header, attributes)
      end

      def decode(decoder, external_selectors: [])
        fixed_header = self::FIXED_HEADER&.decode(decoder)
        attributes = self::ATTRIBUTE_SET&.decode(decoder, external_selectors:)
        new(fixed_header, attributes)
      end

      private def attribute_names
        self::ATTRIBUTE_SET::BY_NAME.keys
      end
    end

    def encode(encoder, external_selectors: [])
      fixed_header&.encode(encoder)
      attributes&.encode(encoder, external_selectors:)
    end
  end
end
