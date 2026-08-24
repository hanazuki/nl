# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Protocols::Raw do
  subject(:protocol) { described_class.new('fake', 0) }

  def decode_control(type, errno: nil)
    header = Nl::Core::NlMsgHdr.new(0, type, 0, 1, 77)
    payload = errno.nil? ? ''.b : [errno].pack('i!')
    protocol.decode_frame(header, IO::Buffer.for(payload), nil)
  end

  it 'decodes NLMSG_ERROR errno as data' do
    message = decode_control(Nl::Core::NLMSG_ERROR, errno: -Errno::EINVAL::Errno)

    expect(message).to eq(described_class::Error.new(errno: Errno::EINVAL::Errno))
  end

  it 'decodes NLMSG_DONE errno as data' do
    message = decode_control(Nl::Core::NLMSG_DONE, errno: -Errno::EINVAL::Errno)

    expect(message).to eq(described_class::Done.new(errno: Errno::EINVAL::Errno))
  end

  it 'decodes a header-only NLMSG_DONE as successful completion' do
    message = decode_control(Nl::Core::NLMSG_DONE)

    expect(message).to eq(described_class::Done.new(errno: nil))
  end
end
