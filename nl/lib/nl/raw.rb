# rbs_inline: enabled

require_relative 'family'
require_relative 'raw/protocol'
require_relative 'raw/client'
require_relative 'attribute_set'
require_relative 'structured_payload'

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
      include Nl::StructuredPayload

      def initialize(fixed_header = nil, attributes = self.class::ATTRIBUTE_SET.new)
        super
      end

      def append_attribute(attribute)
        @attributes << attribute
      end

      def self.decode(decoder, type:)
        unless self::TYPE == type
          raise "Expected message type #{self::TYPE}, got #{type}"
        end

        super(decoder)
      end

      class << self
        private def attribute_names
          self::ATTRIBUTES
        end
      end
    end
  end
end
