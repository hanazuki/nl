require_relative '../genl'
require_relative 'raw'

module Nl
  module Protocols
    # The Generic Netlink protocol
    class Genl < Raw
      def initialize(name, family_id: nil)
        super(name, Core::NETLINK_GENERIC)
        @family_id = family_id || default_family_id(name)
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

      private def frame_type(_message_class) = family_id

      private def default_family_id(name)
        Nl::Genl::GENL_ID_CTRL if name == 'nlctrl'
      end
    end
  end
end
