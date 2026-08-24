# rbs_inline: enabled

require_relative 'error'

module Nl
  # Allocates nonzero 32-bit Netlink sequence numbers.
  class SequenceAllocator
    MAX = 0xFFFFFFFF
    private_constant :MAX

    def initialize
      @last = 0
    end

    # Returns the next sequence number not rejected by the optional block.
    def next
      first = advance
      candidate = first

      loop do
        return candidate unless block_given? && yield(candidate)

        candidate = advance
        if candidate == first
          raise ExhaustedSequenceNumber, 'all Netlink sequence numbers are in use'
        end
      end
    end

    private def advance
      @last = @last == MAX ? 1 : @last + 1
    end
  end

  private_constant :SequenceAllocator
end
