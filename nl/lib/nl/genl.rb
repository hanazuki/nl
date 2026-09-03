# Generic Netlink family support
#--
# rbs_inline: enabled

require_relative 'genl/wire'
require_relative 'family'
require_relative 'genl/protocol'

module Nl
  module Genl
    class Family < Nl::Family
      #--
      # @rbs (resolver: ^(Client, ::String) -> FamilyInfo, ?executor: executor?, ?notification_capacity: Integer?) -> (Nl::Family::Session & instance)
      #  | [R] (resolver: ^(Client, ::String) -> FamilyInfo, ?executor: executor?, ?notification_capacity: Integer?) { (instance) -> R } -> R
      def self.open(resolver:, executor: nil, notification_capacity: DEFAULT_NOTIFICATION_CAPACITY)
        begin
          owner = Client.new(resolver:, executor:, notification_capacity:)
          session = owner.family(self).extend(Nl::Family::Session)
        rescue Exception
          owner&.close
          raise
        end
        return session unless block_given?

        begin
          yield session
        ensure
          session.close
        end
      end
    end
  end
end

require_relative 'genl/client'
