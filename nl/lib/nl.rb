require_relative 'nl/version'
require_relative 'nl/core'
require_relative 'nl/genl'
require_relative 'nl/socket'
require_relative 'nl/family'
require_relative 'nl/protocols/raw'
require_relative 'nl/protocols/genl'

module Nl
  class Error < StandardError; end

  include Core
  include Genl
end
