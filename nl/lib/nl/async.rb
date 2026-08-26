# rbs_inline: enabled

module Nl
  # Asynchronous request handling support.
  module Async
    class TimeoutError < StandardError; end
    class ClosedError < StandardError; end
    class UnavailableError < StandardError; end
  end
end

require_relative 'async/mailbox'
require_relative 'async/operation'
require_relative 'async/driver'
require_relative 'async/dispatcher'
