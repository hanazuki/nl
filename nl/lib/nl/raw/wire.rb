# Netlink wire definitions
#-

require_relative '../endian'

module Nl
  module Raw
    # Constants from <linux/netlink.h>
    module Constants
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

      NLA_F_NESTED = 1 << 15
      NLA_F_NET_BYTEORDER = 1 << 14
      NLA_TYPE_MASK = ~(NLA_F_NESTED | NLA_F_NET_BYTEORDER)

      NLA_ALIGNTO = 4
      NLA_HDRLEN = 4
    end
    include Constants

    # Fixed-format metadata header prepended to every Netlink message.
    #
    # This corresponds to Linux's +struct nlmsghdr+.
    #
    # @!attribute [rw] len
    #   @return [Integer] message length in bytes, including this header
    # @!attribute [rw] type
    #   @return [Integer] message content type
    # @!attribute [rw] flags
    #   @return [Integer] bitwise combination of +NLM_F_+ flags
    # @!attribute [rw] seq
    #   @return [Integer] sequence number used to correlate requests and replies
    # @!attribute [rw] pid
    #   @return [Integer] sender's Netlink port ID
    NlMsgHdr = Struct.new(
      :len, #: Integer
      :type, #: Integer
      :flags, #: Integer
      :seq, #: Integer
      :pid, #: Integer
    )

    class NlMsgHdr
      FORMAT = Ractor.make_shareable([
        Endian::Host::U32,
        Endian::Host::U16,
        Endian::Host::U16,
        Endian::Host::U32,
        Endian::Host::U32,
      ])
      private_constant :FORMAT

      # Decodes a header from the decoder's current position.
      #
      # @param [Decoder] decoder the source decoder
      # @return [NlMsgHdr] the decoded header
      # @rbs (Decoder decoder) -> instance
      def self.decode(decoder)
        obj = new(*decoder.get_values(FORMAT))
        decoder.align_to(Constants::NLMSG_ALIGNTO)
        obj
      end

      # Encodes this header at the encoder's current position.
      #
      # @param [Encoder] encoder the destination encoder
      # @return [void]
      # @rbs (Encoder encoder) -> void
      def encode(encoder)
        encoder.reserve(Constants::NLMSG_HDRLEN)
        encoder.put_values(FORMAT, to_a)
        encoder.align_to(Constants::NLMSG_ALIGNTO)
      end
    end

    # Fixed-format header prepended to every Netlink attribute.
    #
    # This corresponds to Linux's +struct nlattr+.
    #
    # @!attribute [rw] len
    #   @return [Integer] attribute length in bytes, including this header but
    #     excluding trailing alignment padding
    # @!attribute [rw] type
    #   @return [Integer] attribute type combined with optional +NLA_F_+ flags
    NlAttr = Struct.new(
      :len, #: Integer
      :type, #: Integer
    )

    class NlAttr
      FORMAT = Ractor.make_shareable([
        Endian::Host::U16,
        Endian::Host::U16,
      ])
      private_constant :FORMAT

      # Decodes an attribute header from the decoder's current position.
      #
      # @param [Decoder] decoder the source decoder
      # @return [NlAttr] the decoded header
      # @rbs (Decoder decoder) -> instance
      def self.decode(decoder)
        obj = new(*decoder.get_values(FORMAT))
        decoder.align_to(Constants::NLA_ALIGNTO)
        obj
      end

      # Encodes this attribute header at the encoder's current position.
      #
      # @param [Encoder] encoder the destination encoder
      # @return [void]
      # @rbs (Encoder encoder) -> void
      def encode(encoder)
        encoder.reserve(Constants::NLA_HDRLEN)
        encoder.put_values(FORMAT, to_a)
        encoder.align_to(Constants::NLA_ALIGNTO)
      end
    end
  end
end
