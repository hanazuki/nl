require_relative 'base'
require_relative '../decoder'

module Nl
  module DataTypes
    class Scalar < Base
      def self.[](type)
        SPECIALIZATIONS.fetch(type)
      end

      SPECIALIZATIONS = Decoder::VALUE_READERS.to_h do |type, reader|
        specialization = Class.new(self)
        const_set("Type_#{type}", specialization)
        specialization.class_eval <<~RUBY, __FILE__, __LINE__ + 1
          def encode(encoder, value, context: nil)
            encoder.put_value(#{type.inspect}, checked(value || 0))
          end

          def decode(decoder, context: nil, nlattr_type_flags: 0)
            checked(decoder.#{reader})
          end
        RUBY
        [type, specialization]
      end.freeze
      private_constant :SPECIALIZATIONS
    end
  end
end
