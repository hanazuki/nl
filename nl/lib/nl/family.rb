require_relative 'connection'
require_relative 'notification'

module Nl
  # @rbs!
  #   type executor = :thread | :fiber
  #
  #   interface _Connection
  #     def exchange: (
  #       Raw::Endpoint endpoint,
  #       Symbol kind,
  #       Class request_class,
  #       Class reply_class,
  #       Hash[Symbol, untyped] args
  #     ) ?{ (untyped) -> void } -> untyped
  #     def exchange_async: (
  #       Raw::Endpoint endpoint,
  #       Symbol kind,
  #       Class request_class,
  #       Class reply_class,
  #       Hash[Symbol, untyped] args,
  #       ?stream_capacity: Integer?
  #     ) -> (Async::Future[untyped] | Async::Stream[untyped])
  #     def async_capable?: () -> bool
  #     def register_notifications: (Raw::Endpoint, Hash[Integer, Class]) -> NotificationChannel
  #     def add_memberships: (Array[Integer]) -> nil
  #     def drop_memberships: (Array[Integer]) -> nil
  #     def receive_notification: (Raw::Endpoint, ?timeout: Numeric?) -> untyped
  #     def close: () -> nil
  #   end
  #
  #   interface _FamilyClass[out F]
  #     def new: (_Connection, endpoint: Raw::Endpoint) -> F
  #   end

  class Family
    DEFAULT_NOTIFICATION_CAPACITY = Connection::DEFAULT_NOTIFICATION_CAPACITY #: Integer

    # Socket-owning family.
    #
    # {Family} instances that owns sockets are extended with this module.
    module Session
      # Closes the Netlink socket owned by this {Family}.
      # @rbs () -> void
      def close
        @connection.close
      end
    end

    # @rbs (_Connection connection, endpoint: Raw::Endpoint) -> instance
    def initialize(connection, endpoint:)
      @endpoint = endpoint
      @connection = connection
      @connection.register_notifications(@endpoint, notification_classes)
      @notification_stream = NotificationStream.new do |timeout|
        @connection.receive_notification(@endpoint, timeout:)
      end
    end

    private def exchange_message(kind, request_class, reply_class, args, &block)
      @connection.exchange(@endpoint, kind, request_class, reply_class, args, &block)
    end

    # Returns if this family supports asynchronous operations.
    #
    # @rbs () -> bool
    def async_capable?
      @connection.async_capable?
    end

    # Adds multicast memberships to the netlink socket.
    #
    # Membership is additive and remains active until explicitly removed or the owner closes.
    #
    # @param [Array<Symbol>] groups
    # @return [Family] self
    # @rbs (Symbol *groups) -> self
    def subscribe(*groups)
      @connection.add_memberships(multicast_group_ids(groups))
      self
    end

    # Removes multicast memberships from the netlink socket.
    #
    # @param [Array<Symbol>] groups
    # @return [Family] self
    # @rbs (Symbol *groups) -> self
    def unsubscribe(*groups)
      @connection.drop_memberships(multicast_group_ids(groups))
      self
    end

    # Receives the next unsolicited message.
    #
    # @rbs (?timeout: Integer?) -> Message
    def receive_notification(timeout: nil)
      @notification_stream.next(timeout:)
    end

    # Receives unsolicited messages.
    #
    # @rbs () { (Message) -> void } -> void
    def each_notification(&block)
      return @notification_stream.each unless block

      @notification_stream.each(&block)
    end

    # Builds a asynchronous-operation facade.
    #
    # @rbs (Class operations_class, ?stream_capacity: Integer?) -> untyped
    private def build_async_facade(operations_class, stream_capacity: nil)
      unless async_capable?
        raise Async::UnavailableError, 'async operations require an executor'
      end

      operations_class.new do |kind, request_class, reply_class, args|
        exchange_message_async(kind, request_class, reply_class, args, stream_capacity:)
      end
    end

    private def exchange_message_async(kind, request_class, reply_class, args, stream_capacity: nil)
      @connection.exchange_async(@endpoint, kind, request_class, reply_class, args, stream_capacity:)
    end

    private def notification_classes
      self.class.const_get(:NOTIFICATIONS, false)
    rescue NameError
      {}
    end

    private def multicast_groups
      self.class.const_get(:MCAST_GROUPS, false)
    rescue NameError
      {}
    end

    private def multicast_group_ids(names)
      names.map do |name|
        key = name.to_sym
        group = multicast_groups.fetch(key) do
          raise UnknownMulticastGroupError, "unknown multicast group #{name.inspect} for #{@endpoint.name}"
        end
        @endpoint.multicast_group_id(group.name, group.id)
      end
    end
  end

end
