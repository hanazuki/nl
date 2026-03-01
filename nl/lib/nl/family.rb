#--
# rbs_inline: enabled
require_relative 'socket'

module Nl
  class Family
    #--
    # @rbs socket: Socket
    # @rbs protocol: Protocol
    # @rbs return: instance
    def initialize(socket, protocol: self.class::PROTOCOL)
      @socket = socket
      @protocol = protocol
    end

    #--
    # @rbs () -> instance
    #  | [R] () { (instance) -> R } -> R
    def self.open
      begin
        socket = Socket.new(self::PROTOCOL.protonum)
        socket.bind(Socket.sockaddr_nl(0, 0))
        if block_given?
          yield new(socket)
        else
          return new(socket)
        end
      ensure
        socket&.close if block_given?
      end
    end

    private def exchange_message(type, request_class, reply_class, args, &block)
      @protocol.exchange_message(@socket, type, request_class, reply_class, args, &block)
    end
  end
end
