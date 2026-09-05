# rbs_inline: enabled

require_relative 'error'
require_relative 'raw/protocol'

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

    def accept(frame)
      @mutex.synchronize do
        return if @complete

        case frame
        when Raw::UnknownFrame
          nil
        when Raw::ErrorFrame
          @cancelled ? complete(nil) : fail_with(SystemCallError.new(frame.errno))
        when Raw::DoneFrame
          if frame.errno && !@cancelled
            fail_with(SystemCallError.new(frame.errno))
          else
            complete(@reply)
          end
        when Raw::AckFrame
          accept_ack
        when Raw::DataFrame
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

    private def accept_ack
      @acked = true
      if @cancelled || @state == :no_reply || @state == :single
        complete(@reply)
      end
    end

    private def accept_reply(frame)
      return if @cancelled

      multipart = (frame.header.flags.to_i & Raw::NLM_F_MULTI) != 0
      case @state
      when :dump
        return Item.new(frame.message)
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

      @reply ||= frame.message
      complete(frame.message) if @acked && @state == :single
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
