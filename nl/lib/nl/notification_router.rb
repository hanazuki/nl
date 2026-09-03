require_relative 'raw/wire'
require_relative 'notification'

module Nl
  # Routes unsolicited frames to per-family notification channels.
  class NotificationRouter
    Entry = Struct.new(:endpoint, :classes, :channel)
    private_constant :Entry

    def initialize(protocol:, capacity:)
      @protocol = protocol
      @capacity = capacity
      @mutex = Mutex.new
      @entries = {}
      @routes = {}
      @closed = false
    end

    def register(endpoint, classes)
      @mutex.synchronize do
        raise ClosedError, 'notification router is closed' if @closed

        channel_key = @protocol.notification_channel_key(endpoint)
        entry = @entries[channel_key]
        merged_classes = entry ? entry.classes.merge(classes) : classes.dup
        route_keys = @protocol.notification_route_keys(endpoint, merged_classes)
        if route_key = route_keys.find { @routes[it] && !@routes[it].equal?(entry) }
          raise ArgumentError, "notification route #{route_key.inspect} is already registered"
        end

        unless entry
          entry = Entry.new(endpoint, merged_classes, NotificationChannel.new(capacity: @capacity))
          @entries[channel_key] = entry
        end
        entry.classes.replace(merged_classes)
        route_keys.each { @routes[it] = entry }
        entry.channel
      end
    end

    def channel(endpoint)
      @mutex.synchronize do
        @entries.fetch(@protocol.notification_channel_key(endpoint)).channel
      end
    end

    # Returns true if the frame belongs to a registered notification family.
    def route(header, payload)
      if header.type == Raw::NLMSG_OVERRUN
        entries = @mutex.synchronize { @entries.values.dup }
        entries.each { it.channel.fail(NotificationLossError.new('kernel reported Netlink overrun')) }
        return true
      end

      entry = @mutex.synchronize do
        @routes[@protocol.notification_frame_key(header)]
      end
      return false unless entry
      return false unless @protocol.notification_frame?(entry.endpoint, header, payload)

      message_class = @protocol.notification_class(entry.endpoint, header, payload, entry.classes)
      return true unless message_class

      notification = @protocol.decode_notification(entry.endpoint, header, payload, message_class)
      entry.channel.push(notification)
      true
    rescue => error
      entry&.channel&.fail(error)
      true
    end

    def close
      entries = @mutex.synchronize do
        return nil if @closed

        @closed = true
        old = @entries.values
        @entries.clear
        @routes.clear
        old
      end
      entries.each { it.channel.close }
      nil
    end

    def lose_all(error)
      entries = @mutex.synchronize { @entries.values.dup }
      entries.each { it.channel.fail(error) }
      nil
    end
  end
end
