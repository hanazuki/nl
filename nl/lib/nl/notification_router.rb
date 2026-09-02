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
      @closed = false
    end

    def register(endpoint, classes)
      @mutex.synchronize do
        raise ClosedError, 'notification router is closed' if @closed

        key = @protocol.family_key(endpoint)
        if entry = @entries[key]
          entry.classes.merge!(classes)
        else
          entry = Entry.new(endpoint, classes.dup, NotificationChannel.new(capacity: @capacity))
          @entries[key] = entry
        end
        entry.channel
      end
    end

    def channel(endpoint)
      @mutex.synchronize do
        @entries.fetch(@protocol.family_key(endpoint)).channel
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
        @entries[@protocol.frame_key(header)]
      end
      return false unless entry
      return false unless @protocol.notification_frame?(entry.endpoint, header, payload)

      message_class = @protocol.notification_class(entry.endpoint, header, payload, entry.classes)
      notification = if message_class
        @protocol.decode_notification(entry.endpoint, header, payload, message_class)
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
