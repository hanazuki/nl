require_relative 'attributes'

module Nl
  # A standalone nested attribute set. Messages share the same operations
  # without allocating this wrapper.
  class AttributeSet
    include Attributes

    Definition = Data.define(:id, :name, :datatype, :multi, :order, :selector_slot) do
      def initialize(id:, name:, datatype:, multi: false, order: 0, selector_slot: nil)
        super(id:, name:, datatype:, multi:, order:, selector_slot:)
      end
    end

    def initialize(attributes = [])
      @attributes = attributes
    end

    def encode(encoder, external_selectors: Selector::EMPTY_VALUES)
      encode_attributes(encoder, external_selectors:)
    end

    class << self
      def decode(decoder, definitions, local_selector_count, external_selectors)
        new(decode_attributes(decoder, definitions, local_selector_count, external_selectors:))
      end

      def build_instance(params, external_selectors: Selector::EMPTY_VALUES)
        new(build_attributes(params, external_selectors:))
      end
    end
  end
end
