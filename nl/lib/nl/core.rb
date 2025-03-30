# Data types and message handling

require_relative 'endian'

module Nl
  module Core
    module Constants
      # From include/uapi/linux/netlink.h
      NETLINK_ROUTE = 0
      NETLINK_NETFILTER = 12
      NETLINK_GENERIC = 16

      NLM_F_REQUEST = 1
      NLM_F_MULTI = 2
      NLM_F_ACK = 4
      NLM_F_ECHO = 8
      NLM_F_DUMP_INTR = 16
      NLM_F_DUMP_FILTERED = 32
      NLM_F_ROOT = 0x100
      NLM_F_MATCH = 0x200
      NLM_F_ATOMIC = 0x400
      NLM_F_DUMP = NLM_F_ROOT | NLM_F_MATCH
      NLM_F_REPLACE = 0x100
      NLM_F_EXCL = 0x200
      NLM_F_CREATE = 0x400
      NLM_F_APPEND = 0x800

      NLMSG_ALIGNTO = 4
      NLMSG_HDRLEN = 16

      NLMSG_NOOP = 0x1
      NLMSG_ERROR = 0x2
      NLMSG_DONE = 0x3
      NLMSG_OVERRUN = 0x4

      NLMSG_MIN_TYPE = 0x10

      NLA_ALIGNTO = 4
      NLA_HDRLEN = 4
    end
    include Constants

    NlMsgHdr = Struct.new(:len, :type, :flags, :seq, :pid)
    # Message header
    class NlMsgHdr
      FORMAT = Ractor.make_shareable([
        Endian::Host::U32,
        Endian::Host::U16,
        Endian::Host::U16,
        Endian::Host::U32,
        Endian::Host::U32,
      ])
      private_constant :FORMAT

      def self.decode(decoder)
        obj = new(*decoder.get_values(FORMAT))
        decoder.align_to(Constants::NLMSG_ALIGNTO)
        obj
      end

      def encode(encoder)
        encoder.reserve(Constants::NLMSG_HDRLEN)
        encoder.put_values(FORMAT, to_a)
        encoder.align_to(Constants::NLMSG_ALIGNTO)
      end
    end

    NlAttr = Struct.new(:len, :type)
    # Attribute header
    class NlAttr
      FORMAT = Ractor.make_shareable([
        Endian::Host::U16,
        Endian::Host::U16,
      ])
      private_constant :FORMAT

      def self.decode(decoder)
        obj = new(*decoder.get_values(FORMAT))
        decoder.align_to(Constants::NLA_ALIGNTO)
        obj
      end

      def encode(encoder)
        encoder.reserve(Constants::NLA_HDRLEN)
        encoder.put_values(FORMAT, to_a)
        encoder.align_to(Constants::NLA_ALIGNTO)
      end
    end
  end
end
