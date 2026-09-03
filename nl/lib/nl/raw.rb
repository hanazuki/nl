require_relative 'family'
require_relative 'raw/protocol'
require_relative 'raw/client'
require_relative 'attribute_set'

module Nl
  module Raw
    class Family < Nl::Family
      #--
      # @rbs (?executor: executor?, ?notification_capacity: Integer?) -> (Nl::Family::Session & instance)
      #  | [R] (?executor: executor?, ?notification_capacity: Integer?) { (instance) -> R } -> R
      def self.open(executor: nil, notification_capacity: DEFAULT_NOTIFICATION_CAPACITY)
        session = build_session(executor:, notification_capacity:)
        return session unless block_given?

        begin
          yield session
        ensure
          session.close
        end
      end

      class << self
        #--
        # @rbs (executor: executor?, notification_capacity: Integer) -> (Nl::Family::Session & instance)
        private def build_session(executor:, notification_capacity:)
          owner = Client.new(protonum: self::PROTONUM, executor:, notification_capacity:)
          owner.family(self).extend(Nl::Family::Session)
        rescue Exception
          owner&.close
          raise
        end
      end
    end

    class Message
      attr_accessor :fixed_header, :attributes

      def initialize(fixed_header = nil, attributes = self.class::ATTRIBUTE_SET.new)
        @fixed_header = fixed_header
        @attributes = attributes
      end

      def self.from_params(params)
        if self::FIXED_HEADER
          header_params = params.slice(*self::FIXED_HEADER.members)
          fixed_header = self::FIXED_HEADER.new(**header_params)
        end
        attribute_params = params.slice(*self::ATTRIBUTES)
        attributes = self::ATTRIBUTE_SET.build_attributes(**attribute_params)

        unknown = params.keys - attribute_params.keys
        unknown -= header_params.keys if header_params
        unless unknown.empty?
          raise ArgumentError, "unknown parameters: #{unknown.join(', ')}"
        end

        new(fixed_header, attributes)
      end

      def append_attribute(attribute)
        @attributes << attribute
      end

      def encode(encoder)
        @fixed_header&.encode(encoder)
        @attributes.encode(encoder)
      end

      def self.decode(decoder, type:)
        unless self::TYPE == type
          raise "Expected message type #{self::TYPE}, got #{type}"
        end

        if fixed_header_class = self::FIXED_HEADER
          fixed_header = fixed_header_class.decode(decoder)
        end

        attributes = self::ATTRIBUTE_SET.decode(decoder)

        new(fixed_header, attributes)
      end
    end
  end
end
