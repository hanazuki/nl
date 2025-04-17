module Nl
  module Protocols
    # The raw Netlink protocol
    class Raw
      class Done
      end
      class Ack
      end

      attr_reader :name, :protonum

      def initialize(name, protonum)
        @name = name
        @protonum = protonum
      end

      def encode_message(encoder, message)
        message.encode(encoder)
      end

      def decode_message(decoder, message_class)
        header = NlMsgHdr.decode(decoder)
        decoder.limit(header.len - Core::NLMSG_HDRLEN) do
          message_class.decode(decoder, header)
        end
      end

      def send_message(socket, message)
        seq_pid = socket.complete(message.header)
        encoder = Encoder.new
        encode_message(encoder, message)
        socket.sendmsg(encoder.buffer.get_string, 0, Socket.sockaddr_nl(0, 0))
        seq_pid
      end

      def recv_message(socket, seq_pid, message_class)
        data, = socket.recvmsg

        decoder = Decoder.new(IO::Buffer.for(data))
        while decoder.available?(Core::NLMSG_HDRLEN)
          header = Core::NlMsgHdr.decode(decoder)
          decoder.align_to(Core::NLMSG_ALIGNTO)
          raise binding.irb unless [header.seq, header.pid] == seq_pid
          if header.type < Core::NLMSG_MIN_TYPE
            # Control messages
            case header.type
            when Core::NLMSG_ERROR
              errno = decoder.get_value(Endian::Host::SINT)
              if errno == 0
                yield Ack.new
              else
                yield SystemCallError.new(-errno)
              end
              decoder.skip(header.len - Core::NLMSG_HDRLEN - 4)
            when Core::NLMSG_DONE
              yield Done.new
              decoder.skip(header.len - Core::NLMSG_HDRLEN)
            else
              # just ignore NLMSG_NOOP and other unknown control messages
              decoder.skip(header.len - Core::NLMSG_HDRLEN)
            end
          else
            # Subsystem-specific messages
            decoder.limit(header.len - Core::NLMSG_HDRLEN) do
              decoder.align_to(Core::NLMSG_ALIGNTO)
              yield message_class.decode(decoder, header)
            end
          end
        end
      end

      # @param socket [Socket] Netlink socket
      # @param type [:do, :dump] Request type
      # @param request_class [Class] Request message class
      # @param reply_class [Class] Reply message class
      # @param args [Hash] Request arguments
      def exchange_message(socket, type, request_class, reply_class, args)
        flags = Core::NLM_F_REQUEST | Core::NLM_F_ACK
        flags |= Core::NLM_F_DUMP if type == :dump

        request = request_class.from_params(args)
        request.header.flags = flags
        seq_pid = send_message(socket, request)

        result = []

        done = false
        acked = false
        begin
          recv_message(socket, seq_pid, reply_class) do |message|
            case message
            when Done
              done = true
            when Exception
              raise
            when Ack
              acked = true
            else
              result << message
              done = true if type == :do
            end
          end
        end unless done

        result
      end

      module DataTypes
        class Scalar
          def initialize(type, check)
            @type = type
            @check = check
          end

          def encode(encoder, value)
            value ||= 0
            encoder.put_value(@type, value.tap(&@check))
          end

          def decode(decoder)
            value = decoder.get_value(@type).tap(&@check)
          end
        end

        class String
          def initialize(check)
            @check = check
          end

          def encode(encoder, value)
            encoder.put_zstring(value)
          end

          def decode(decoder)
            decoder.get_zstring
          end
        end

        class Binary
          def initialize(check)
            @check = check
          end

          def encode(encoder, value)
            encoder.put_string(value)
          end

          def decode(decoder)
            decoder.get_string
          end
        end

        class NestedAttributes
          def initialize(attribute_set)
            @attribute_set = attribute_set
          end

          def encode(encoder, value)
            @attribute_set.encode(encoder, value)
          end

          def decode(decoder)
            @attribute_set.decode(decoder)
          end
        end
      end
    end

    # The Generic Netlink protocol
      class Genl < Raw  # TODO: Implement
      def initialize(name)
        super(name, NETLINK_GENERIC)
      end
  
      def parse(buffer, offset)
        nlmsg = super(buffer, offset)
        genlmsg = GenlMsgHdr.parse(nlmsg.data, 0)
      end
    end
  end
end
