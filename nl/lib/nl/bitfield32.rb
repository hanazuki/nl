# rbs_inline: enabled

module Nl
  # A 32-bit value paired with a mask selecting the meaningful bits.
  class Bitfield32
    UINT32_RANGE = (0...2**32)

    attr_reader :value #: Integer
    attr_reader :selector #: Integer

    # @rbs (Integer value, Integer selector) -> void
    def initialize(value, selector)
      validate_uint32(value, :value)
      validate_uint32(selector, :selector)
      if value & ~selector != 0
        raise ArgumentError, 'value contains bits which are not selected'
      end

      @value = value
      @selector = selector
    end

    # Returns 1 or 0 for a selected bit, or nil for an unselected bit.
    # @rbs (Integer index) -> (0 | 1 | nil)
    def [](index)
      mask = bit_mask(index)
      return nil if selector & mask == 0

      value & mask == 0 ? 0 : 1
    end

    # Selects and sets or clears a bit. Assigning nil unselects it.
    # @rbs (Integer index, (0 | 1 | nil) state) -> (0 | 1 | nil)
    def []=(index, state)
      mask = bit_mask(index)
      case state
      when 1
        @selector |= mask
        @value |= mask
      when 0
        @selector |= mask
        @value &= ~mask
      when nil
        @selector &= ~mask
        @value &= ~mask
      else
        raise TypeError, 'bit state must be 0, 1, or nil'
      end

      state
    end

    # @rbs (Integer index) -> Integer
    private def bit_mask(index)
      unless index.is_a?(Integer)
        raise TypeError, 'bit index must be an Integer'
      end
      unless (0...32).cover?(index)
        raise RangeError, "bit index #{index.inspect} is outside the 0...32 range"
      end

      1 << index
    end

    # @rbs (Integer integer, Symbol name) -> void
    private def validate_uint32(integer, name)
      unless integer.is_a?(Integer)
        raise TypeError, "#{name} must be an Integer"
      end
      unless UINT32_RANGE.cover?(integer)
        raise RangeError, "#{name} #{integer.inspect} is outside the #{UINT32_RANGE} range"
      end
    end
  end
end
