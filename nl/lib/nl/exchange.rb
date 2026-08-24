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

    def accept(message)
      @mutex.synchronize do
        return Ignore.new if @complete

        case message
        when Protocols::Raw::Ignored
          Ignore.new
        when Protocols::Raw::Error
          @cancelled ? complete(nil) : fail_with(SystemCallError.new(message.errno))
        when Protocols::Raw::Done
          if message.errno && !@cancelled
            fail_with(SystemCallError.new(message.errno))
          else
            complete(@reply)
          end
        when Protocols::Raw::Ack
          accept_ack
        else
          accept_reply(message)
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

    private def accept_reply(message)
      return Ignore.new if @cancelled

      multipart = multipart?(message)
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

      return Item.new(message) if @kind == :dump

      @reply ||= message
      @acked && @state == :single ? complete(message) : Ignore.new
    end

    private def multipart?(message)
      message.respond_to?(:nlmsg_header) &&
        (message.nlmsg_header.flags.to_i & Core::NLM_F_MULTI) != 0
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
