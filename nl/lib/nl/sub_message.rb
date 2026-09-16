require_relative 'structured_payload'

module Nl
  module Selector
    EMPTY_VALUES = Ractor.make_shareable([])

    class MissingSelectorValueError < StandardError
      attr_reader :scope, :index

      def initialize(scope, index)
        @scope = scope
        @index = index
        super()
      end
    end

    class UnknownSelectorValueError < StandardError
      attr_reader :value

      def initialize(value)
        @value = value
        super()
      end
    end

    module Reference
      def select(context, formats)
        value = read(context)
        formats.fetch(value) do
          return yield(value) if block_given?
          raise UnknownSelectorValueError.new(value)
        end
      end
    end

    Local = Data.define(:index) do
      include Reference

      def read(context)
        context.fetch_local(index)
      end
    end

    External = Data.define(:index) do
      include Reference

      def read(context)
        context.fetch_external(index)
      end
    end

    class State
      def self.for(local_count, external)
        return EMPTY if local_count.zero? && external.empty?

        new(local_count, external)
      end

      def initialize(local_count, external)
        @local = Array.new(local_count)
        @external = external
      end

      def set_local(index, value)
        @local[index] = value
      end

      def fetch_local(index)
        fetch(@local, index) { raise MissingSelectorValueError.new(:local, index) }
      end

      def fetch_external(index)
        fetch(@external, index) { raise MissingSelectorValueError.new(:external, index) }
      end

      def fetch(values, key)
        value = values[key]
        value.nil? ? yield : value
      end

      EMPTY = Ractor.make_shareable(new(0, EMPTY_VALUES))
    end
  end

  # A selector-specific payload containing an optional fixed header followed by
  # an optional set of Netlink attributes.
  class SubMessage
    include StructuredPayload
  end

  # An unrecognized selector-specific payload retained without interpretation.
  class RawSubMessage < SubMessage
    attr_reader :payload, :nlattr_type_flags

    def initialize(payload, nlattr_type_flags:)
      @payload = payload
      @nlattr_type_flags = nlattr_type_flags
    end

    def encode(encoder, external_selectors: Selector::EMPTY_VALUES)
      encoder.put_string(payload)
    end
  end
end
