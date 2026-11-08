module Ynl
  module Models
    Family = ::Struct.new(:name, :protocol, :version, :protonum, :doc,
      :consts, :enums, :flags, :structs,
      :attribute_sets, :sub_messages, :operations, :mcast_groups)
    class Family
      def find_type(name)
        enums[name] or flags[name] or structs[name] or raise ParseError, "Unknown type: #{name}"
      end
    end

    Const = ::Struct.new(:name, :value, :doc)
    Check = ::Struct.new(:operation, :value)

    class SubMessage
      Format = ::Struct.new(:value, :fixed_header, :attribute_set)

      attr_reader :name, :formats

      def initialize(name:, formats:)
        @name = name
        @formats = formats
      end
    end

    class Enum
      Entry = ::Struct.new(:name, :value, :doc)

      attr_reader :name, :entries, :doc

      def initialize(name:, entries:, doc:)
        @name = name
        @entries = entries
        @doc = doc
      end
    end

    class Flags
      Entry = ::Struct.new(:name, :value, :doc)

      attr_reader :name, :entries, :doc

      def initialize(name:, entries:, doc:)
        @name = name
        @entries = entries
        @doc = doc
      end
    end

    class Struct
      Member = ::Struct.new(:name, :type, :doc)

      attr_reader :name, :members, :doc

      def initialize(name:, members:, doc:)
        @name = name
        @members = members
        @doc = doc
      end
    end

    class AttributeSet
      Attribute = ::Struct.new(:name, :type, :value, :checks, :doc, :multi_attr, :enum, :enum_as_flags) do
        def multi?
          multi_attr
        end
      end

      attr_reader :name, :name_prefix, :attributes, :doc

      def initialize(name:, name_prefix:, attributes:, doc:)
        @name = name
        @name_prefix = name_prefix
        @attributes = attributes
        @doc = doc
      end
    end

    class AttributeSubset
      attr_reader :name, :superset, :doc

      def initialize(name:, superset:, attributes:, doc:)
        @name = name
        @superset = superset
        @attributes = attributes
        @doc = doc
      end

      def attributes
        @attributes
      end
    end

    McastGroup = ::Struct.new(:name, :value, :doc)

    class Operation
      attr_reader :name, :doc, :flags, :fixed_header, :attribute_set, :doit, :dumpit, :notification

      def initialize(name:, doc:, flags:, fixed_header:, attribute_set:, doit:, dumpit:, notification:)
        @name = name
        @doc = doc
        @flags = flags
        @fixed_header = fixed_header
        @attribute_set = attribute_set
        @doit = doit
        @dumpit = dumpit
        @notification = notification
      end
    end

    class Notification
      attr_reader :kind, :message, :source, :group

      def initialize(kind:, message:, source:, group:)
        @kind = kind
        @message = message
        @source = source
        @group = group
      end
    end

    class RequestReply
      attr_reader :request, :reply

      def initialize(request:, reply:)
        @request = request
        @reply = reply
      end
    end

    class Message
      attr_reader :value, :attributes

      def initialize(value:, attributes:)
        @value = value
        @attributes = attributes
      end
    end
  end
end
