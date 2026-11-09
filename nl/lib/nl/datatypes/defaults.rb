module Nl
  module DataTypes
    module Defaults
      def nlattr_type_flags(_value = nil, context: nil)
        0
      end

      def coerce(value, context: nil)
        value
      end
    end
  end
end
