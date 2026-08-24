# rbs_inline: enabled

module Nl
  # State machine for one Netlink request/reply exchange.
  class Exchange
    Item = Data.define(:value)
    Complete = Data.define(:value)
    Failure = Data.define(:exception)
    Ignore = Data.define

    attr_reader :kind

    def initialize(kind:, expects_reply:)
      @kind = kind
      @expects_reply = expects_reply
      @reply = nil
      @state = kind == :dump ? :multi : :initial
      @acked = false
      @cancelled = false
      @complete = false
      @result = nil
      @mutex = Mutex.new
    end

    def accept(frame)
      @mutex.synchronize do
        return Ignore.new if @complete

        case frame
        when Protocols::Raw::UnknownFrame
          Ignore.new
        when Protocols::Raw::ErrorFrame
          @cancelled ? complete(nil) : fail_with(SystemCallError.new(frame.errno))
        when Protocols::Raw::DoneFrame
          if frame.errno && !@cancelled
            fail_with(SystemCallError.new(frame.errno))
          else
            complete(@reply)
          end
        when Protocols::Raw::AckFrame
          accept_ack
        when Protocols::Raw::DataFrame
          accept_reply(frame)
        else
          raise ArgumentError, "unexpected exchange input: #{frame.inspect}"
        end
      end
    end

    def cancel
      @mutex.synchronize { @cancelled = true unless @complete }
      nil
    end

    def cancelled? = @mutex.synchronize { @cancelled }
    def complete? = @mutex.synchronize { @complete }
    def result = @mutex.synchronize { @result }
    def expects_reply? = @expects_reply

    private def accept_ack
      @acked = true
      if @cancelled || !@expects_reply || @state == :single
        complete(@reply)
      else
        Ignore.new
      end
    end

    private def accept_reply(frame)
      return Ignore.new if @cancelled

      multipart = (frame.header.flags.to_i & Core::NLM_F_MULTI) != 0
      case @state
      when :initial
        @state = multipart ? :multi : :single
      when :single
        return fail_with(ProtocolViolation.new('more than one data message in a non-multipart Netlink response'))
      when :multi
        unless multipart
          return fail_with(ProtocolViolation.new('multipart Netlink response contains data without NLM_F_MULTI'))
        end
      end

      return Item.new(frame.message) if @kind == :dump

      @reply ||= frame.message
      @acked && @state == :single ? complete(frame.message) : Ignore.new
    end

    private def complete(value)
      @complete = true
      @result = value
      Complete.new(value)
    end

    private def fail_with(exception)
      @complete = true
      Failure.new(exception)
    end
  end
end
