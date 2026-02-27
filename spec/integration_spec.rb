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
end
