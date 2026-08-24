require_relative 'nl/async'
require_relative 'nl/blocking_transport'
require_relative 'nl/core'
require_relative 'nl/datagram'
require_relative 'nl/exchange'
require_relative 'nl/family'
require_relative 'nl/genl'
require_relative 'nl/protocols/genl'
require_relative 'nl/protocols/raw'
require_relative 'nl/socket'
require_relative 'nl/version'

module Nl
  class Error < StandardError; end

  include Core
  include Genl
end
