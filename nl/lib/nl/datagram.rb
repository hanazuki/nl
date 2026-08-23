# rbs_inline: enabled

require_relative 'core'
require_relative 'decoder'

module Nl
  # Splits Netlink datagrams into aligned header/payload frames.
  module Datagram
    # @rbs (IO::Buffer buffer) { (Core::NlMsgHdr, IO::Buffer) -> void } -> nil
    #    | (IO::Buffer buffer) -> Enumerator[[Core::NlMsgHdr, IO::Buffer], nil]
    def self.each_frame(buffer)
      return enum_for(__method__, buffer) unless block_given?

      decoder = Decoder.new(buffer)
      while decoder.available?(Core::NLMSG_HDRLEN)
        header = Core::NlMsgHdr.decode(decoder)
        payload_size = header.len - Core::NLMSG_HDRLEN
        payload = decoder.get_buffer(payload_size)
        decoder.align_to(Core::NLMSG_ALIGNTO)
        yield header, payload
      end
    end
  end
end
