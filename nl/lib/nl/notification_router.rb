require_relative 'core'
require_relative 'notification'

module Nl
  # Routes unsolicited frames to per-family notification channels.
  class NotificationRouter
    Entry = Struct.new(:protocol, :classes, :channel)
    private_constant :Entry

    def initialize(routing:, capacity:)
      @routing = routing
      @capacity = capacity
      @mutex = Mutex.new
      @entries = {}
      @closed = false
    end

    def register(protocol, classes)
      @mutex.synchronize do
        raise ClosedError, 'notification router is closed' if @closed

        key = @routing.family_key(protocol)
        if entry = @entries[key]
          entry.classes.merge!(classes)
        else
          entry = Entry.new(protocol, classes.dup, NotificationChannel.new(capacity: @capacity))
          @entries[key] = entry
        end
        entry.channel
      end
    end

    def channel(protocol)
      @mutex.synchronize do
        @entries.fetch(@routing.family_key(protocol)).channel
      end
    end

    # Returns true if the frame belongs to a registered notification family.
    def route(header, payload)
      if header.type == Core::NLMSG_OVERRUN
        entries = @mutex.synchronize { @entries.values.dup }
        entries.each { it.channel.fail(NotificationLossError.new('kernel reported Netlink overrun')) }
        return true
      end

      entry = @mutex.synchronize do
        @entries[@routing.frame_key(header)]
      end
      return false unless entry
      return false unless entry.protocol.notification_frame?(header, payload)

      message_class = entry.protocol.notification_class(header, payload, entry.classes)
      notification = if message_class
        entry.protocol.decode_notification(header, payload, message_class)
      else
        UnknownNotification.new(header:, payload: payload.get_string)
      end
      entry.channel.push(notification)
      true
    rescue Exception => error
      entry&.channel&.fail(error)
      true
    end

    def close
      entries = @mutex.synchronize do
        return nil if @closed

        @closed = true
        old = @entries.values
        @entries.clear
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
