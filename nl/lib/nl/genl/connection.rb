# Generic Netlink connection handling
#--
# rbs_inline: enabled

require_relative '../connection'
require_relative 'wire'

module Nl
  module Genl
    FamilyInfo = Data.define(
      :id, #: Integer
      :multicast_groups, #: Hash[String, Integer]
    )

    class Connection
      #--
      # @rbs (resolver: ^(instance, ::String) -> FamilyInfo, ?executor: executor?, ?notification_capacity: Integer?) -> instance
      #  | [R] (resolver: ^(instance, ::String) -> FamilyInfo, ?executor: executor?, ?notification_capacity: Integer?) { (instance) -> R } -> R
      def self.open(resolver:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY)
        conn = new(resolver:, executor:, notification_capacity:)
        if block_given?
          begin
            yield conn
          ensure
            conn.close
          end
        else
          conn
        end
      end

      #--
      # @rbs resolver: ^(instance, ::String) -> FamilyInfo
      # @rbs executor: executor?
      # @rbs return: instance
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

      def close
        @connection.close
      end

      private def family_info(name)
        cached_info = @family_cache_mutex.synchronize { @family_cache[name] }
        return cached_info if cached_info

        info = @resolver.call(self, name)
        @family_cache_mutex.synchronize { @family_cache[name] ||= info }
      end
    end
  end
end
