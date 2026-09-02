# rbs_inline: enabled

require_relative 'raw/wire'
require_relative 'decoder'

module Nl
  # Splits Netlink datagrams into aligned header/payload frames.
  module Datagram
    # @rbs (IO::Buffer buffer) { (Raw::NlMsgHdr, IO::Buffer) -> void } -> nil
    #    | (IO::Buffer buffer) -> Enumerator[[Raw::NlMsgHdr, IO::Buffer], nil]
    def self.each_frame(buffer)
      return enum_for(__method__, buffer) unless block_given?

      decoder = Decoder.new(buffer)
      while decoder.available?(Raw::NLMSG_HDRLEN)
        header = Raw::NlMsgHdr.decode(decoder)
        payload_size = header.len - Raw::NLMSG_HDRLEN
        payload = decoder.get_buffer(payload_size)
        decoder.align_to(Raw::NLMSG_ALIGNTO)
        yield header, payload
      end
    end
  end
end
