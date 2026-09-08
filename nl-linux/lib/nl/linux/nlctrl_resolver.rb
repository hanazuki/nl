require 'nl/linux/nlctrl'

module Nl
  module Linux
    # Resolves Generic Netlink family metadata through nlctrl.
    class NlctrlResolver
      FAMILY_INFO_CTRL = Nl::Genl::FamilyInfo.new(
        id: Genl::GENL_ID_CTRL,
        multicast_groups: {}.freeze,
      ).freeze

      # Resolves a Generic Netlink family metadata through nlctrl.
      #
      # @param [Genl::Client] client
      # @param [String] family_name
      # @return [Genl::FamilyInfo]
      # @rbs (Genl::Client client, String family_name) -> Genl::FamilyInfo
      def call(client, family_name)
        return FAMILY_INFO_CTRL if family_name == Nlctrl::NAME

        reply = client.family(Nlctrl).do_getfamily(family_name:)
        groups = (reply.mcast_groups || []).to_h do |attributes|
          [attributes[:name].value, attributes[:id].value]
        end
        Genl::FamilyInfo.new(id: reply.family_id, multicast_groups: groups.freeze)
      end
    end

    DEFAULT_RESOLVER = NlctrlResolver.new.freeze
  end
end
