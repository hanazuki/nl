require_relative 'error'
require_relative 'raw/protocol'
require_relative 'message'

module Nl
  # State machine for one Netlink request/reply exchange.
  #
  # Dump exchanges are known to be multipart from the request and remain open
  # through NLMSG_DONE. Some Linux Generic Netlink dump handlers construct
  # replies with genlmsg_iput(), which leaves NLM_F_MULTI unset despite that
  # multipart lifetime. Dump mode therefore accepts data with or without the
  # flag; reply mode still uses it to detect a multipart do response.
  #
  # Some operations also return multipart data for a do request, although YNL
  # cannot declare such a reply. Reply mode handles this kernel behavior by
  # retaining the first data message, draining the remainder, and completing
  # on NLMSG_DONE instead of ACK.
  class Exchange
    Item = Data.define(:value)
    Complete = Data.define
    COMPLETE = Complete.new
    Failure = Data.define(:exception)

    MODES = %i[dump no_reply reply].freeze
    private_constant :MODES

    attr_reader :mode

    # @rbs (mode: :dump | :no_reply | :reply) -> void
    def initialize(mode:)
      raise ArgumentError, "unknown exchange mode: #{mode.inspect}" unless MODES.include?(mode)

      @mode = mode
      @reply = nil
      # Receive states:
      # - :dump accepts and emits every data message, then completes on DONE.
      # - :no_reply rejects data and completes on ACK.
      # - :initial waits for the first data message of a reply operation.
      # - :single retains that message and completes once ACK is received.
      # - :multi retains the first message, drains the rest, and
      #   completes on DONE. Every data message must carry NLM_F_MULTI.
      @state = mode == :reply ? :initial : mode
      @acked = false
      @cancelled = false
      @complete = false
      @result = nil
      @mutex = Mutex.new
    end

    def accept(header, message)
      @mutex.synchronize do
        return if @complete

        case message
        when Raw::Unknown
          nil
        when Raw::Error
          @cancelled ? complete(nil) : fail_with(SystemCallError.new(message.errno))
        when Raw::Done
          if message.errno && !@cancelled
            fail_with(SystemCallError.new(message.errno))
          else
            complete(@reply)
          end
        when Raw::Ack
          accept_ack
        when Message
          accept_reply(header, message)
        else
          raise ArgumentError, "unexpected exchange input: #{message.inspect}"
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

    private def accept_ack
      @acked = true
      if @cancelled || @state == :no_reply || @state == :single
        complete(@reply)
      end
    end

    private def accept_reply(header, message)
      return if @cancelled

      multipart = (header.flags.to_i & Raw::NLM_F_MULTI) != 0
      case @state
      when :dump
        return Item.new(message)
      when :no_reply
        return fail_with(ProtocolViolation.new('unexpected data message in a no-reply Netlink response'))
      when :initial
        @state = multipart ? :multi : :single
      when :single
        return fail_with(ProtocolViolation.new('more than one data message in a non-multipart Netlink response'))
      when :multi
        unless multipart
          return fail_with(ProtocolViolation.new('multipart Netlink response contains data without NLM_F_MULTI'))
        end
      end

      @reply ||= message
      complete(message) if @acked && @state == :single
    end

    private def complete(value)
      @complete = true
      @result = value
      COMPLETE
    end

    private def fail_with(exception)
      @complete = true
      Failure.new(exception)
    end
  end
end
