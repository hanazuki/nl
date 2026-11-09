require_relative 'defaults'
require_relative '../decoder'

module Nl
  module DataTypes
    module Scalar
      def self.[](type)
        SPECIALIZATIONS.fetch(type)
      end

      SPECIALIZATIONS = Decoder::VALUE_READERS.to_h do |type, reader|
        specialization = Class.new { include Defaults }
        const_set("Type_#{type}", specialization)
        specialization.class_eval <<~RUBY, __FILE__, __LINE__ + 1
          def encode(encoder, value, context: nil)
            encoder.put_value(#{type.inspect}, value)
          end

          def decode(decoder, context: nil, nlattr_type_flags: 0)
            decoder.#{reader}
          end
        RUBY
        [type, specialization]
      end.freeze
      private_constant :SPECIALIZATIONS
    end
  end
end
