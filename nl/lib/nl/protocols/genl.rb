require_relative 'raw'

module Nl
  module Protocols
    # The Generic Netlink protocol
    class Genl < Raw
      GenlMsgHdr = ::Struct.new(:cmd, :version, :reserved)
      class GenlMsgHdr
        FORMAT = Ractor.make_shareable([
          Endian::Host::U8,
          Endian::Host::U8,
          Endian::Host::U16,
        ])

        def self.decode(decoder)
          new(*decoder.get_values(FORMAT))
        end

        def encode(encoder)
          encoder.put_values(FORMAT, to_a)
        end
      end

      def initialize(name, family_id: nil)
        super(name, Core::NETLINK_GENERIC)
        @family_id = family_id || default_family_id(name)
      end

      def family_id
        @family_id or raise NotImplementedError, "Genetlink family ID for '#{name}' must be resolved via nlctrl"
      end

      def encode_message(encoder, frame)
        message = frame.message
        encoder.measure(Endian::Host::U16) do
          frame.header.encode(encoder)
          GenlMsgHdr.new(message.class::TYPE, 1, 0).encode(encoder)
          message.encode(encoder)
        end
      end

      class Message < Raw::Message
        def self.decode(decoder, type:)
          genlhdr = GenlMsgHdr.decode(decoder)
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
