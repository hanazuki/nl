require 'nl/linux'

RSpec.describe do
  let(:resolver) do
    ->(socket, name) do
      Nl::Linux::Nlctrl.new(socket).do_getfamily(family_name: name).family_id
    end
  end

  describe Nl::Linux::RtLink do
    example 'do_getlink returns link info for loopback' do
      Nl::Linux::RtLink.open do |rtlink|
        reply = rtlink.do_getlink(ifi_index: 1)
        expect(reply).to be_a Nl::Linux::RtLink::Messages::DoGetlinkReply

        expect(reply.fixed_header.ifi_index).to eq 1
        expect(reply.ifname).to eq 'lo'
        expect(reply.fixed_header.ifi_type).to eq 772  # ARPHRD_LOOPBACK
      end
    end

    example 'dump_getlink returns link list including loopback' do
      Nl::Linux::RtLink.open do |rtlink|
        r = rtlink.dump_getlink
        expect(r).to be_an Array

        lo = r.find { it.ifname == 'lo' }
        expect(lo).to be_a Nl::Linux::RtLink::Messages::DumpGetlinkReply

        expect(lo.fixed_header.ifi_type).to eq 772  # ARPHRD_LOOPBACK
      end
    end

    example 'dump_getlink accepts block' do
      Nl::Linux::RtLink.open do |rtlink|
        r = []
        rtlink.dump_getlink do |m|
          expect(m).to be_a Nl::Linux::RtLink::Messages::DumpGetlinkReply
          r << m
        end
        expect(r).not_to be_empty
      end
    end

    example 'do_getstats returns 64-bit link stats for loopback' do
      link_64_filter = 1 << 0  # IFLA_STATS_LINK_64

      Nl::Linux::RtLink.open do |rtlink|
        reply = rtlink.do_getstats(ifindex: 1, filter_mask: link_64_filter)
        expect(reply).to be_a Nl::Linux::RtLink::Messages::DoGetstatsReply

        expect(reply.ifindex).to eq 1
        expect(reply.filter_mask).to eq link_64_filter
        expect(reply.link_64).not_to be_nil
      end
    end
  end

  describe Nl::Linux::RtAddr do
    example 'dump_getaddr returns address list including loopback' do
      Nl::Linux::RtAddr.open do |rtaddr|
        r = rtaddr.dump_getaddr
        expect(r).to be_an Array

        lo = r.find { it.label == 'lo' }
        expect(lo).to be_a Nl::Linux::RtAddr::Messages::DumpGetaddrReply

        expect(lo.fixed_header.ifa_family).to eq 2  # AF_INET
        expect(lo.fixed_header.ifa_index).to eq 1  # loopback interface index is always 1
      end
    end
  end

  describe Nl::Linux::Netdev do
    example 'do_dev_get returns device info for loopback' do
      Nl::Genl::Connection.open(resolver:) do |conn|
        netdev = conn.open(Nl::Linux::Netdev)
        dev = netdev.do_dev_get(ifindex: 1)
        expect(dev).to be_a Nl::Linux::Netdev::Messages::DoDevGetReply

        expect(dev.ifindex).to eq 1
      end
    end
  end

  describe Nl::Linux::Nlctrl do
    example 'do_getfamily returns family info for nlctrl' do
      Nl::Linux::Nlctrl.open do |nlctrl|
        reply = nlctrl.do_getfamily(family_name: 'nlctrl')
        expect(reply).to be_a Nl::Linux::Nlctrl::Messages::DoGetfamilyReply

        expect(reply.family_name).to eq 'nlctrl'
      end
    end

    example 'dump_getfamily returns family list including nlctrl' do
      Nl::Linux::Nlctrl.open do |nlctrl|
        replies = nlctrl.dump_getfamily
        expect(replies).to be_an Array

        reply = replies.find { it.family_name == 'nlctrl' }
        expect(reply).to be_a Nl::Linux::Nlctrl::Messages::DumpGetfamilyReply
        expect(reply.family_id).to eq Nl::Genl::GENL_ID_CTRL
      end
    end

    example 'dump_getpolicy returns policies for nlctrl' do
      Nl::Linux::Nlctrl.open do |nlctrl|
        replies = nlctrl.dump_getpolicy(family_name: 'nlctrl')
        expect(replies).not_to be_empty
        expect(replies).to all be_a Nl::Linux::Nlctrl::Messages::DumpGetpolicyReply
        expect(replies).to all have_attributes(family_id: Nl::Genl::GENL_ID_CTRL)

        policies = replies.filter_map(&:policy)
        expect(policies).not_to be_empty
        policy_entries = policies.flat_map { it.values.flat_map(&:values) }
        expect(policy_entries).to all be_a Nl::Linux::Nlctrl::AttributeSets::PolicyAttrs

        operation_policies = replies.filter_map(&:op_policy)
        expect(operation_policies).not_to be_empty
        expect(operation_policies.flat_map(&:values)).to all be_a Nl::Linux::Nlctrl::AttributeSets::OpPolicyAttrs
      end
    end
  end

  describe Nl::Linux::RtNeigh do
    fexample 'dump_getneigh returns array' do
      Nl::Linux::RtNeigh.open do |rtneigh|
        r = rtneigh.dump_getneigh
        expect(r).to be_an Array
        r.each do |entry|
          expect(entry).to be_a Nl::Linux::RtNeigh::Messages::DumpGetneighReply
        end
      end
    end

    example 'dump_getneigh accepts block' do
      Nl::Linux::RtNeigh.open do |rtneigh|
        rtneigh.dump_getneigh do |m|
          expect(m).to be_a Nl::Linux::RtNeigh::Messages::DumpGetneighReply
        end
      end
    end

    example 'dump_getneightbl returns neighbor table configurations' do
      Nl::Linux::RtNeigh.open do |rtneigh|
        r = rtneigh.dump_getneightbl
        expect(r).to be_an Array
        expect(r).not_to be_empty
        r.each do |entry|
          expect(entry).to be_a Nl::Linux::RtNeigh::Messages::DumpGetneightblReply
          expect(entry.name).to be_a String
          expect(entry.name).not_to be_empty
        end
        expect(r.map(&:name)).to include('arp_cache')
      end
    end
  end

  describe Nl::Linux::RtRoute do
    example 'do_getroute returns the loopback route for 127.0.0.1' do
      Nl::Linux::RtRoute.open do |rtroute|
        reply = rtroute.do_getroute(
          rtm_family: 2,  # AF_INET
          rtm_dst_len: 32,
          dst: "\x7f\x00\x00\x01",
        )
        expect(reply).to be_a Nl::Linux::RtRoute::Messages::DoGetrouteReply

        expect(reply.rtm_family).to eq 2
        expect(reply.rtm_dst_len).to eq 32
        expect(reply.dst).to eq "\x7f\x00\x00\x01"
        expect(reply.oif).to eq 1
      end
    end

    example 'dump_getroute returns IPv4 routes' do
      Nl::Linux::RtRoute.open do |rtroute|
        r = rtroute.dump_getroute(rtm_family: 2)  # AF_INET
        expect(r).to be_an Array
        expect(r).not_to be_empty
        r.each do |entry|
          expect(entry).to be_a Nl::Linux::RtRoute::Messages::DumpGetrouteReply
          expect(entry.rtm_family).to eq 2
        end
      end
    end

    example 'dump_getroute accepts block' do
      Nl::Linux::RtRoute.open do |rtroute|
        r = []
        rtroute.dump_getroute(rtm_family: 2) do |m|
          expect(m).to be_a Nl::Linux::RtRoute::Messages::DumpGetrouteReply
          r << m
        end
        expect(r).not_to be_empty
      end
    end
  end

  describe Nl::Linux::RtRule do
    example 'dump_getrule returns default IPv4 routing rules' do
      Nl::Linux::RtRule.open do |rtrule|
        r = rtrule.dump_getrule(family: 2)  # AF_INET
        expect(r).to be_an Array
        expect(r).not_to be_empty
        r.each do |entry|
          expect(entry).to be_a Nl::Linux::RtRule::Messages::DumpGetruleReply
          expect(entry.family).to eq 2
        end
      end
    end
  end

  describe Nl::Linux::Tc do
    example 'dump_getqdisc returns qdisc for loopback' do
      Nl::Linux::Tc.open do |tc|
        r = tc.dump_getqdisc
        expect(r).to be_an Array
        expect(r).not_to be_empty

        lo_qdisc = r.find { it.ifindex == 1 }
        expect(lo_qdisc).to be_a Nl::Linux::Tc::Messages::DumpGetqdiscReply
        expect(lo_qdisc.kind).to be_a String
      end
    end
  end

  describe Nl::Linux::Ethtool do
    example 'dump_strset_get returns string sets' do
      Nl::Genl::Connection.open(resolver:) do |conn|
        ethtool = conn.open(Nl::Linux::Ethtool)
        r = ethtool.dump_strset_get
        expect(r).to be_an Array
        expect(r).not_to be_empty
        r.each do |entry|
          expect(entry).to be_a Nl::Linux::Ethtool::Messages::DumpStrsetGetReply
        end
      end
    end

    example 'dump_features_get returns device features' do
      Nl::Genl::Connection.open(resolver:) do |conn|
        ethtool = conn.open(Nl::Linux::Ethtool)
        r = ethtool.dump_features_get
        expect(r).to be_an Array
        expect(r).not_to be_empty
        r.each do |entry|
          expect(entry).to be_a Nl::Linux::Ethtool::Messages::DumpFeaturesGetReply
        end
      end
    end

    example 'dump_linkstate_get returns entry for loopback' do
      Nl::Genl::Connection.open(resolver:) do |conn|
        ethtool = conn.open(Nl::Linux::Ethtool)
        r = ethtool.dump_linkstate_get
        expect(r).to be_an Array

        lo = r.find { it.header[:dev_index]&.value == 1 }
        dev_name = lo.header[:dev_name]
        expect(dev_name).to be_a Nl::Linux::Ethtool::AttributeSets::Header::DevName
        expect(dev_name.value).to eq 'lo'
      end
    end
  end
end
