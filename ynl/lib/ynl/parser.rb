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
      doc = translate_doc(@yaml['doc'])

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
        when 'unified', nil
          :unified
        else
          raise ParseError, "Unknown enum model: #{operations['enum-model']}"
        end
        @default_fixed_header = operations['fixed-header']&.then { @structs.fetch(it) }

        if enum_model == :unified
          counter = 0
          operations['list']&.each do |d|
            counter = d['value'] || (counter + 1)
            parse_operation(d, request_id: counter, reply_id: counter)
          end
        else
          request_counter = 1
          reply_counter = 1
          operations['list']&.each do |d|
            if d.key?('notify') || d.key?('event')
              reply_counter = d['value'] || reply_counter
              parse_operation(d, request_id: nil, reply_id: reply_counter)
              reply_counter += 1
            else
              primary = d['do'] || d['dump']
              request_counter = primary&.dig('request', 'value') || request_counter
              request_id = request_counter
              request_counter += 1
              if primary&.key?('reply')
                reply_counter = primary.dig('reply', 'value') || reply_counter
                reply_id = reply_counter
                reply_counter += 1
              else
                reply_id = nil
              end
              parse_operation(d, request_id:, reply_id:)
            end
          end
        end
      end
      @yaml.dig('mcast-groups', 'list')&.each do |d|
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

    private def parse_const(d)
      name = "#{d['name-prefix']}#{d.fetch('name')}"
      value = d.fetch('value')
      unless value.is_a?(Integer) || value.is_a?(String)
        raise ParseError, "Constant value must be a string or an integer: #{name}"
      end

      Models::Const.new(name, value, translate_doc(d['doc']))
    end

    private def parse_enum_flags(d, type:)
      cls = type == :enum ? Models::Enum : Models::Flags
      result = cls.new(name: d.fetch('name'), doc: translate_doc(d['doc']))

      start_value = d['start-value'] || 0
      value = type == :enum ? start_value : 1 << start_value

      d.fetch('entries').each do |v|
        case v
        when String
          entry = cls::Entry.new(name: v, value:)
        when Hash
          entry = cls::Entry.new(name: v.fetch('name'), value:, doc: translate_doc(v['doc']))
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
      when 'u8', 'u16', 'u32', 'u64', 's8', 's16', 's32', 's64', 'int', 'uint', 'sint'
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
      when 'indexed-array'
        Types::IndexedArray.new(
          sub_type: parse_indexed_array_sub_type(d),
        )
      when 'nest-type-value'
        if d['nested-attributes']
          Types::NestTypeValue.new(
            attribute_set: Models::Thunk.new {|f| f.attribute_sets.fetch(d.fetch('nested-attributes')) },
            type_values: d.fetch('type-value'),
          )
        else
          Types::Binary.new(struct: nil, display_hint: nil)
        end
      when 'sub-message'
        Types::SubMessage.new(
          sub_message: Models::Thunk.new {|f| f.sub_messages.fetch(d.fetch('sub-message')) },
          selector: d.fetch('selector'),
        )
      when 'pad'
        Types::Pad.new(
          length: nil,
        )
      when 'flag'
        Types::Flag.new
      when 'bitfield32'
        Types::Bitfield32.new
      when 'unused'
        nil
      else
        raise ParseError, "Unknown type: #{type}"
      end
    end

    private def parse_indexed_array_sub_type(d)
      sub_type = d.fetch('sub-type')
      case sub_type
      when 'u8', 'u16', 'u32', 'u64', 's8', 's16', 's32', 's64', 'int', 'uint', 'sint'
        Types::Scalar.new(
          type: sub_type,
          byte_order: parse_byte_order(d['byte-order']),
        )
      when 'binary'
        Types::Binary.new(
          struct: nil,
          display_hint: d['display-hint'],
        )
      when 'nest'
        Types::NestedAttributes.new(
          attribute_set: Models::Thunk.new {|f| f.attribute_sets.fetch(d.fetch('nested-attributes')) },
        )
      else
        raise ParseError, "Unknown indexed-array sub-type: #{sub_type}"
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
      result = Models::Struct.new(name: d.fetch('name'), doc: translate_doc(d['doc']))

      d.fetch('members').each do |v|
        type = parse_struct_member_type(v)
        member = Models::Struct::Member.new(name: v.fetch('name'), type: type, doc: translate_doc(v['doc']))
        result.members << member
      rescue
        raise ParseError, "Failed to parse struct member: #{v.fetch('name')}"
      end

      result
    rescue
      raise ParseError, "Failed to parse struct: #{d.fetch('name')}"
    end

    private def parse_checks(d)
      d.filter_map do |op, value|
        parse_check(op, value)
      end
    rescue
      raise ParseError, "Failed to parse checks"
    end

    private def parse_check(op, value_literal)
      case op
      when 'max', 'min', 'min-len', 'max-len', 'exact-len'
        Models::Check.new(operation: op, value: parse_value(value_literal))
      when 'unterminated-ok'
        return nil
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
      when String
        const = @consts[v] or raise ParseError, "Unknown value: #{v}"
        const
      else
        raise ParseError, "Unknown value: #{v}"
      end
    end

    private def parse_attribute_set(d)
      name = d.fetch('name')
      if subset_of = d['subset-of']
        superset = @attribute_sets.fetch(subset_of)
        result = Models::AttributeSubset.new(name:, superset:, attributes: d.fetch('attributes'), doc: translate_doc(d['doc']))
      else
        name_prefix = d['name_prefix']
        result = Models::AttributeSet.new(name:, name_prefix:, doc: translate_doc(d['doc']))
        value = 0

        d.fetch('attributes').each do |v|
          value = v.fetch('value', value + 1)
          if type = parse_attribute_type(v)
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
      name = d.fetch('name')
      result = Models::SubMessage.new(name:)
      d.fetch('formats', []).each do |fmt|
        attr_set = fmt['attribute-set']&.then { @attribute_sets[it] }
        result.formats << Models::SubMessage::Format.new(fmt['value'], attr_set)
      end
      @sub_messages[name] = result
    end

    private def parse_operation(d, request_id:, reply_id:)
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

      doit = d['do']&.then { parse_request_reply(it, default_request_id: request_id, default_reply_id: reply_id) }
      dumpit = d['dump']&.then { parse_request_reply(it, default_request_id: request_id, default_reply_id: reply_id) }
      notification = parse_notification(d, default_id: reply_id)

      @operations[name] = Models::Operation.new(
        name:, doc: translate_doc(d['doc']), flags: d.fetch('flags', []), fixed_header:, attribute_set:,
        doit:, dumpit:, notification:,
      )
    end

    private def parse_notification(d, default_id:)
      if source = d['notify']
        Models::Notification.new(
          kind: :notify,
          message: parse_message({}, default_id:),
          source:,
          group: d['mcgrp'],
        )
      elsif event = d['event']
        Models::Notification.new(
          kind: :event,
          message: parse_message(event, default_id:),
          source: nil,
          group: d['mcgrp'],
        )
      end
    end

    private def parse_request_reply(d, default_request_id:, default_reply_id:)
      Models::RequestReply.new(
        request: parse_message(d.fetch('request', {}), default_id: default_request_id),
        reply: d['reply']&.then { parse_message(it, default_id: default_reply_id) },
      )
    end

    private def parse_message(d, default_id:)
      Models::Message.new(value: d['value'] || default_id, attributes: d.fetch('attributes', []))
    end

    private def parse_mcast_group(d)
      name = d.fetch('name')
      @mcast_groups[name] = Models::McastGroup.new(
        name,
        d['value'],
        translate_doc(d['doc']),
      )
    end

    private def translate_doc(doc)
      return unless doc

      doc.gsub(/(?:\s|^)\K@(?<ident>[\w.-]+)/i) { "`#{$~[:ident]}`" }
    end
  end
end
