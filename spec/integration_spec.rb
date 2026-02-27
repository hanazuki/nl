require 'nl/linux/rt_link'

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
end
