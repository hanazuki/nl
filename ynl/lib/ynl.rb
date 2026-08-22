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

      def rbs_type
        '::Integer'
      end
    end
    String = Struct.new do
      def resolve(f)
        self
      end

      def rbs_type
        '::String'
      end
    end
    Binary = Struct.new(:struct, :length, :display_hint) do
      def resolve(f)
        self.struct = struct.resolve(f) if self.struct
        self
      end

      def rbs_type
        'untyped'
      end
    end
    NestedAttributes = Struct.new(:attribute_set) do
      using Generator::Refinements  # FIXME:

      def resolve(f)
        self.attribute_set = attribute_set.resolve(f)
        self
      end

      def rbs_type
        'AttributeSets::' + attribute_set.name.as_class_name
      end
    end
    NestTypeValue = Struct.new(:attribute_set, :type_values) do
      def resolve(f)
        self.attribute_set = attribute_set.resolve(f)
        self
      end

      def rbs_type
        'untyped'
      end
    end
    SubMessage = Struct.new(:sub_message, :selector) do
      def resolve(f)
        self.sub_message = sub_message.resolve(f)
        self
      end

      def rbs_type
        'untyped'
      end
    end

    Pad = Data.define(:length) do
      def resolve(f)
        self
      end

      def rbs_type
        'nil'
      end
    end

    Flag = Data.define do
      def resolve(f)
        self
      end

      def rbs_type
        '::Integer'
      end
    end

    Bitfield32 = Data.define do
      def resolve(f)
        self
      end

      def rbs_type
        '::Integer'
      end
    end

    IndexedArray = Struct.new(:sub_type) do
      def resolve(f)
        self.sub_type = sub_type.resolve(f)
        self
      end

      def rbs_type
        'untyped'
      end
    end
  end
end
