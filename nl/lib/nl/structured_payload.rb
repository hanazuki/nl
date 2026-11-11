require_relative 'attributes'

module Nl
  # Generated payloads store their fixed fields and attribute values directly.
  module StructuredPayload
    EMPTY_FIELD_NAMES = [].freeze

    def self.included(base)
      base.include(Attributes)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def from_params(params = {})
        build_instance(params)
      end

      private def validate_payload_params(params, header_names, attribute_names)
        unknown = params.keys - header_names - attribute_names
        raise ArgumentError, "unknown parameters: #{unknown.join(', ')}" unless unknown.empty?
      end
    end
  end
end
