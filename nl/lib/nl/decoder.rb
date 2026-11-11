require_relative 'endian'

module Nl
  class Decoder
    class Error < StandardError; end
    class OutOfBounds < Error
      def initialize(message = 'out of bounds') = super
    end
    class Unterminated < Error
      def initialize(message = 'unterminated string') = super
    end

    VALUE_READERS = {
      U8: :get_U8, S8: :get_S8,
      u16: :get_u16, U16: :get_U16,
      s16: :get_s16, S16: :get_S16,
      u32: :get_u32, U32: :get_U32,
      s32: :get_s32, S32: :get_S32,
      u64: :get_u64, U64: :get_U64,
      s64: :get_s64, S64: :get_S64,
      f32: :get_f32, F32: :get_F32,
      f64: :get_f64, F64: :get_F64,
    }.freeze

    VALUE_READERS.each do |type, reader|
      # Emit a literal buffer type so the JIT can specialize the load.
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def #{reader}
          nposition = @position + #{IO::Buffer.size_of(type)}
          raise OutOfBounds if nposition > @limit
          value = @buffer.get_value(#{type.inspect}, @position)
          @position = nposition
          value
        end
      RUBY
    end

    alias_method :get_host_u8, :"get_#{Endian::Host::U8}"
    alias_method :get_host_s8, :"get_#{Endian::Host::S8}"
    alias_method :get_host_u16, :"get_#{Endian::Host::U16}"
    alias_method :get_host_s16, :"get_#{Endian::Host::S16}"
    alias_method :get_host_u32, :"get_#{Endian::Host::U32}"
    alias_method :get_host_s32, :"get_#{Endian::Host::S32}"
    alias_method :get_host_u64, :"get_#{Endian::Host::U64}"
    alias_method :get_host_s64, :"get_#{Endian::Host::S64}"
    alias_method :get_host_f32, :"get_#{Endian::Host::F32}"
    alias_method :get_host_f64, :"get_#{Endian::Host::F64}"
    alias_method :get_host_uint, :"get_#{Endian::Host::UINT}"
    alias_method :get_host_sint, :"get_#{Endian::Host::SINT}"
    alias_method :get_host_ulong, :"get_#{Endian::Host::ULONG}"
    alias_method :get_host_slong, :"get_#{Endian::Host::SLONG}"
    alias_method :get_host_ullong, :"get_#{Endian::Host::ULLONG}"
    alias_method :get_host_sllong, :"get_#{Endian::Host::SLLONG}"

    alias get_host_int get_host_sint
    alias get_host_long get_host_slong
    alias get_host_llong get_host_sllong

    def initialize(buffer, offset = 0, length = buffer.size - offset)
      @buffer = buffer
      @position = offset
      @limit = offset + length
    end

    def available?(size = 1)
      @position + size <= @limit
    end

    def remaining
      @limit - @position
    end

    def limit(size)
      orig_limit = @limit
      new_limit = @position + size
      raise OutOfBounds if size < 0 || new_limit > orig_limit

      @limit = new_limit
      result = yield self
      if @limit != @position
        raise "Not all bytes upto specified limit is consumed"
      end
      result
    ensure
      @limit = orig_limit
    end

    def lookahead
      orig_position = @position
      yield self
    ensure
      @position = orig_position
    end

    def skip(length = @limit - @position)
      nposition = @position + length
      raise OutOfBounds if nposition > @limit
      @position = nposition
    end

    def get_string(length = @limit - @position)
      nposition = @position + length
      raise OutOfBounds if length < 0 || nposition > @limit
      value = @buffer.get_string(@position, length)
      @position = nposition
      value
    end

    def slice(length = @limit - @position)
      nposition = @position + length
      raise OutOfBounds if length < 0 || nposition > @limit
      value = self.class.new(@buffer, @position, length)
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

    def get_values(types)
      nposition = @position + IO::Buffer.size_of(types)
      raise OutOfBounds if nposition > @limit
      values = @buffer.get_values(types, @position)
      @position = nposition
      values
    end

    def align_to_4
      nposition = (@position + 3) & -4
      raise OutOfBounds if nposition > @limit
      @position = nposition
    end
  end
end
