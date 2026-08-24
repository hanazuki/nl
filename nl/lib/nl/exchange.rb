# rbs_inline: enabled

module Nl
  # State machine for one Netlink request/reply exchange.
  class Exchange
    Item = Data.define(:value)
    Complete = Data.define(:value)
    Failure = Data.define(:exception)
    Ignore = Data.define

    class UnexpectedReplyError < StandardError; end

    attr_reader :kind

    def initialize(kind:, expects_reply:)
      @kind = kind
      @expects_reply = expects_reply
      @reply = nil
      @reply_received = false
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
        when Protocols::Raw::Done
          if message.error && !@cancelled
            fail_with(message.error)
          else
            complete(@reply)
          end
        when Protocols::Raw::Ack
          accept_ack
        when Exception
          @cancelled ? complete(nil) : fail_with(message)
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
      if @cancelled || @kind == :dump || !@expects_reply || @reply_received
        complete(@reply)
      else
        Ignore.new
      end
    end

    private def accept_reply(message)
      return Ignore.new if @cancelled
      return Item.new(message) if @kind == :dump
      if @reply_received
        return fail_with(UnexpectedReplyError.new('more than one reply in a single Netlink exchange'))
      end

      @reply = message
      @reply_received = true
      @acked ? complete(message) : Ignore.new
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
