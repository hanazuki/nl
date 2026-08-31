# Netlink sockets

require 'socket'

module Nl
  # Netlink socket
  class Socket < ::Socket
    module Constants
      # From include/linux/socket.h
      PF_NETLINK = AF_NETLINK = 16

      # From include/uapi/linux/netlink.h
      SOL_NETLINK = 270
      NETLINK_ADD_MEMBERSHIP = 1
      NETLINK_DROP_MEMBERSHIP = 2
    end
    include Constants

    class << self
      def pack_sockaddr_nl(pid, groups) = [Socket::AF_NETLINK, 0, pid, groups].pack('S!S!LL')
      alias sockaddr_nl pack_sockaddr_nl

      def unpack_sockaddr_nl(sockaddr) = sockaddr.unpack('S!S!LL')[2..3]
    end

    # @param protonum [Integer] Netlink protocol number
    def initialize(protonum)
      super(PF_NETLINK, SOCK_RAW, protonum)
    end

    def self.open(protonum)
      return new(protonum) unless block_given?
      begin
        socket = new(protonum)
        yield socket
      ensure
        socket&.close
      end
    end

    # @return [Integer] Local Netlink port ID assigned to this socket
    def local_port_id
      Socket.unpack_sockaddr_nl(local_address.to_sockaddr).first
    end

    # Adds this socket to a Netlink multicast group.
    def add_membership(group_id)
      setsockopt(SOL_NETLINK, NETLINK_ADD_MEMBERSHIP, group_id)
    end

    # Removes this socket from a Netlink multicast group.
    def drop_membership(group_id)
      setsockopt(SOL_NETLINK, NETLINK_DROP_MEMBERSHIP, group_id)
    end
  end
end
