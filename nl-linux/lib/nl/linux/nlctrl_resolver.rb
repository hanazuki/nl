# frozen_string_literal: true
# rbs_inline: enabled

require 'nl/linux/nlctrl'

module Nl
  module Linux
    # Resolves Generic Netlink family metadata through nlctrl.
    class NlctrlResolver
      #--
      # @rbs connection: ::Nl::Genl::Connection
      # @rbs name: String
      # @rbs return: ::Nl::Genl::FamilyInfo
      def call(connection, name)
        if name == Nlctrl::NAME
          return Nl::Genl::FamilyInfo.new(
            id: Nl::Genl::GENL_ID_CTRL,
            multicast_groups: {}.freeze,
          )
        end

        reply = connection.family(Nlctrl).do_getfamily(family_name: name)
        groups = (reply.mcast_groups || []).to_h do |attributes|
          [attributes[:name].value, attributes[:id].value]
        end
        Nl::Genl::FamilyInfo.new(id: reply.family_id, multicast_groups: groups.freeze)
      end
    end

    DEFAULT_RESOLVER = NlctrlResolver.new.freeze
  end
end
