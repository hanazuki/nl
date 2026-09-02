require_relative 'wire'
require_relative '../decoder'
require_relative '../encoder'
require_relative '../error'
require_relative '../socket'

module Nl
  module Raw
    AckFrame = Data.define(:header)
    ErrorFrame = Data.define(:header, :errno)
    DoneFrame = Data.define(:header, :errno)
    UnknownFrame = Data.define(:header)
    DataFrame = Data.define(:header, :message)
    Request = Data.define(:type, :flags, :message)

    # A generated raw Netlink family bound to its fixed wire identity.
    class Endpoint
      attr_reader :definition

      def initialize(definition)
        @definition = definition
      end

      def name = @definition::NAME
      def frame_type(message_class) = message_class::TYPE

      def multicast_group_id(name, value)
        value or raise UnresolvedMulticastGroupError,
          "multicast group #{name.inspect} has no fixed ID"
      end
    end

    # Socket-wide wire behavior for a classic (netlink-raw) protocol.
    class Protocol
      attr_reader :protonum

      def initialize(protonum)
        @protonum = protonum
      end

      def encode_message(encoder, _endpoint, request, seq:, pid:)
        header = Raw::NlMsgHdr.new(0, request.type, request.flags, seq, pid)
        encoder.measure(Endian::Host::U16) do
          header.encode(encoder)
          request.message.encode(encoder)
        end
      end

      # Decodes one frame using the reply class associated with its sequence.
      def decode_frame(_endpoint, header, payload, message_class)
        decoder = Decoder.new(payload)
        if header.type < Raw::NLMSG_MIN_TYPE
          case header.type
          when Raw::NLMSG_ERROR
            errno = decoder.get_value(Endian::Host::SINT)
            if errno.positive?
              raise ProtocolViolation, "expected zero or negative NLMSG_ERROR errno, got #{errno}"
            end

            errno.zero? ? AckFrame.new(header:) : ErrorFrame.new(header:, errno: -errno)
          when Raw::NLMSG_DONE
            return DoneFrame.new(header:, errno: nil) unless decoder.available?

            errno = decoder.get_value(Endian::Host::SINT)
            if errno.positive?
              raise ProtocolViolation, "expected zero or negative NLMSG_DONE errno, got #{errno}"
            end

            DoneFrame.new(header:, errno: errno.negative? ? -errno : nil)
          else
            UnknownFrame.new(header:)
          end
        else
          raise ArgumentError, 'reply class is required for a data message' unless message_class

          DataFrame.new(header:, message: message_class.decode(decoder, type: header.type))
        end
      end

      def send_message(socket, endpoint, request, seq:, pid:)
        encoder = Encoder.new
        encode_message(encoder, endpoint, request, seq:, pid:)
        socket.sendmsg(encoder.buffer.get_string, 0, Socket.sockaddr_nl(0, 0))
        nil
      end

      def build_request(endpoint, kind, request_class, args)
        flags = Raw::NLM_F_REQUEST
        flags |= kind == :dump ? Raw::NLM_F_DUMP : Raw::NLM_F_ACK

        message = request_class.from_params(args)
        Request.new(type: endpoint.frame_type(request_class), flags:, message:)
      end

      # Classic Netlink support currently allows one generated family per socket.
      def family_key(_endpoint) = nil
      def frame_key(_header) = nil

      def notification_frame?(_endpoint, header, _payload)
        header.type >= Raw::NLMSG_MIN_TYPE
      end

      def notification_class(_endpoint, header, _payload, classes)
        classes[header.type]
      end

      def decode_notification(endpoint, header, payload, message_class)
        decode_frame(endpoint, header, payload, message_class).message
      end
    end
  end
end
