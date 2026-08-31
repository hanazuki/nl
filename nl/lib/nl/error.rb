module Nl
  class Error < StandardError; end
  class ProtocolViolation < Error; end
  class ExhaustedSequenceNumber < Error; end
  class TimeoutError < Error; end
  class ClosedError < Error; end
  class NotificationLossError < Error; end
  class UnknownMulticastGroupError < Error; end
  class UnresolvedMulticastGroupError < Error; end
end
