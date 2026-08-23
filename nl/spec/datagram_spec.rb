# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::Datagram do
  def frame(type:, sequence:, payload: ''.b)
    encoder = Nl::Encoder.new
    encoder.measure(Nl::Endian::Host::U32) do
      Nl::Core::NlMsgHdr.new(0, type, 0, sequence, 77).encode(encoder)
      encoder.put_string(payload)
    end
    encoder.align_to(Nl::Core::NLMSG_ALIGNTO)
    encoder.buffer.get_string
  end

  it 'splits aligned messages into header and payload frames' do
    frames = described_class.each_frame(
      IO::Buffer.for(
        frame(type: 20, sequence: 1, payload: 'one') +
          frame(type: 21, sequence: 2, payload: 'two'),
      ),
    ).to_a

    expect(frames.map { |header, payload| [header.type, header.seq, payload.get_string] }).to eq([
      [20, 1, 'one'],
      [21, 2, 'two'],
    ])
    expect(frames.map(&:last)).to all(be_a(IO::Buffer))
  end

  it 'rejects a payload shorter than its declared message length' do
    encoder = Nl::Encoder.new
    Nl::Core::NlMsgHdr.new(20, 20, 0, 1, 77).encode(encoder)

    expect do
      described_class.each_frame(encoder.buffer).to_a
    end.to raise_error(Nl::Decoder::OutOfBounds)
  end
end
