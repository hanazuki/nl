# frozen_string_literal: true

class RtLinkProtocol < Nl::Protocol
  def initialize
    super('rt_link', Nl::NETLINK_ROUTE)
  end

  def encode_message(encoder, message)
    message.encode(encoder)
  end

  def decode_message(header, payload)
    fixed_header = IfInfoMsg.decode(payload)
    p header, fixed_header, payload
  end
end

IfInfoMsg = Struct.new(:family, :pad, :type, :index, :flags, :change)
class IfInfoMsg
  FORMAT = [
    :U8,
    :U8,
    Nl::Endian::Host::U16,
    Nl::Endian::Host::S32,
    Nl::Endian::Host::U32,
    Nl::Endian::Host::U32,
  ]

  def encode(encoder)
    encoder.put_values(FORMAT, to_a)
  end

  def self.decode(decoder)
    new(*decoder.get_values(FORMAT))
  end
end

RSpec.describe Nl do
  it "has a version number" do
    expect(Nl::VERSION).not_to be nil
  end

  example do
    protocol = RtLinkProtocol.new
    socket = Nl::Socket.new(protocol)

    request = Nl::Message.new(type: 18, flags: Nl::Core::NLM_F_REQUEST | Nl::Core::NLM_F_DUMP)
    request.fixed_header = IfInfoMsg.new(0, 0, 0, 0, 0, 0)

    socket.send(request)

    socket.recv do |msg|
      binding.irb
    end

    socket.recv do |msg|
      #binding.irb
    end
  end
    
  end
