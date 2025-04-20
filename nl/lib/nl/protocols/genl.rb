module Nl
  module Protocols
    # The Generic Netlink protocol
      class Genl < Raw  # TODO: Implement
      def initialize(name)
        super(name, NETLINK_GENERIC)
      end

      def parse(buffer, offset)
        nlmsg = super(buffer, offset)
        genlmsg = GenlMsgHdr.parse(nlmsg.data, 0)
      end
    end
  end
end
