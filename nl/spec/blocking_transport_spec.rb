# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Nl::BlockingTransport do
  BlockingReply = Class.new(String) do
    attr_reader :nlmsg_header

    def initialize(value, nlmsg_header)
      super(value)
      @nlmsg_header = nlmsg_header
    end
  end

  BlockingFakeSocket = Struct.new(:datagrams, :closed) do
    def recvmsg = [datagrams.shift]
    def close = self.closed = true
    def closed? = !!closed
  end

  BlockingFakeProtocol = Class.new do
    def initialize
      @raw = Nl::Protocols::Raw.new('fake', 0)
    end

    def build_request(kind, request_class, args) = [kind, request_class, args]
    def send_message(_socket, _request) = [1, 77]

    def decode_frame(header, payload, _reply_class)
      if header.type < Nl::Core::NLMSG_MIN_TYPE
        @raw.decode_frame(header, payload, nil)
      else
        BlockingReply.new(payload.get_string, header)
      end
    end
  end

  def frame(type:, sequence: 1, flags: 0, payload: ''.b)
    encoder = Nl::Encoder.new
    encoder.measure(Nl::Endian::Host::U32) do
      Nl::Core::NlMsgHdr.new(0, type, flags, sequence, 77).encode(encoder)
      encoder.put_string(payload)
    end
    encoder.align_to(Nl::Core::NLMSG_ALIGNTO)
    encoder.buffer.get_string
  end

  def ack(sequence: 1, errno: 0)
    frame(type: Nl::Core::NLMSG_ERROR, sequence:, payload: [errno].pack('i!'))
  end

  def done(sequence: 1, errno: 0)
    frame(type: Nl::Core::NLMSG_DONE, sequence:, payload: [errno].pack('i!'))
  end

  it 'is not async-capable' do
    expect(described_class.allocate).not_to be_async_capable
  end

  it 'returns a do reply after its ACK' do
    socket = BlockingFakeSocket.new([frame(type: 42, payload: 'reply') + ack])

    result = described_class.new(socket).exchange(BlockingFakeProtocol.new, :do, Object, String, {})

    expect(result).to eq('reply')
  end

  it 'returns the first multipart do reply after header-only DONE' do
    socket = BlockingFakeSocket.new([
      frame(type: 42, flags: Nl::Core::NLM_F_MULTI, payload: 'one') +
        frame(type: 42, flags: Nl::Core::NLM_F_MULTI, payload: 'two') +
        frame(type: Nl::Core::NLMSG_DONE),
    ])

    result = described_class.new(socket).exchange(BlockingFakeProtocol.new, :do, Object, String, {})

    expect(result).to eq('one')
  end

  it 'collects a multipart dump' do
    socket = BlockingFakeSocket.new([
      frame(type: 42, flags: Nl::Core::NLM_F_MULTI, payload: 'one') +
        frame(type: 42, flags: Nl::Core::NLM_F_MULTI, payload: 'two') + done,
    ])

    result = described_class.new(socket).exchange(BlockingFakeProtocol.new, :dump, Object, String, {})

    expect(result).to eq(%w[one two])
  end

  it 'streams a multipart dump through a block' do
    socket = BlockingFakeSocket.new([frame(type: 42, flags: Nl::Core::NLM_F_MULTI, payload: 'one') + done])
    values = []

    result = described_class.new(socket).exchange(BlockingFakeProtocol.new, :dump, Object, String, {}) do |value|
      values << value
    end

    expect(result).to be_nil
    expect(values).to eq(['one'])
  end

  it 'raises NLMSG_ERROR as the first dump response' do
    socket = BlockingFakeSocket.new([ack(errno: -22)])

    expect do
      described_class.new(socket).exchange(BlockingFakeProtocol.new, :dump, Object, String, {})
    end.to raise_error(Errno::EINVAL)
  end

  it 'rejects a positive NLMSG_ERROR errno' do
    socket = BlockingFakeSocket.new([ack(errno: Errno::EINVAL::Errno)])

    expect do
      described_class.new(socket).exchange(BlockingFakeProtocol.new, :dump, Object, String, {})
    end.to raise_error(Nl::ProtocolViolation, 'expected zero or negative NLMSG_ERROR errno, got 22')
  end

  it 'raises an error carried by DONE as the first dump response' do
    socket = BlockingFakeSocket.new([done(errno: -Errno::EINVAL::Errno)])

    expect do
      described_class.new(socket).exchange(BlockingFakeProtocol.new, :dump, Object, String, {})
    end.to raise_error(Errno::EINVAL)
  end

  it 'rejects a truncated DONE errno' do
    socket = BlockingFakeSocket.new([frame(type: Nl::Core::NLMSG_DONE, payload: "\0\0\0".b)])

    expect do
      described_class.new(socket).exchange(BlockingFakeProtocol.new, :dump, Object, String, {})
    end.to raise_error(Nl::Decoder::OutOfBounds)
  end

  it 'accepts a header-only DONE as implicit success' do
    socket = BlockingFakeSocket.new([frame(type: Nl::Core::NLMSG_DONE)])

    result = described_class.new(socket).exchange(BlockingFakeProtocol.new, :dump, Object, String, {})

    expect(result).to eq([])
  end

  it 'rejects a positive DONE errno' do
    socket = BlockingFakeSocket.new([done(errno: Errno::EINVAL::Errno)])

    expect do
      described_class.new(socket).exchange(BlockingFakeProtocol.new, :dump, Object, String, {})
    end.to raise_error(Nl::ProtocolViolation, 'expected zero or negative NLMSG_DONE errno, got 22')
  end

  it 'rejects a datagram for another sequence' do
    socket = BlockingFakeSocket.new([frame(type: 42, sequence: 2, payload: 'reply')])

    expect do
      described_class.new(socket).exchange(BlockingFakeProtocol.new, :do, Object, String, {})
    end.to raise_error(Nl::BlockingTransport::UnexpectedSequenceError) do |error|
      expect(error.expected).to eq([1, 77])
      expect(error.actual).to eq([2, 77])
    end
  end

  it 'rejects a concurrent exchange' do
    entered_receive = Queue.new
    release_receive = Queue.new
    ack_frame = ack
    socket = BlockingFakeSocket.new([])
    socket.define_singleton_method(:recvmsg) do
      entered_receive << true
      release_receive.pop
      [ack_frame]
    end
    exchanger = described_class.new(socket)
    active_exchange = Thread.new do
      exchanger.exchange(BlockingFakeProtocol.new, :do, Object, nil, {})
    end
    entered_receive.pop

    begin
      expect do
        exchanger.exchange(BlockingFakeProtocol.new, :do, Object, nil, {})
      end.to raise_error(
        Nl::BlockingTransport::ConcurrentExchangeError,
        'BlockingTransport supports only one active exchange',
      )
    ensure
      release_receive << true
    end
    expect(active_exchange.value).to be_nil
  end

  it 'closes its socket once' do
    socket = BlockingFakeSocket.new([])
    exchanger = described_class.new(socket)

    exchanger.close
    exchanger.close

    expect(socket).to be_closed
  end
end
