module Nl
  class Error < StandardError; end
  class ProtocolViolation < Error; end
  class ExhaustedSequenceNumber < Error; end
end
