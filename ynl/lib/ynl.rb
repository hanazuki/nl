# Parse for YNL netlink specification
#
# See: https://www.kernel.org/doc/html/latest/userspace-api/netlink/specs.html

require_relative 'ynl/family'

module Ynl
  class ParseError < StandardError; end

  module Types
    Scalar = Data.define(:type, :byte_order) do
      def resolve(f)
        self
      end
    end
    String = Struct.new do
      def resolve(f)
        self
      end
    end
    Binary = Struct.new(:struct, :length, :display_hint) do
      def resolve(f)
        self.struct = struct.resolve(f) if self.struct
        self
      end
    end
    NestedAttributes = Struct.new(:attribute_set) do
      def resolve(f)
        self.attribute_set = attribute_set.resolve(f)
        self
      end
    end
    SubMessage = Struct.new(:sub_message, :selector) do
      def resolve(f)
        self.sub_message = sub_message.resolve(f)
        self
      end
    end

    Pad = Data.define(:length) do
      def resolve(f)
        self
      end
    end
  end

end
