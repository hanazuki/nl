require 'nl/linux'

RSpec.describe do
  describe Nl::Linux::RtLink do
    example do
      Nl::Linux::RtLink.open do |rtlink|
        r = rtlink.dump_getlink
        expect(r).to be_an Array

        lo = r.find { it.ifname == 'lo' }
        expect(lo).to be_a Nl::Linux::RtLink::Messages::DumpGetlinkReply

        expect(lo.fixed_header.ifi_type).to eq 772  # ARPHRD_LOOPBACK
      end
    end

    example do
      Nl::Linux::RtLink.open do |rtlink|
        r = []
        rtlink.dump_getlink do |m|
          expect(m).to be_a Nl::Linux::RtLink::Messages::DumpGetlinkReply
          r << m
        end
        expect(r).not_to be_empty
      end
    end
  end

  describe Nl::Linux::RtAddr do
    example do
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
    example do
      resolver = ->(socket, name) {
        Nl::Linux::Nlctrl.new(socket).do_getfamily(family_name: name).family_id
      }

      Nl::Genl::Connection.open(resolver:) do |conn|
        netdev = conn.open(Nl::Linux::Netdev)
        dev = netdev.do_dev_get(ifindex: 1)
        expect(dev).to be_a Nl::Linux::Netdev::Messages::DoDevGetReply

        expect(dev.ifindex).to eq 1
      end
    end
  end

  describe Nl::Linux::Nlctrl do
    example do
      Nl::Linux::Nlctrl.open do |nlctrl|
        reply = nlctrl.do_getfamily(family_name: 'nlctrl')
        expect(reply).to be_a Nl::Linux::Nlctrl::Messages::DoGetfamilyReply

        expect(reply.family_name).to eq 'nlctrl'
      end
    end
  end
end
