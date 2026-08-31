# Generic Netlink connection handling
#--
# rbs_inline: enabled

require_relative '../connection'
require_relative '../core'
require_relative '../protocols/genl'

module Nl
  module Genl
    FamilyInfo = Data.define(:id, :multicast_groups) do
      def self.from_reply(reply)
        groups = (reply.mcast_groups || []).to_h do |attributes|
          [attributes[:name].value.to_sym, attributes[:id].value]
        end
        new(id: reply.family_id, multicast_groups: groups.freeze)
      end
    end

    class Connection
      #--
      # @rbs (resolver: ^(instance, ::String) -> (Integer | FamilyInfo | untyped), ?executor: executor?, ?notification_capacity: Integer?) -> instance
      #  | [R] (resolver: ^(instance, ::String) -> (Integer | FamilyInfo | untyped), ?executor: executor?, ?notification_capacity: Integer?) { (instance) -> R } -> R
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
      # @rbs resolver: ^(instance, ::String) -> (Integer | FamilyInfo | untyped)
      # @rbs executor: executor?
      # @rbs return: instance
      def initialize(resolver:, executor: nil, notification_capacity: Nl::Connection::DEFAULT_NOTIFICATION_CAPACITY)
        @resolver = resolver
        @family_cache = {}
        @family_cache_mutex = Mutex.new
        @connection = Nl::Connection.new(
          protocol: Protocols::Genl,
          executor:,
          notification_capacity:,
        )
      end

      def family(family_class)
        proto = family_class::PROTOCOL
        info = family_info(proto)
        family_class.new(
          @connection,
          protocol: Protocols::Genl.new(
            proto.name,
            family_id: info.id,
            multicast_groups: info.multicast_groups,
          ),
        )
      end

      def close
        @connection.close
      end

      private def family_info(protocol)
        id = protocol.family_id
        FamilyInfo.new(id:, multicast_groups: {}.freeze)
      rescue NotImplementedError
        cached_info = @family_cache_mutex.synchronize { @family_cache[protocol.name] }
        return cached_info if cached_info

        resolved = @resolver.call(self, protocol.name)
        info = case resolved
        when Integer
          FamilyInfo.new(id: resolved, multicast_groups: {}.freeze)
        when FamilyInfo
          resolved
        else
          FamilyInfo.from_reply(resolved)
        end
        @family_cache_mutex.synchronize { @family_cache[protocol.name] ||= info }
      end
    end
  end
end
