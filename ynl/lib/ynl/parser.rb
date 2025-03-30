require 'yaml'

require_relative 'models'

module Ynl
  class Parser
    def initialize(source)
      @yaml = YAML.load(source, aliases: true)

      @consts = {}
      @flags = {}
      @enums = {}
      @structs = {}

      @attribute_sets = {}
      @sub_messages = {}
      @operations = {}
      @mcast_groups = {}
    end

    def self.parse_file(path)
      File.open(path) {|f| new(f) }.parse
    end

    def parse
      protocol = @yaml['protocol'] || 'genetlink'
      protonum = @yaml['protonum']
      name = @yaml['name']
      doc = @yaml['doc']

      @yaml['definitions']&.each do |d|
        parse_definition(d)
      end
      @yaml['attribute-sets'].each do |d|
        parse_attribute_set(d)
      end
      @yaml['sub-messages']&.each do |d|
        parse_sub_message(d)
      end
      if operations = @yaml['operations']
        enum_model = case operations['enum-model']
        when 'directional'
          :directional
        when nil
          :unidirectional
        else
          raise ParseError, "Unknown enum model: #{operations['enum-model']}"
        end
        @default_fixed_header = operations['fixed-header']&.then { @structs.fetch(it) }
        operations['list']&.each do |d|
          parse_operation(d, enum_model:)
        end
      end
      @yaml['mcast-groups']&.each do |d|
        parse_mcast_group(d)
      end

      Models::Family.new(
        name:,
        protocol:,
        protonum:,
        doc:,
        consts: @consts,
        enums: @enums,
        flags: @flags,
        structs: @structs,
        attribute_sets: @attribute_sets,
        sub_messages: @sub_messages,
        operations: @operations,
        mcast_groups: @mcast_groups,
      ).resolve
    end

    private def parse_definition(d)
      case type = d.fetch('type')
      when 'const'
        v = parse_const(d)
        @consts[v.name] = v
      when 'enum'
        v = parse_enum_flags(d, type: :enum)
        @enums[v.name] = v
      when 'flags'
        v = parse_enum_flags(d, type: :flags)
        @flags[v.name] = v
      when 'struct'
        v = parse_struct(d)
        @structs[v.name] = v
      else
        raise ParseError, "Unknown definition type: #{type}"
      end
    end

    private def parse_enum_flags(d, type:)
      cls = type == :enum ? Models::Enum : Models::Flags
      result = cls.new(name: d.fetch('name'), doc: d['doc'])

      start_value = d['start-value'] || 0
      value = type == :enum ? start_value : 1 << start_value

      d.fetch('entries').each do |v|
        case v
        when String
          entry = cls::Entry.new(name: v, value:)
        when Hash
          entry = cls::Entry.new(name: v.fetch('name'), value:, doc: v['doc'])
        else
          raise ParseError, "Unknown class for enum/flags entry: #{v.class}"
        end

        result.entries << entry

        value = type == :enum ? value + 1 : value << 1

      rescue
        raise ParseError, "Failed to parse enum/flags entry: #{v.fetch('name')}"
      end

      result
    rescue
      raise ParseError, "Failed to parse enum/flags: #{d.fetch('name')}"
    end

    private def parse_struct_member_type(d)
      type = d.fetch('type')
      case type
      when 'u8', 'u16', 'u32', 'u64', 's8', 's16', 's32', 's64', 'int', 'uint'
        Types::Scalar.new(
          type: type,
          byte_order: parse_byte_order(d['byte-order']),
        )
      when 'binary'
        Types::Binary.new(
          struct: d['struct'] ? Models::Thunk.new {|f| f.structs.fetch(d['struct']) } : nil,
          display_hint: d['display-hint'],
        )
      when 'pad'
        Types::Pad.new(
          length: d['len'],
        )
      else
        fail "Unknown type: #{type}"
      end
    end

    private def parse_attribute_type(d)
      type = d.fetch('type')
      case type
      when 'u8', 'u16', 'u32', 'u64', 's8', 's16', 's32', 's64', 'int', 'uint'
        Types::Scalar.new(
          type: type,
          byte_order: parse_byte_order(d['byte-order']),
        )
      when 'binary'
        Types::Binary.new(
          struct: d['struct'] ? Models::Thunk.new {|f| f.structs.fetch(d.fetch('struct')) } : nil,
          display_hint: d['display-hint'],
        )
      when 'string'
        Types::String.new
      when 'nest'
        Types::NestedAttributes.new(
          attribute_set: Models::Thunk.new {|f| f.attribute_sets.fetch(d.fetch('nested-attributes')) },
        )
      when 'sub-message'
        Types::SubMessage.new(
          sub_message: Models::Thunk.new {|f| f.sub_messages.fetch(d.fetch('sub-message')) },
          selector: d.fetch('selector'),
        )
      when 'pad'
        Types::Pad.new(
          length: nil,
        )
      when 'unused'
        nil
      else
        raise ParseError, "Unknown type: #{type}"
      end
    end

    private def parse_byte_order(v)
      case v
      when nil
        :host
      when 'big-endian'
        :big
      when 'litten-endian'
        :little
      else
        raise ParseError, "Unknown endian: #{v}"
      end
    end

    private def parse_struct(d)
      result = Models::Struct.new(name: d.fetch('name'), doc: d['doc'])

      d.fetch('members').each do |v|
        type = parse_struct_member_type(v)
        member = Models::Struct::Member.new(name: v.fetch('name'), type: type, doc: v['doc'])
        result.members << member
      rescue
        raise ParseError, "Failed to parse struct member: #{v.fetch('name')}"
      end

      result
    rescue
      raise ParseError, "Failed to parse struct: #{d.fetch('name')}"
    end

    private def parse_checks(d)
      d.map do |op, value|
        parse_check(op, value)
      end
    rescue
      raise ParseError, "Failed to parse checks"
    end

    private def parse_check(op, value_literal)
      case op
      when 'max'
        value = parse_value(value_literal)
        return %{raise unless it <= #{value}}
      when 'min'
        value = parse_value(value_literal)
        return %{raise unless it >= #{value}}
      when 'min-len'
        value = parse_value(value_literal)
        return %{raise unless it.bytesize >= #{value}}
      when 'max-len'
        value = parse_value(value_literal)
        return %{raise unless it.bytesize <= #{value}}
      else
        raise ParseError, "Unknown check: #{op}"
      end
    rescue
      raise ParseError, "Failed to parse check: #{op}"
    end

    private def parse_value(v)
      case v
      when Integer
        v
      when 'u32-max'
        (2 ** 32) - 1
      when 's32-max'
        (2 ** 31) - 1
      else
        raise ParseError, "Unknown value: #{v}"
      end
    end

    private def parse_attribute_set(d)
      name = d.fetch('name')
      if subset_of = d['subset-of']
        result = Models::Thunk.new do |f|
          superset = f.attribute_sets.fetch(subset_of)
          attribute_set = Models::AttributeSet.new(name:, name_prefix: superset.name_prefix, doc: d['doc'])
          d.fetch('attributes').each do |v|
            aname = v.fetch('name')
            sattr = superset.attributes.find {|a| a.name == aname } or raise ParseError, "Attribute not found: #{aname}"
            # TODO: type/checks overrides
            attribute_set.attributes << sattr
          rescue
            raise ParseError, "Failed to parse attribute: #{v.fetch('name')}"
          end
          attribute_set
        end
      else
        name_prefix = d['name_prefix']
        result = Models::AttributeSet.new(name:, name_prefix:, doc: d['doc'])
        value = 0

        d.fetch('attributes').each do |v|
          if type = parse_attribute_type(v)
            value = v.fetch('value', value + 1)
            attribute = Models::AttributeSet::Attribute.new(name: v.fetch('name'), type: type, value:)
            result.attributes << attribute
            if checks = v['checks']
              attribute.checks = parse_checks(checks)
            end
          end
        rescue
          raise ParseError, "Failed to parse attribute: #{v.fetch('name')}"
        end
      end

      @attribute_sets[name] = result

    rescue
      raise ParseError, "Failed to parse attribute set: #{d.fetch('name')}"
    end

    private def parse_sub_message(d)
    end

    private def parse_operation(d, enum_model:)
      name = d.fetch('name')

      fixed_header = d['fixed-header']&.then do
        @structs.fetch(it)
      rescue
        raise ParseError, "Undefined fixed header: #{it}"
      end || @default_fixed_header

      attribute_set = d['attribute-set']&.then do
        @attribute_sets.fetch(it)
      rescue
        raise ParseError, "Undefined attribute set: #{it}"
      end

      doit = d['do']&.then { parse_request_reply(it) }
      dumpit = d['dump']&.then { parse_request_reply(it) }

      @operations[name] = Models::Operation.new(name:, doc: d['doc'], fixed_header:, attribute_set:, doit:, dumpit:)
    end

    private def parse_request_reply(d)
      Models::RequestReply.new(
        request: d['request']&.then { parse_message(it) },
        reply: d['reply']&.then { parse_message(it) },
      )
    end

    private def parse_message(d)
      Models::Message.new(value: d['value'], attributes: d.fetch('attributes', []))
    end

    private def parse_mcast_group(d)
    end
  end
end
