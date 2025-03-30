module Nl
  class Encoder
    attr_reader :position

    def initialize(capacity = 4096)
      @buffer = IO::Buffer.new(capacity)
      @position = 0
    end

    def reserve(size)
      nposition = @position + size
      if @buffer.size < nposition
        @buffer.resize([@buffer.size * 2, nposition].max)
      end
    end

    def put_string(value)
      reserve(value.bytesize)
      @position = @buffer.set_string(value, @position)
    end

    def put_zstring(value)
      reserve(value.bytesize + 1)
      @position = @buffer.set_string(value, @position)
      @position = @buffer.set_value(:U8, @position, 0)
    end

    def put_value(type, value)
      reserve(IO::Buffer.size_of(type))
      @position = @buffer.set_value(type, @position, value)
    end

    def put_values(types, values)
      reserve(IO::Buffer.size_of(types))
      @position = @buffer.set_values(types, @position, values)
    end

    def align_to(alignment)
      if alignment > 1
        nposition = (@position + alignment - 1) & ~(alignment - 1)
        reserve(nposition - @position)
        @position = nposition
      end
    end

    def put_value_at(offset, type, value)
      @buffer.set_value(type, offset, value)
    end

    def put_values_at(offset, types, values)
      @buffer.set_values(types, offset, values)
    end

    def buffer
      @buffer.slice(0, @position)
    end

    def measure(type, offset = 0)
      before = @position
      yield
      after = @position
      put_value_at(before + offset, type, after - before)
    end
  end
end
