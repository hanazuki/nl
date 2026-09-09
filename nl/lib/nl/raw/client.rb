# Raw Netlink client handling
#-

require_relative '../connection'
require_relative 'protocol'

module Nl
  module Raw
    # Owns one raw Netlink connection shared by compatible families.
    class Client
      # Opens a client for a raw Netlink protocol.
      #
      # @overload open(protonum:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY)
      #   The caller is responsible for closing the client.
      #   @param [Integer] protonum the Netlink protocol number
      #   @param [:thread, :fiber, nil] executor the asynchronous executor, or `nil` for blocking operation
      #   @param [Integer] notification_capacity the maximum number of queued notifications
      #   @return [Client] the opened client
      # @overload open(protonum:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY, &block)
      #   The client is automatically closed after the block returns.
      #   @param [Integer] protonum the Netlink protocol number
      #   @param [:thread, :fiber, nil] executor the asynchronous executor, or `nil` for blocking operation
      #   @param [Integer] notification_capacity the maximum number of queued notifications
      #   @yieldparam [Client] client the opened client
      #   @return [Object] the value returned from the block
      # @rbs (protonum: Integer, ?executor: executor?, ?notification_capacity: Integer?) -> instance
      #    | [R] (protonum: Integer, ?executor: executor?, ?notification_capacity: Integer?) { (instance) -> R } -> R
      def self.open(protonum:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY)
        client = new(protonum:, executor:, notification_capacity:)
        return client unless block_given?

        begin
          yield client
        ensure
          client.close
        end
      end

      # @param [Integer] protonum the Netlink protocol number
      # @param [:thread, :fiber, nil] executor the asynchronous executor, or `nil` for blocking operation
      # @param [Integer] notification_capacity the maximum number of queued notifications
      # @rbs (protonum: Integer, ?executor: executor?, ?notification_capacity: Integer?) -> void
      def initialize(protonum:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY)
        @protonum = protonum
        @connection = Nl::Connection.new(
          protocol: Protocol.new(protonum),
          executor:,
          notification_capacity:,
        )
      end

      # Builds a family backed by this client's connection.
      #
      # @param [Class<Family>] family_class a raw Netlink family class
      # @return [Family] an instance of `family_class`
      # @raise [TypeError] if +family_class+ does not inherit from {Family}
      # @raise [ArgumentError] if the family's protocol number differs from the client's protocol number
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

      # Closes the underlying Netlink connection.
      #
      # @return [void]
      # @rbs () -> void
      def close
        @connection.close
      end
    end
  end
end
