require_relative 'attribute_set'
require_relative 'structured_payload'

module Nl
  # Family payload with fixed-header fields and attribute values stored inline.
  class Message
    include StructuredPayload
  end
end
