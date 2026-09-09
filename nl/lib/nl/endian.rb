module Nl
  # Byte-order helpers
  module Endian
    # sizeof(int)
    SIZEOF_INT = [1].pack('i!').bytesize
    # sizeof(long)
    SIZEOF_LONG = [1].pack('l!').bytesize
    # sizeof(long long)
    SIZEOF_LLONG = [1].pack('q!').bytesize

    # Little-endian scalar types.
    module Little
      U8, S8, U16, S16, U32, S32, U64, S64, F32, F64 = :U8, :S8, :u16, :s16, :u32, :s32, :u64, :s64, :f32, :f64
    end

    # Big-endian scalar types.
    module Big
      U8, S8, U16, S16, U32, S32, U64, S64, F32, F64 = :U8, :S8, :U16, :S16, :U32, :S32, :U64, :S64, :F32, :F64
    end

    # Host-endian scalar types.
    #
    # This module includes either {Little} or {Big} depending on the host's native byte order.
    module Host
      include (IO::Buffer::HOST_ENDIAN == IO::Buffer::LITTLE_ENDIAN ? Little : Big)

      UINT, SINT = case SIZEOF_INT
        when 2; [U16, S16]
        when 4; [U32, S32]
        when 8; [U64, S64]
        else raise "Unsupported 'int' size"
      end
      ULONG, SLONG = case SIZEOF_LONG
        when 4; [U32, S32]
        when 8; [U64, S64]
        else raise "Unsupported 'long' size"
      end
      ULLONG, SLLONG = case SIZEOF_LLONG
        when 8; [U64, S64]
        else raise "Unsupported 'long long' size"
      end

      INT, LONG, LLONG = SINT, SLONG, SLLONG
    end
  end
end
