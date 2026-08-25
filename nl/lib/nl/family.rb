#--
# rbs_inline: enabled
require_relative 'async'
require_relative 'blocking_transport'
require_relative 'socket'

module Nl
  # @rbs!
  #   type executor = :thread | :fiber
  #
  #   interface _BlockingExchanger
  #     def exchange: (
  #       Protocols::Raw protocol,
  #       Symbol kind,
  #       Class request_class,
  #       Class reply_class,
  #       Hash[Symbol, untyped] args
  #     ) ?{ (untyped) -> void } -> untyped
  #     def async_capable?: () -> false
  #     def close: () -> nil
  #   end
  #
  #   interface _AsyncExchanger
  #     def exchange: (
  #       Protocols::Raw protocol,
  #       Symbol kind,
  #       Class request_class,
  #       Class reply_class,
  #       Hash[Symbol, untyped] args
  #     ) ?{ (untyped) -> void } -> untyped
  #     def exchange_async: (
  #       Protocols::Raw protocol,
  #       Symbol kind,
  #       Class request_class,
  #       Class reply_class,
  #       Hash[Symbol, untyped] args,
  #       ?stream_capacity: Integer?
  #     ) -> (Async::Future[untyped] | Async::Stream[untyped])
  #     def async_capable?: () -> true
  #     def close: () -> nil
  #   end
  #
  #   type exchanger = _BlockingExchanger | _AsyncExchanger

  class Family
    module Session
      def close #: nil
        @exchanger.close
      end
    end

    #--
    # @rbs exchanger: exchanger
    # @rbs protocol: Protocol
    # @rbs return: instance
    def initialize(exchanger, protocol: self.class::PROTOCOL)
      @protocol = protocol
      @exchanger = exchanger
    end

    #--
    # @rbs (?executor: executor?) -> (Session & instance)
    #  | [R] (?executor: executor?) { (instance) -> R } -> R
    def self.open(executor: nil)
      session = build_session(executor:)
      return session unless block_given?

      begin
        yield session
      ensure
        session.close
      end
    end

    class << self
      # @rbs (?executor: executor?) -> (Session & instance)
      private def build_session(executor: nil)
        socket = Socket.new(self::PROTOCOL.protonum)
        socket.bind(Socket.sockaddr_nl(0, 0))
        exchanger = if executor
          Async::Dispatcher.new(socket, executor:)
        else
          BlockingTransport.new(socket)
        end
        new(exchanger).extend(Session)
      rescue Exception
        exchanger ? exchanger.close : socket&.close
        raise
      end
    end

    private def exchange_message(kind, request_class, reply_class, args, &block)
      @exchanger.exchange(@protocol, kind, request_class, reply_class, args, &block)
    end

    def async_capable? #: bool
      @exchanger.async_capable?
    end

    # Builds a generated asynchronous-operation facade with a narrowly scoped
    # callback, so the facade does not need access to Family's private API.
    #--
    # @rbs operations_class: Class
    # @rbs stream_capacity: Integer?
    # @rbs return: untyped
    private def build_async_facade(operations_class, stream_capacity: nil)
      unless async_capable?
        raise Async::UnavailableError, 'async operations require an executor'
      end

      operations_class.new do |kind, request_class, reply_class, args|
        exchange_message_async(kind, request_class, reply_class, args, stream_capacity:)
      end
    end

    private def exchange_message_async(kind, request_class, reply_class, args, stream_capacity: nil)
      @exchanger.exchange_async(@protocol, kind, request_class, reply_class, args, stream_capacity:)
    end
  end
end
