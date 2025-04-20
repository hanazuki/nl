# Netlink sockets

require 'socket'

module Nl
  # Netlink socket
  class Socket < ::Socket
    module Constants
      # From include/linux/socket.h
      PF_NETLINK = AF_NETLINK = 16
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
      @seq = 0  # last-used sequence number
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

    # XXX: Should Protocol manage next_seq?

    # @return [Integer] Get next sequence number
    def next_seq
      nseq = (@seq + 1) & 0xFFFFFFFF
      nseq = 1 if nseq == 0  # seq=0 is for notification
      @seq = nseq
    end

    def complete(hdr)
      [
        hdr.seq ||= next_seq,
        hdr.pid ||= Socket.unpack_sockaddr_nl(local_address.to_sockaddr).first,
      ]
    end
  end
end
