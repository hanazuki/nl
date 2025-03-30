module Nl
  module Endian
    SIZEOF_INT = [1].pack('i!').bytesize
    SIZEOF_LONG = [1].pack('l!').bytesize
    SIZEOF_LLONG = [1].pack('q!').bytesize

    module Little
      U8, S8, U16, S16, U32, S32, U64, S64, F32, F64 = :U8, :S8, :u16, :s16, :u32, :s32, :u64, :s64, :f32, :f64
    end

    module Big
      U8, S8, U16, S16, U32, S32, U64, S64, F32, F64 = :U8, :S8, :U16, :S16, :U32, :S32, :U64, :S64, :F32, :F64
    end

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
    end
  end
end
