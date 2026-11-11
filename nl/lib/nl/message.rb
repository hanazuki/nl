require_relative 'attribute_set'

module Nl
  # Family payload with fixed-header fields and attribute values stored inline.
  class Message
    include Attributes

    EMPTY_FIELD_NAMES = [].freeze

    class << self
      def from_params(params = {})
        build_instance(params)
      end

      private def validate_params(params, header_names, attribute_names)
        unknown = params.keys - header_names - attribute_names
        raise ArgumentError, "unknown parameters: #{unknown.join(', ')}" unless unknown.empty?
      end
    end
  end
end
