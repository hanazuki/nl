module Ynl
  module Models
    Family = ::Struct.new(:name, :protocol, :protonum, :doc,
      :consts, :enums, :flags, :structs,
      :attribute_sets, :sub_messages, :operations, :mcast_groups)
    class Family
      def resolve
        structs.transform_values! {|s| s.resolve(self) }
        attribute_sets.transform_values! {|s| s.resolve(self) }
        self
      end

      def find_type(name)
        enums[name] or flags[name] or structs[name] or raise ParseError, "Unknown type: #{name}"
      end
    end

    class Thunk
      def initialize(&block)
        @block = block
      end

      def resolve(f)
        raise ParseError, "Circular dependency" if @resolving
        @resolving = true
        @block.call(f)
      end
    end

    class Enum
      Entry = ::Struct.new(:name, :value, :doc)

      attr_reader :name, :entries, :doc

      def initialize(name:, doc:)
        @name = name
        @entries = []
        @doc = doc
      end

      def resolve(f)
        self
      end
    end

    class Flags
      Entry = ::Struct.new(:name, :value, :doc)

      attr_reader :name, :entries, :doc

      def initialize(name:, doc:)
        @name = name
        @entries = []
        @doc = doc
      end

      def resolve(f)
        self
      end
    end

    class Struct
      Member = ::Struct.new(:name, :type, :doc) do
        def resolve(f)
          self.type = self.type.resolve(f)
          self
        end
      end

      attr_reader :name, :members, :doc

      def initialize(name:, doc:)
        @name = name
        @members = []
        @doc = doc
      end

      def resolve(f)
        @members.map! {|m| m.resolve(f) }
        self
      end
    end

    class AttributeSet
      Attribute = ::Struct.new(:name, :type, :value, :checks, :doc) do
        def resolve(f)
          self.type = type.resolve(f)
          self
        end
      end

      attr_reader :name, :name_prefix, :attributes, :doc

      def initialize(name:, name_prefix:, doc:)
        @name = name
        @name_prefix = name_prefix
        @attributes = []
        @doc = doc
      end

      def resolve(f)
        attributes.map! { it.resolve(f) }
        self
      rescue
        raise ParseError, "Failed to resolve attribute set: #{name}"
      end
    end

    class Operation
      attr_reader :name, :doc, :fixed_header, :attribute_set, :doit, :dumpit

      def initialize(name:, doc:, fixed_header:, attribute_set:, doit:, dumpit:)
        @name = name
        @doc = doc
        @fixed_header = fixed_header
        @attribute_set = attribute_set
        @doit = doit
        @dumpit = dumpit
      end

      def resolve(f)
        @doit = @doit.resolve(f)
        @dumpit = @dumpit.resolve(f)
        self
      end
    end

    class RequestReply
      attr_reader :request, :reply

      def initialize(request:, reply:)
        @request = request
        @reply = reply
      end

      def resolve(f)
        @request = @request.resolve(f)
        @reply = @reply.resolve(f)
        self
      end
    end

    class Message
      attr_reader :value, :attributes

      def initialize(value:, attributes:)
        @value = value
        @attributes = attributes
      end

      def resolve(f)
        self
      end
    end
  end
end
