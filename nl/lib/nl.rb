require_relative 'nl/error'
require_relative 'nl/core'
require_relative 'nl/notification'
require_relative 'nl/connection'
require_relative 'nl/family'
require_relative 'nl/genl'
require_relative 'nl/socket'
require_relative 'nl/version'

module Nl
  include Core
  include Genl
end
