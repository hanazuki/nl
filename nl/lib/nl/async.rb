# rbs_inline: enabled

require_relative 'error'

module Nl
  # Asynchronous request handling support.
  module Async
    class UnavailableError < StandardError; end
  end
end

require_relative 'async/mailbox'
require_relative 'async/operation'
require_relative 'async/driver'
require_relative 'async/dispatcher'
