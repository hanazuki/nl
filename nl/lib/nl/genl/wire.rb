# Generic Netlink wire definitions
#--
# rbs_inline: enabled

require_relative '../raw/wire'
require_relative '../endian'

module Nl
  module Genl
    module Constants
      # From include/uapi/linux/genetlink.
      GENL_NAMSIZ = 16
      GENL_MIN_ID = Raw::NLMSG_MIN_TYPE
      GENL_MAX_ID = 1023

      GENL_HDRLEN = 4

      GENL_ID_GENERATE = 0
      GENL_ID_CTRL = Raw::NLMSG_MIN_TYPE
      GENL_ID_VFS_DQUOT = Raw::NLMSG_MIN_TYPE + 1
      GENL_ID_PMCRAID = Raw::NLMSG_MIN_TYPE + 2

      CTRL_CMD_UNSPEC = 0
      CTRL_CMD_NEWFAMILY = 1
      CTRL_CMD_DELFAMILY = 2
      CTRL_CMD_GETFAMILY = 3
      CTRL_CMD_NEWOPS = 4
      CTRL_CMD_DELOPS = 5
      CTRL_CMD_GETOPS = 6
      CTRL_CMD_NEWMCAST_GRP = 7
      CTRL_CMD_DELMCAST_GRP = 8
      CTRL_CMD_GETMCAST_GRP = 9

      CTRL_ATTR_UNSPEC = 0
      CTRL_ATTR_FAMILY_ID = 1
      CTRL_ATTR_FAMILY_NAME = 2
      CTRL_ATTR_VERSION = 3
      CTRL_ATTR_HDRSIZE = 4
      CTRL_ATTR_MAXATTR = 5
      CTRL_ATTR_OPS = 6
      CTRL_ATTR_MCAST_GROUPS = 7

      CTRL_ATTR_OP_UNSPEC = 0
      CTRL_ATTR_OP_ID = 1
      CTRL_ATTR_OP_FLAGS = 2

      CTRL_ATTR_MCAST_GRP_UNSPEC = 0
      CTRL_ATTR_MCAST_GRP_NAME = 1
      CTRL_ATTR_MCAST_GRP_ID = 2
    end
    include Constants

    GenlMsgHdr = Struct.new(:cmd, :version, :reserved)
    # Generic Netlink message header
    class GenlMsgHdr
      FORMAT = Ractor.make_shareable([
        Endian::Host::U8,
        Endian::Host::U8,
        Endian::Host::U16,
      ])
      private_constant :FORMAT

      def self.decode(decoder)
        new(*decoder.get_values(FORMAT))
      end

      def encode(encoder)
        encoder.put_values(FORMAT, to_a)
      end
    end
  end
end
