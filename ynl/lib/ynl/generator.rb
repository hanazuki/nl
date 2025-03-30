module Ynl
  class Generator
    module Refinements
      WORD_DELIM = /[ _-]+/

      refine(String) do
        def as_const_name
          split(WORD_DELIM).map(&:upcase).join('_')
        end

        def as_class_name
          split(WORD_DELIM).map(&:capitalize).join
        end

        def as_variable_name
          split(WORD_DELIM).join('_')
        end
        alias as_method_name as_variable_name

        def as_string_literal
          dump
        end

        def as_symbol_literal
          ":#{dump}"
        end
      end
    end
    private_constant :Refinements

    using Refinements

    def initialize(ynl, out)
      @ynl = ynl
      @out = out
      @indent = 0
    end

    def generate(superclass: '::Nl::Family', namespace: nil)
      classname = @ynl.name.as_class_name
      emit_class([*namespace, classname].join('::'), superclass) do
        write('NAME = ', @ynl.name.as_string_literal)
        write('PROTONUM = ', @ynl.protonum)

        if @ynl.protocol == 'netlink-raw'
          write('PROTOCOL = Ractor.make_shareable(::Nl::Protocols::Raw.new(', @ynl.name.as_string_literal, ', ', @ynl.protonum ,'))')
        else
          write('PROTOCOL = Ractor.make_shareable(::Nl::Protocols::Genl.new(', @ynl.name.as_string_literal, ')')
        end

        emit_module('Structs') do
          @ynl.structs.each do |name, struct|
            emit_comment(struct.doc)
            write(name.as_class_name, ' = Struct.new(', struct.members.map { it.name.as_variable_name.as_symbol_literal }.join(', ') ,')')
            emit_class(name.as_class_name) do
              write('MEMBERS = Ractor.make_shareable({', struct.members.map { "#{it.name.as_variable_name}: #{to_datatype(it.type, nil)}" }.join(', ') ,'})')
              write('def self.decode(decoder)')
              indent do
                write('self.new(*MEMBERS.map {|name, datatype| datatype.decode(decoder) })')
              end
              write('end')

              write('def encode(encoder)')
              indent do
                write('MEMBERS.each {|name, datatype| datatype.encode(encoder, self.public_send(name)) }')
              end
              write('end')
            end
          end
        end

        emit_module('AttributeSets') do
          @ynl.attribute_sets.each do |name, attr_set|
            emit_comment(attr_set.doc)
            emit_class(name.as_class_name, '::Nl::Family::AttributeSet') do
              emit_comment("Abstract class")
              emit_class('Attribute', '::Nl::Family::AttributeSet::Attribute') do
              end
              attr_set.attributes.each do |attr|
                emit_comment(attr.doc)
                emit_class(attr.name.as_class_name, 'Attribute') do
                  write('TYPE = ', attr.value)
                  write('DATATYPE = ', to_datatype(attr.type, attr.checks))
                end
              end

              write('BY_NAME = Ractor.make_shareable({', attr_set.attributes.map { "#{it.name.as_variable_name.as_symbol_literal} => #{it.name.as_class_name}" }.join(', ') ,'})')
              write('BY_TYPE = Ractor.make_shareable({', attr_set.attributes.map { "#{it.value} => #{it.name.as_class_name}" }.join(', ') ,'})')

              emit_singleton_class do
                emit_rbs_comment(
                  'name: Symbol',
                  'return: Attribute',
                )
                write('def by_name(name) = BY_NAME[name]')

                emit_rbs_comment(
                  'type: Integer',
                  'return: Attribute',
                )
                write('def by_type(type) = BY_TYPE[type]')
              end
            end
          end
        end

        emit_module('Messages') do
          @ynl.operations.each do |name, oper|
            emit_comment(oper.doc)
            %w[do dump].each do |method|
              if request_reply = oper.public_send(method + 'it')
                %w[request reply].to_h { [it, request_reply.public_send(it)] }.compact.each do |type, msg|
                  emit_class(method.as_class_name + oper.name.as_class_name + type.as_class_name, '::Nl::Family::Message') do
                    write('TYPE = ', msg.value)
                    write('FIXED_HEADER = ', oper.fixed_header&.then { 'Structs::' + it.name.as_class_name } || 'nil')
                    write('ATTRIBUTE_SET = AttributeSets::', oper.attribute_set.name.as_class_name)
                    params = msg.attributes
                    header_params = params & (oper.fixed_header&.members&.map(&:name) || [])
                    attribute_params = params & (oper.attribute_set.attributes.map(&:name))
                    write('HEADER_PARAMS = Ractor.make_shareable(%i[', header_params.map { it.as_variable_name }.join(' ') ,'])')
                    write('ATTRIBUTE_PARAMS = Ractor.make_shareable(%i[', attribute_params.map { it.as_variable_name }.join(' ') ,'])')
                  end
                end
              end
            end
          end
        end

        # emit request methods
        @ynl.operations.each do |name, oper|
          %w[do dump].each do |method|
            if request_reply = oper.public_send(method + 'it')
              emit_comment(oper.doc)
              write('def ', method.as_method_name, '_', oper.name.as_method_name, '(**args)')
              indent do
                request_class = "Messages::#{method.as_class_name}#{oper.name.as_class_name}Request"
                if request_reply.reply
                  reply_class = "Messages::#{method.as_class_name}#{oper.name.as_class_name}Reply"
                else
                  reply_class = 'nil'
                end
                write("exchange_message(#{method.as_symbol_literal}, #{request_class}, #{reply_class}, args)")
              end
              write('end')
            end
          end
        end
      end

      classname
    end

    INDENT = -'  '
    NEWLINE = -?\n
    private_constant :INDENT, :NEWLINE

    private def write(*str)
      @out.write(INDENT * @indent, *str, NEWLINE)
    end

    private def indent
      @indent += 1
      yield
    ensure
      @indent -= 1
    end

    private def emit_module(name)
      write('module ', name)
      indent { yield }
      write('end')
    end

    private def emit_class(name, superclass = nil)
      if superclass
        write('class ', name, ' < ', superclass)
      else
        write('class ', name)
      end
      indent { yield }
      write('end')
    end

    private def emit_singleton_class
      write('class << self')
      indent { yield }
      write('end')
    end

    private def emit_comment(comment)
      return unless comment
      comment.each_line do |line|
        write('# ', line)
      end
    end

    private def emit_rbs_comment(*args)
      args.each do |arg|
        write('# @rbs ', arg)
      end
    end

    private def to_datatype(type, checks)
      case type
      when Types::Pad
        'nil'
      when Types::Scalar
        "PROTOCOL.class::DataTypes::Scalar.new(::Nl::Endian::#{type.byte_order.name.as_class_name}::#{type.type.as_class_name}, check: #{to_checks(checks)})"
      when Types::String
        "PROTOCOL.class::DataTypes::String.new(check: #{to_checks(checks)})"
      when Types::Binary
        # if type.struct
        #   "Structs::" + type.struct.name.as_class_name
        # else
        "PROTOCOL.class::DataTypes::Binary.new(check: #{to_checks(checks)})"
        # end
      when Types::NestedAttributes
        "PROTOCOL.class::DataTypes::NestedAttributes.new(#{type.attribute_set.name.as_class_name})"
      else
        raise "Unknown type: #{type.class}"
      end
    end

    private def to_checks(checks)
      return 'nil' if !checks || checks.empty?
      %Q{-> { #{checks.join('; ')} }}
    end
  end
end
