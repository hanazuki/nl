# Raw Netlink client handling
#--
# rbs_inline: enabled

require_relative '../connection'
require_relative 'protocol'

module Nl
  module Raw
    # Owns one raw Netlink connection shared by compatible generated families.
    class Client
      #--
      # @rbs (protonum: Integer, ?executor: executor?, ?notification_capacity: Integer?) -> instance
      #  | [R] (protonum: Integer, ?executor: executor?, ?notification_capacity: Integer?) { (instance) -> R } -> R
      def self.open(protonum:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY)
        client = new(protonum:, executor:, notification_capacity:)
        return client unless block_given?

        begin
          yield client
        ensure
          client.close
        end
      end

      #--
      # @rbs protonum: Integer
      # @rbs executor: executor?
      # @rbs return: instance
      def initialize(protonum:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY)
        @protonum = protonum
        @connection = Nl::Connection.new(
          protocol: Protocol.new(protonum),
          executor:,
          notification_capacity:,
        )
      end

      # @rbs [F < Family] (_FamilyClass[F] family_class) -> F
      def family(family_class)
        unless family_class <= Family
          raise TypeError, "family class must inherit from #{Family}"
        end
        unless family_class::PROTONUM == @protonum
          raise ArgumentError,
            "family protonum #{family_class::PROTONUM} does not match client protonum #{@protonum}"
        end

        family_class.new(
          @connection,
          endpoint: Endpoint.new(family_class),
        )
      end

      def close
        @connection.close
      end
    end
  end
end
