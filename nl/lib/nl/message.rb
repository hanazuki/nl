require_relative 'attribute_set'
require_relative 'structured_payload'

module Nl
  # Base class for family-specific Netlink message payloads.
  #
  # A message may contain a fixed header followed by a set of Netlink
  # attributes.
  class Message
    include StructuredPayload

    # @param [Object, nil] fixed_header the family-specific fixed header
    # @param [AttributeSet, nil] attributes the message's attributes
    # @rbs (?untyped fixed_header, ?AttributeSet? attributes) -> void
    def initialize(fixed_header = nil, attributes = self.class::ATTRIBUTE_SET.new)
      super
    end

    # Appends an attribute value, identified by name or wire type.
    #
    # @rbs (Symbol | Integer type, untyped value) -> void
    def append_attribute(type, value)
      @attributes.append(type, value)
    end

    class << self
      # Returns the attribute names accepted by this message.
      #
      # @return [Array<Symbol>] the attribute names
      # @rbs () -> Array[Symbol]
      private def attribute_names
        self::ATTRIBUTES
      end
    end
  end
end
