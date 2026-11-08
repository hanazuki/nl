module Nl
  module DataTypes
    class Base
      def initialize(check: nil)
        @check = check
      end

      def nlattr_type_flags(_value = nil, context: nil)
        0
      end

      def coerce(value, context: nil)
        value
      end

      private def checked(value)
        @check&.call(value)
        value
      end
    end
  end
end
