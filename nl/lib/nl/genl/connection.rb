# Generic Netlink connection handling
#--
# rbs_inline: enabled

require_relative '../async'
require_relative '../blocking_transport'
require_relative '../core'
require_relative '../protocols/genl'
require_relative '../socket'

module Nl
  module Genl
    class Connection
      #--
      # @rbs (resolver: ^(instance, ::String) -> ::Integer, ?executor: executor?) -> instance
      #  | [R] (resolver: ^(instance, ::String) -> ::Integer, ?executor: executor?) { (instance) -> R } -> R
      def self.open(resolver:, executor: nil)
        conn = new(resolver:, executor:)
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
      # @rbs resolver: ^(instance, ::String) -> ::Integer
      # @rbs executor: executor?
      # @rbs return: instance
      def initialize(resolver:, executor: nil)
        socket = Socket.new(Core::NETLINK_GENERIC)
        socket.bind(Socket.sockaddr_nl(0, 0))
        @resolver = resolver
        @id_cache = {}
        @id_cache_mutex = Mutex.new
        @exchanger = if executor
          Async::Dispatcher.new(socket, executor:)
        else
          BlockingTransport.new(socket)
        end
      end

      def family(family_class)
        proto = family_class::PROTOCOL
        id = family_id(proto)
        family_class.new(
          @exchanger,
          protocol: Protocols::Genl.new(proto.name, family_id: id),
        )
      end

      def close
        @exchanger.close
      end

      private def family_id(protocol)
        protocol.family_id
      rescue NotImplementedError
        cached_id = @id_cache_mutex.synchronize { @id_cache[protocol.name] }
        return cached_id if cached_id

        resolved_id = @resolver.call(self, protocol.name)
        @id_cache_mutex.synchronize { @id_cache[protocol.name] ||= resolved_id }
      end
    end
  end
end
