# Generic Netlink client handling
#-

require_relative '../connection'
require_relative 'wire'

module Nl
  module Genl
    # Dynamically resolved information for a generic Netlink family.
    #
    # @!attribute [r] id
    #   @return [Integer] the assigned family ID
    # @!attribute [r] multicast_groups
    #   @return [Hash<String, Integer>] multicast group names mapped to their IDs
    FamilyInfo = Data.define(
      :id, #: Integer
      :multicast_groups, #: Hash[String, Integer]
    )

    # Owns one generic Netlink connection shared by compatible families.
    class Client
      # Opens a generic Netlink client.
      #
      # @overload open(resolver:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY)
      #   The caller is responsible for closing the client.
      #   @param [#call] resolver a callable that resolves a family name to {FamilyInfo}
      #   @param [:thread, :fiber, nil] executor the asynchronous executor, or `nil` for blocking operation
      #   @param [Integer] notification_capacity the maximum number of queued notifications
      #   @return [Client] the opened client
      # @overload open(resolver:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY, &block)
      #   The client is automatically closed after the block returns.
      #   @param [#call] resolver a callable that resolves a family name to {FamilyInfo}
      #   @param [:thread, :fiber, nil] executor the asynchronous executor, or `nil` for blocking operation
      #   @param [Integer] notification_capacity the maximum number of queued notifications
      #   @yieldparam [Client] client the opened client
      #   @return [Object] the value returned from the block
      # @rbs (resolver: ^(instance, ::String) -> FamilyInfo, ?executor: executor?, ?notification_capacity: Integer?) -> instance
      #    | [R] (resolver: ^(instance, ::String) -> FamilyInfo, ?executor: executor?, ?notification_capacity: Integer?) { (instance) -> R } -> R
      def self.open(resolver:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY)
        client = new(resolver:, executor:, notification_capacity:)
        return client unless block_given?

        begin
          yield client
        ensure
          client.close
        end
      end

      # @param [#call] resolver a callable that resolves a family name to {FamilyInfo}
      # @param [:thread, :fiber, nil] executor the asynchronous executor, or `nil` for blocking operation
      # @param [Integer] notification_capacity the maximum number of queued notifications
      # @rbs (resolver: ^(instance, ::String) -> FamilyInfo, ?executor: executor?, ?notification_capacity: Integer?) -> void
      def initialize(resolver:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY)
        @resolver = resolver
        @family_cache = {}
        @family_cache_mutex = Mutex.new
        @connection = Nl::Connection.new(
          protocol: Protocol.new,
          executor:,
          notification_capacity:,
        )
      end

      # Builds a family backed by this client's connection.
      #
      # @param [Class<Family>] family_class a generic Netlink family class
      # @return [Family] an instance of `family_class`
      # @raise [TypeError] if +family_class+ does not inherit from {Family}
      # @rbs [F < Family] (_FamilyClass[F] family_class) -> F
      def family(family_class)
        unless family_class <= Family
          raise TypeError, "family class must inherit from #{Family}"
        end

        info = family_info(family_class::NAME)
        family_class.new(
          @connection,
          endpoint: Endpoint.new(family_class, info),
        )
      end

      # Closes the underlying Netlink connection.
      #
      # @return [void]
      # @rbs () -> void
      def close
        @connection.close
      end

      # Resolves and caches information for a family by name.
      #
      # @param [String] name the generic Netlink family name
      # @return [FamilyInfo] the resolved family information
      # @rbs (String name) -> FamilyInfo
      private def family_info(name)
        cached_info = @family_cache_mutex.synchronize { @family_cache[name] }
        return cached_info if cached_info

        info = @resolver.call(self, name)
        @family_cache_mutex.synchronize { @family_cache[name] ||= info }
      end
    end
  end
end
