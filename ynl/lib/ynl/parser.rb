require 'yaml'

require_relative 'models'

module Ynl
  class Parser
    # @param [String, #read] source
    # @rbs (String | _Readable source) -> void
    def initialize(source)
      @document = YAML.load(source, aliases: true)
      @attribute_declarations = {}
      @attribute_definitions = {}
      @expanding_subsets = []
      @operation_values = []
    end

    # @param [String, #to_path] path
    # @return [Models::Family]
    # @rbs (String | _PathLike path) -> Models::Family
    def self.parse_file(path)
      File.open(path) {|f| new(f) }.parse
    end

    # Returns a complete, deeply frozen model graph.
    # @return [Models::Family]
    # @rbs () -> Models::Family
    def parse
      return @family if @family

      normalize
      @family = materialize
    end

    private def normalize
      @document.fetch('attribute-sets').each do |declaration|
        name = declaration.fetch('name')
        if @attribute_declarations.key?(name)
          raise ParseError, "Duplicate AttributeSet: #{name}"
        end
        @attribute_declarations[name] = declaration
      end
      @attribute_declarations.each_key { attribute_definitions(it) }
      if operations = @document['operations']
        enum_model = case operations['enum-model']
        when 'directional'
          :directional
        when 'unified', nil
          :unified
        else
          raise ParseError, "Unknown enum model: #{operations['enum-model']}"
        end

        if enum_model == :unified
          counter = 0
          operations['list']&.each do |d|
            counter = d['value'] || (counter + 1)
            @operation_values << [d, counter, counter]
          end
        else
          request_counter = 1
          reply_counter = 1
          operations['list']&.each do |d|
            if d.key?('notify') || d.key?('event')
              reply_counter = d['value'] || reply_counter
              @operation_values << [d, nil, reply_counter]
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
              @operation_values << [d, request_id, reply_id]
            end
          end
        end
      end
    end

    private def materialize
      @consts = {}
      @enums = {}
      @flags = {}
      @structs = {}
      @attribute_sets = {}
      @sub_messages = {}
      @operations = {}
      @mcast_groups = {}
      @operation_declarations = {}
      @building_operations = []
      @operation_values.each do |entry|
        name = entry.first.fetch('name')
        raise ParseError, "Duplicate Operation: #{name}" if @operation_declarations.key?(name)
        @operation_declarations[name] = entry
      end
      declare_models

      @document.fetch('definitions', []).each { build_definition(it) }
      @attribute_declarations.each_value { build_attribute_set(it) }
      @document.fetch('sub-messages', []).each { build_sub_message(it) }
      @document.dig('mcast-groups', 'list')&.each { build_mcast_group(it) }
      @default_fixed_header = @document.dig('operations', 'fixed-header')&.then do
        reference(@structs, it, 'struct')
      end
      # Construction may visit a notification source first; retain declaration
      # order in the exposed table and keep the previously assigned wire IDs.
      @operations = @operation_values.to_h do |declaration, request_id, reply_id|
        operation = build_operation(declaration, request_id:, reply_id:)
        [operation.name, operation]
      end

      Models::Family.new(
        name: @document['name']&.dedup, protocol: (@document['protocol'] || 'genetlink').dedup,
        version: @document.fetch('version', 1), protonum: @document['protonum'],
        doc: translate_doc(@document['doc']),
        consts: @consts.freeze, enums: @enums.freeze, flags: @flags.freeze, structs: @structs.freeze,
        attribute_sets: @attribute_sets.freeze, sub_messages: @sub_messages.freeze,
        operations: @operations.freeze, mcast_groups: @mcast_groups.freeze).freeze
    end

    # Establish identities through ordinary constructors. Their owned arrays
    # remain mutable until the corresponding members, attributes, or formats
    # have been built; references can already point to these models.
    private def declare_models
      @document.fetch('definitions', []).each do |d|
        next unless d['type'] == 'struct'
        register(@structs, Models::Struct.new(
          name: d.fetch('name').dedup, members: [], doc: translate_doc(d['doc'])).freeze)
      end
      @attribute_sets = @attribute_declarations.to_h do |name, _|
        [name, declare_attribute_set(name)]
      end
      @document.fetch('sub-messages', []).each do |d|
        register(@sub_messages, Models::SubMessage.new(
          name: d.fetch('name').dedup, formats: []).freeze)
      end
    end

    private def declare_attribute_set(name)
      return @attribute_sets.fetch(name) if @attribute_sets.key?(name)

      d = reference(@attribute_declarations, name, 'attribute set')
      model = if parent = d['subset-of']
        Models::AttributeSubset.new(
          name: name.dedup, superset: declare_attribute_set(parent),
          attributes: [], doc: translate_doc(d['doc']))
      else
        Models::AttributeSet.new(
          name: name.dedup, name_prefix: d['name_prefix']&.dedup,
          attributes: [], doc: translate_doc(d['doc']))
      end
      @attribute_sets[name] = model.freeze
    end

    private def register(table, model)
      if table.key?(model.name)
        raise ParseError, "Duplicate #{model.class.name.split('::').last}: #{model.name}"
      end
      table[model.name] = model
    end

    private def reference(table, name, kind)
      table.fetch(name) { raise ParseError, "Unknown #{kind}: #{name}" }
    end

    private def find_type(name)
      @enums[name] || @flags[name] || @structs[name] || raise(ParseError, "Unknown type: #{name}")
    end

    private def build_definition(d)
      case type = d.fetch('type')
      when 'const'
        v = build_const(d)
        @consts[v.name] = v
      when 'enum'
        v = build_enum_flags(d, type: :enum)
        reject_enum_flags_name_collision(v.name, @flags)
        @enums[v.name] = v
      when 'flags'
        v = build_enum_flags(d, type: :flags)
        reject_enum_flags_name_collision(v.name, @enums)
        @flags[v.name] = v
      when 'struct'
        build_struct(d)
      else
        raise ParseError, "Unknown definition type: #{type}"
      end
    end

    private def reject_enum_flags_name_collision(name, other_definitions)
      return unless other_definitions.key?(name)

      raise ParseError, "Definition #{name.inspect} cannot be both an enum and flags"
    end

    private def build_const(d)
      name = "#{d['name-prefix']}#{d.fetch('name')}".dedup
      literal = d.fetch('value')
      value = case literal
      when String
        literal.dedup
      when Integer
        literal
      else
        raise ParseError, "Constant value must be a string or an integer: #{name}"
      end

      Models::Const.new(name:, value:, doc: translate_doc(d['doc'])).freeze
    end

    private def build_enum_flags(d, type:)
      cls = type == :enum ? Models::Enum : Models::Flags
      start_value = d['value-start'] || 0
      raw_value = start_value

      entries = d.fetch('entries').map do |v|
        explicit_value = v.is_a?(Hash) ? v['value'] : nil
        raw_value = explicit_value unless explicit_value.nil?
        value = type == :enum ? raw_value : 1 << raw_value
        case v
        when String
          entry = cls::Entry.new(name: v.dedup, value:).freeze
        when Hash
          entry = cls::Entry.new(name: v.fetch('name').dedup, value:, doc: translate_doc(v['doc'])).freeze
        else
          raise ParseError, "Unknown class for enum/flags entry: #{v.class}"
        end

        raw_value += 1
        entry

      rescue
        raise ParseError, "Failed to parse enum/flags entry: #{v.fetch('name')}"
      end

      cls.new(name: d.fetch('name').dedup, entries: entries.freeze, doc: translate_doc(d['doc'])).freeze
    rescue
      raise ParseError, "Failed to parse enum/flags: #{d.fetch('name')}"
    end

    private def build_struct_member_type(d)
      length = d['len']
      length = length.dedup if length.is_a?(String)
      type = d.fetch('type')
      case type
      when 'u8', 'u16', 'u32', 'u64', 's8', 's16', 's32', 's64', 'int', 'uint'
        Types::Scalar.new(
          type: type.dedup,
          byte_order: build_byte_order(d['byte-order']),
        ).freeze
      when 'binary'
        Types::Binary.new(
          struct: d['struct'] ? reference(@structs, d.fetch('struct'), 'struct') : nil,
          length: length,
          display_hint: d['display-hint']&.dedup,
        ).freeze
      when 'pad'
        Types::Pad.new(
          length: length,
        ).freeze
      else
        fail "Unknown type: #{type}"
      end
    end

    private def build_attribute_type(d)
      type = d.fetch('type')
      case type
      when 'u8', 'u16', 'u32', 'u64', 's8', 's16', 's32', 's64', 'int', 'uint', 'sint'
        Types::Scalar.new(
          type: type.dedup,
          byte_order: build_byte_order(d['byte-order']),
        ).freeze
      when 'binary'
        if d.key?('sub-type')
          Types::PackedArray.new(sub_type: build_packed_array_sub_type(d)).freeze
        else
          Types::Binary.new(
            struct: d['struct'] ? reference(@structs, d.fetch('struct'), 'struct') : nil,
            length: nil,
            display_hint: d['display-hint']&.dedup,
          ).freeze
        end
      when 'string'
        Types::String.new.freeze
      when 'nest'
        Types::NestedAttributes.new(
          attribute_set: reference(@attribute_sets, d.fetch('nested-attributes'), 'attribute set'),
        ).freeze
      when 'indexed-array'
        Types::IndexedArray.new(
          sub_type: build_indexed_array_sub_type(d),
        ).freeze
      when 'nest-type-value'
        if d['nested-attributes']
          type_values = d.fetch('type-value')
          type_values.map!(&:dedup).freeze unless type_values.frozen?
          Types::NestTypeValue.new(
            attribute_set: reference(@attribute_sets, d.fetch('nested-attributes'), 'attribute set'),
            type_values:,
          ).freeze
        else
          Types::Binary.new(struct: nil, length: nil, display_hint: nil).freeze
        end
      when 'sub-message'
        Types::SubMessage.new(
          sub_message: reference(@sub_messages, d.fetch('sub-message'), 'sub-message'),
          selector: d.fetch('selector').dedup,
        ).freeze
      when 'pad'
        Types::Pad.new(
          length: nil,
        ).freeze
      when 'flag'
        Types::Flag.new.freeze
      when 'bitfield32'
        Types::Bitfield32.new.freeze
      when 'unused'
        nil
      else
        raise ParseError, "Unknown type: #{type}"
      end
    end

    private def build_indexed_array_sub_type(d)
      sub_type = d.fetch('sub-type')
      case sub_type
      when 'u8', 'u16', 'u32', 'u64', 's8', 's16', 's32', 's64', 'int', 'uint', 'sint'
        Types::Scalar.new(
          type: sub_type.dedup,
          byte_order: build_byte_order(d['byte-order']),
        ).freeze
      when 'binary'
        Types::Binary.new(
          struct: nil,
          length: nil,
          display_hint: d['display-hint']&.dedup,
        ).freeze
      when 'nest'
        Types::NestedAttributes.new(
          attribute_set: reference(@attribute_sets, d.fetch('nested-attributes'), 'attribute set'),
        ).freeze
      else
        raise ParseError, "Unknown indexed-array sub-type: #{sub_type}"
      end
    end

    private def build_packed_array_sub_type(d)
      sub_type = d.fetch('sub-type')
      case sub_type
      when 'u8', 'u16', 'u32', 'u64', 's8', 's16', 's32', 's64', 'int'
        Types::Scalar.new(
          type: sub_type.dedup,
          byte_order: build_byte_order(d['byte-order']),
        ).freeze
      else
        raise ParseError, "Unknown packed-array sub-type: #{sub_type}"
      end
    end

    private def build_byte_order(v)
      case v
      when nil
        :host
      when 'big-endian'
        :big
      when 'little-endian'
        :little
      else
        raise ParseError, "Unknown endian: #{v}"
      end
    end

    private def build_struct(d)
      model = @structs.fetch(d.fetch('name'))
      d.fetch('members').each do |member|
        model.members << Models::Struct::Member.new(
          name: member.fetch('name').dedup, type: build_struct_member_type(member),
          doc: translate_doc(member['doc'])).freeze
      rescue => error
        raise ParseError, "Failed to parse struct member #{member.fetch('name')}: #{error.message}"
      end
      model.members.freeze
      model
    rescue => error
      raise ParseError, "Failed to parse struct #{d.fetch('name')}: #{error.message}"
    end

    private def build_checks(d)
      d.filter_map do |op, value|
        build_check(op, value)
      end.freeze
    rescue
      raise ParseError, "Failed to parse checks"
    end

    private def build_check(op, value_literal)
      case op
      when 'max', 'min', 'min-len', 'max-len', 'exact-len'
        Models::Check.new(operation: op.dedup, value: build_value(value_literal)).freeze
      when 'unterminated-ok'
        return nil
      else
        raise ParseError, "Unknown check: #{op}"
      end
    rescue
      raise ParseError, "Failed to parse check: #{op}"
    end

    private def build_value(v)
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

    # Subsets depend on their parent's normalized contents, unlike ordinary
    # references, which only need the target's identity. Expand that dependency
    # separately so forward subsets work and inheritance cycles fail clearly.
    private def attribute_definitions(name)
      return @attribute_definitions.fetch(name) if @attribute_definitions.key?(name)
      if @expanding_subsets.include?(name)
        chain = (@expanding_subsets + [name]).join(' -> ')
        raise ParseError, "Attribute subset inheritance cycle: #{chain}"
      end
      d = reference(@attribute_declarations, name, 'attribute set')
      @expanding_subsets << name
      begin
        definitions = if parent_name = d['subset-of']
          inherited = attribute_definitions(parent_name).to_h { [it.fetch('name'), it] }
          d.fetch('attributes').uniq { it.fetch('name') }.map do |override|
            parent = inherited.fetch(override.fetch('name'))
            parent.merge(override).merge('value' => parent.fetch('value'))
          end
        else
          value = 0
          d.fetch('attributes').map do |attribute|
            value = attribute.fetch('value', value + 1)
            attribute.merge('value' => value)
          end
        end
        @attribute_definitions[name] = definitions
      ensure
        @expanding_subsets.pop
      end
    end

    private def build_attribute_set(d)
      name = d.fetch('name')
      model = @attribute_sets.fetch(name)
      attribute_definitions(name).each do |definition|
        attribute = build_attribute(definition)
        model.attributes << attribute if attribute
      end
      model.attributes.freeze
      model
    rescue => error
      raise ParseError, "Failed to parse attribute set #{d.fetch('name')}: #{error.message}"
    end

    private def build_attribute(d)
      multi_attr = d.fetch('multi-attr', false)
      unless multi_attr == true || multi_attr == false
        raise ParseError, "multi-attr must be a boolean"
      end

      enum_as_flags = d.fetch('enum-as-flags', false)
      unless enum_as_flags == true || enum_as_flags == false
        raise ParseError, "enum-as-flags must be a boolean"
      end
      if enum_as_flags && !d['enum']
        raise ParseError, "enum-as-flags requires enum"
      end

      return unless type = build_attribute_type(d)

      Models::AttributeSet::Attribute.new(
        name: d.fetch('name').dedup,
        type:,
        value: d.fetch('value'),
        checks: (build_checks(d['checks']) if d['checks']),
        doc: translate_doc(d['doc']),
        multi_attr:,
        enum: d['enum']&.then { find_type(it) },
        enum_as_flags:,
      ).freeze
    rescue => error
      raise ParseError, "Failed to parse attribute #{d.fetch('name')}: #{error.message}"
    end

    private def build_sub_message(d)
      model = @sub_messages.fetch(d.fetch('name'))
      d.fetch('formats', []).each do |format|
        model.formats << Models::SubMessage::Format.new(
          value: format.fetch('value').dedup,
          fixed_header: format['fixed-header']&.then { reference(@structs, it, 'struct') },
          attribute_set: format['attribute-set']&.then { reference(@attribute_sets, it, 'attribute set') }).freeze
      end
      model.formats.freeze
      model
    end

    private def build_operation(d, request_id:, reply_id:)
      name = d.fetch('name').dedup
      return @operations.fetch(name) if @operations.key?(name)
      if @building_operations.include?(name)
        chain = (@building_operations + [name]).join(' -> ')
        raise ParseError, "Notification source cycle: #{chain}"
      end

      @building_operations << name
      begin
        fixed_header = d['fixed-header']&.then do
          reference(@structs, it, 'struct')
        end || @default_fixed_header
        attribute_set = d['attribute-set']&.then do
          reference(@attribute_sets, it, 'attribute set')
        end

        doit = d['do']&.then { build_request_reply(it, default_request_id: request_id, default_reply_id: reply_id) }
        dumpit = d['dump']&.then { build_request_reply(it, default_request_id: request_id, default_reply_id: reply_id) }
        notification = build_notification(d, default_id: reply_id)
        flags = d.fetch('flags', [])
        flags.map!(&:dedup).freeze unless flags.frozen?

        @operations[name] = Models::Operation.new(
          name:, doc: translate_doc(d['doc']), flags:,
          fixed_header:, attribute_set:, doit:, dumpit:, notification:,
        ).freeze
      ensure
        @building_operations.pop
      end
    end

    private def build_notification(d, default_id:)
      if source = d['notify']
        declaration, request_id, reply_id = reference(@operation_declarations, source, 'operation')
        source_operation = build_operation(declaration, request_id:, reply_id:)
        Models::Notification.new(
          kind: :notify,
          message: build_message({}, default_id:),
          source: source_operation,
          group: d['mcgrp']&.then { reference(@mcast_groups, it, 'multicast group') },
        ).freeze
      elsif event = d['event']
        Models::Notification.new(
          kind: :event,
          message: build_message(event, default_id:),
          source: nil,
          group: d['mcgrp']&.then { reference(@mcast_groups, it, 'multicast group') },
        ).freeze
      end
    end

    private def build_request_reply(d, default_request_id:, default_reply_id:)
      Models::RequestReply.new(
        request: build_message(d.fetch('request', {}), default_id: default_request_id),
        reply: d['reply']&.then { build_message(it, default_id: default_reply_id) },
      ).freeze
    end

    private def build_message(d, default_id:)
      attributes = d.fetch('attributes', [])
      attributes.map!(&:dedup).freeze unless attributes.frozen?
      Models::Message.new(value: d['value'] || default_id, attributes:).freeze
    end

    private def build_mcast_group(d)
      name = d.fetch('name').dedup
      @mcast_groups[name] = Models::McastGroup.new(
        name:, value: d['value'], doc: translate_doc(d['doc']),
      ).freeze
    end

    private def translate_doc(doc)
      return unless doc

      doc.gsub(/(?:\s|^)\K@(?<ident>[\w.-]+)/i) { "`#{$~[:ident]}`" }.dedup
    end
  end
end
