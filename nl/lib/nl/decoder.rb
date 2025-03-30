module Nl
  class Decoder
    class Error < StandardError; end
    class OutOfBounds < Error
      def initialize(message = 'out of bounds') = super
    end
    class Unterminated < Error
      def initialize(message = 'unterminated string') = super
    end

    def initialize(buffer, offset = 0, length = buffer.size - offset)
      @buffer = buffer
      @position = offset
      @limit = length
    end

    def available?(size = 1)
      @position + size <= @limit
    end

    def limit(size)
      orig_limit = @limit
      @limit = @position + size
      result = yield self
      if @limit != @position
        raise "Not all bytes upto specified limit is consumed"
      end
      result
    ensure
      @limit = orig_limit
    end

    def skip(length = @limit - @position)
      nposition = @position + length
      raise OutOfBounds if nposition > @limit
      @position = nposition
    end

    def get_string(length = @limit - @position)
      nposition = @position + length
      raise OutOfBounds if nposition > @limit
      value = @buffer.get_string(@position, length)
      @position = nposition
      value
    end

    def get_zstring(unterminated_ok: false)
      nposition = @position
      nul_found = false
      while nposition < @limit
        c = @buffer.get_value(:U8, nposition)
        nposition += 1
        if c == 0
          nul_found = true
          break
        end
      end
      raise Unterminated if !nul_found && !unterminated_ok
      value = @buffer.get_string(@position, nposition - @position - (nul_found ? 1 : 0))
      @position = nposition
      value
    end

    def get_value(type)
      nposition = @position + IO::Buffer.size_of(type)
      raise OutOfBounds if nposition > @limit
      value = @buffer.get_value(type, @position)
      @position = nposition
      value
    end

    def get_values(types)
      nposition = @position + IO::Buffer.size_of(types)
      raise OutOfBounds if nposition > @limit
      values = @buffer.get_values(types, @position)
      @position = nposition
      values
    end

    def align_to(alignment)
      nposition = (@position + alignment - 1) & ~(alignment - 1)
      raise OutOfBounds if nposition > @limit
      @position = nposition
    end
  end
end
