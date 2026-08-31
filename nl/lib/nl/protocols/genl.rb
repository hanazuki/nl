require_relative '../genl'
require_relative 'raw'

module Nl
  module Protocols
    # The Generic Netlink protocol
    class Genl < Raw
      class NotificationRouting
        def family_key(protocol) = protocol.family_key
        def frame_key(header) = header.type
      end

      NOTIFICATION_ROUTING = NotificationRouting.new.freeze

      def self.protonum = Core::NETLINK_GENERIC

      def initialize(name, family_id: nil, multicast_groups: {})
        super(name, self.class.protonum)
        @family_id = family_id || default_family_id(name)
        @multicast_groups = multicast_groups.transform_keys(&:to_sym).freeze
      end

      def family_id
        @family_id or raise NotImplementedError, "Genetlink family ID for '#{name}' must be resolved via nlctrl"
      end

      def encode_message(encoder, request, seq:, pid:)
        message = request.message
        header = Core::NlMsgHdr.new(0, request.type, request.flags, seq, pid)
        encoder.measure(Endian::Host::U16) do
          header.encode(encoder)
          Nl::Genl::GenlMsgHdr.new(message.class::TYPE, 1, 0).encode(encoder)
          message.encode(encoder)
        end
      end

      class Message < Raw::Message
        def self.decode(decoder, type:)
          genlhdr = Nl::Genl::GenlMsgHdr.decode(decoder)
          super(decoder, type: genlhdr.cmd)
        end
      end

      def family_key = family_id

      def self.notification_routing = NOTIFICATION_ROUTING
      def notification_routing = self.class.notification_routing

      def notification_frame?(header, _payload)
        header.type == family_id
      end

      def notification_class(header, payload, classes)
        return unless notification_frame?(header, payload)

        command = Nl::Genl::GenlMsgHdr.decode(Decoder.new(payload)).cmd
        classes[command]
      end

      def multicast_group_id(name, _value)
        @multicast_groups.fetch(name.to_sym) do
          raise UnresolvedMulticastGroupError,
            "Generic Netlink multicast group #{name.inspect} was not resolved"
        end
      end

      private def frame_type(_message_class) = family_id

      private def default_family_id(name)
        Nl::Genl::GENL_ID_CTRL if name == 'nlctrl'
      end
    end
  end
end
