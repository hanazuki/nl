require 'nl/linux'

RSpec.describe do
  describe Nl::Linux::RtLink do
    example do
      Nl::Linux::RtLink.open do |rtlink|
        r = rtlink.dump_getlink
        expect(r).to be_an Array

        lo = r.find do |i|
          i.attributes.any? do |attr|
            attr.kind_of?(Nl::Linux::RtLink::AttributeSets::LinkAttrs::Ifname) && attr.value == 'lo'
          end
        end
        expect(lo).to be_a Nl::Linux::RtLink::Messages::DumpGetlinkReply

        expect(lo.fixed_header.ifi_type).to eq 772  # ARPHRD_LOOPBACK
      end
    end
  end

  describe Nl::Linux::RtAddr do
    example do
      Nl::Linux::RtAddr.open do |rtaddr|
        r = rtaddr.dump_getaddr
        expect(r).to be_an Array

        lo = r.find do |i|
          i.attributes.any? do |attr|
            attr.kind_of?(Nl::Linux::RtAddr::AttributeSets::AddrAttrs::Label) && attr.value == 'lo'
          end
        end
        expect(lo).to be_a Nl::Linux::RtAddr::Messages::DumpGetaddrReply

        expect(lo.fixed_header.ifa_family).to eq 2  # AF_INET
        expect(lo.fixed_header.ifa_index).to eq 1  # loopback interface index is always 1
      end
    end
  end

  describe Nl::Linux::Netdev do
    example do
      resolver = ->(socket, name) {
        Nl::Linux::Nlctrl.new(socket)
          .do_getfamily(family_name: name).first
          .attributes.find { it.is_a?(Nl::Linux::Nlctrl::AttributeSets::CtrlAttrs::FamilyId) }
          .value
      }

      Nl::Genl::Connection.open(resolver:) do |conn|
        netdev = conn.open(Nl::Linux::Netdev)
        r = netdev.do_dev_get(ifindex: 1)
        expect(r).to be_an Array
        expect(r.length).to eq 1

        dev = r.first
        expect(dev).to be_a Nl::Linux::Netdev::Messages::DoDevGetReply

        ifindex_attr = dev.attributes.find { it.is_a?(Nl::Linux::Netdev::AttributeSets::Dev::Ifindex) }
        expect(ifindex_attr).not_to be_nil
        expect(ifindex_attr.value).to eq 1
      end
    end
  end

  describe Nl::Linux::Nlctrl do
    example do
      Nl::Linux::Nlctrl.open do |nlctrl|
        r = nlctrl.do_getfamily(family_name: 'nlctrl')
        expect(r).to be_an Array
        expect(r.length).to eq 1

        reply = r.first
        expect(reply).to be_a Nl::Linux::Nlctrl::Messages::DoGetfamilyReply

        name_attr = reply.attributes.find {|attr| attr.kind_of?(Nl::Linux::Nlctrl::AttributeSets::CtrlAttrs::FamilyName) }
        expect(name_attr).not_to be_nil
        expect(name_attr.value).to eq 'nlctrl'
      end
    end
  end
end
