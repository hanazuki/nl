# rbs_inline: enabled

require_relative 'async'
require_relative 'blocking_transport'
require_relative 'notification_router'
require_relative 'socket'

module Nl
  # Owns one Netlink socket and the facilities shared by families using it.
  class Connection
    DEFAULT_NOTIFICATION_CAPACITY = 1_024

    def initialize(protocol:, executor: nil, notification_capacity: DEFAULT_NOTIFICATION_CAPACITY)
      socket = Socket.new(protocol.protonum)
      socket.bind(Socket.sockaddr_nl(0, 0))
      notifications = NotificationRouter.new(
        routing: protocol.notification_routing,
        capacity: notification_capacity,
      )

      @socket = socket
      @notifications = notifications
      @transport = if executor
        Async::Dispatcher.new(socket, executor:, notifications:)
      else
        BlockingTransport.new(socket, notifications:)
      end
    rescue Exception
      @transport ? @transport.close : socket&.close
      notifications&.close
      raise
    end

    def exchange(...) = @transport.exchange(...)
    def exchange_async(...) = @transport.exchange_async(...)
    def async_capable? = @transport.async_capable?

    def register_notifications(protocol, classes)
      @notifications.register(protocol, classes)
    end

    def add_memberships(group_ids)
      group_ids.each { @socket.add_membership(it) }
      nil
    end

    def drop_memberships(group_ids)
      group_ids.each { @socket.drop_membership(it) }
      nil
    end

    def receive_notification(protocol, timeout: nil)
      @transport.receive_notification(protocol, timeout:)
    end

    def close
      @transport.close
      nil
    ensure
      @notifications.close
    end
  end
end
