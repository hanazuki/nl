require 'nl/linux/rt_link'

RSpec.describe Nl::Linux::RtLink do
  let(:encoder) { Nl::Encoder.new }

  describe 'Structs::Ifinfomsg' do
    # ifi_family(U8), pad(ignored), ifi_type(U16), ifi_index(S32), ifi_flags(U32), ifi_change(U32)
    subject(:struct) { described_class::Structs::Ifinfomsg.new(0xAB, nil, 0xCDEF, 0x12345678, 0xDEADBEEF, 0xCAFEBABE) }

    it 'encodes each field at the correct offset' do
      struct.encode(encoder)
      expect(encoder.buffer.get_string.bytesize).to eq 16
      ifi_family, pad, ifi_type, ifi_index, ifi_flags, ifi_change =
        encoder.buffer.get_string.unpack('C C S< l< L< L<')
      expect(ifi_family).to eq 0xAB
      expect(pad).to eq 0x00  # pad is always zero
      expect(ifi_type).to eq 0xCDEF
      expect(ifi_index).to eq 0x12345678
      expect(ifi_flags).to eq 0xDEADBEEF
      expect(ifi_change).to eq 0xCAFEBABE
    end
  end

  describe 'Messages::DumpGetlinkRequest' do
    subject(:message) do
      msg = described_class::Messages::DumpGetlinkRequest.from_params({})
      msg.nlmsg_header.flags = 0
      msg.nlmsg_header.seq = 12345
      msg.nlmsg_header.pid = 67890
      msg
    end

    it 'serializes to 32 bytes (nlmsghdr + ifinfomsg, no attributes)' do
      message.encode(encoder)
      expect(encoder.buffer.get_string.bytesize).to eq 32
    end

    it 'encodes nlmsghdr fields at the correct offsets' do
      message.encode(encoder)
      # len(U32), type(U16), flags(U16), seq(U32), pid(U32)
      len, type, flags, seq, pid = encoder.buffer.get_string.unpack('L< S< S< L< L<')
      expect(len).to eq 32
      expect(type).to eq 18  # RTM_GETLINK
      expect(flags).to eq 0
      expect(seq).to eq 12345
      expect(pid).to eq 67890
    end

    it 'encodes ifinfomsg as all zeros at bytes 16-31' do
      message.encode(encoder)
      expect(encoder.buffer.get_string[16, 16]).to eq(?\x0.b * 16)
    end
  end
end
