require_relative 'wire'
require_relative '../raw'

module Nl
  module Genl
    # A generated Generic Netlink family bound to nlctrl-provided information.
    class Endpoint < Raw::Endpoint
      attr_reader :info

      def initialize(definition, info)
        super(definition)
        @info = info
      end

      def family_id = @info.id
      def frame_type(_message_class) = family_id

      def multicast_group_id(name, _value)
        @info.multicast_groups.fetch(name) do
          raise UnresolvedMulticastGroupError,
            "Generic Netlink multicast group #{name.inspect} was not resolved"
        end
      end
    end

    # Socket-wide Generic Netlink wire behavior.
    class Protocol < Raw::Protocol
      def initialize
        super(Raw::NETLINK_GENERIC)
      end

      def encode_message(encoder, _endpoint, request, seq:, pid:)
        message = request.message
        header = Raw::NlMsgHdr.new(0, request.type, request.flags, seq, pid)
        encoder.measure(Endian::Host::U16) do
          header.encode(encoder)
          Nl::Genl::GenlMsgHdr.new(message.class::TYPE, 1, 0).encode(encoder)
          message.encode(encoder)
        end
      end

      def notification_channel_key(endpoint) = endpoint.family_id
      def notification_route_keys(endpoint, _classes) = [endpoint.family_id]
      def notification_frame_key(header) = header.type

      def notification_frame?(endpoint, header, _payload)
        header.type == endpoint.family_id
      end

      def notification_class(endpoint, header, payload, classes)
        return unless notification_frame?(endpoint, header, payload)

        command = Nl::Genl::GenlMsgHdr.decode(Decoder.new(payload)).cmd
        classes[command]
      end
    end

    class Message < Raw::Message
      def self.decode(decoder, type:)
        genlhdr = Nl::Genl::GenlMsgHdr.decode(decoder)
        super(decoder, type: genlhdr.cmd)
      end
    end
  end
end
