# frozen_string_literal: true

require_relative '../../spec/coverage_helper'
CoverageHelper.start('nl-linux')
require 'nl/linux'

RSpec.describe Nl::Linux::NlctrlResolver do
  describe '#call' do
    it 'bootstraps the nlctrl family ID without querying nlctrl' do
      client = instance_double(Nl::Genl::Client)

      expect(described_class.new.call(client, 'nlctrl')).to eq(
        Nl::Genl::FamilyInfo.new(
          id: Nl::Genl::GENL_ID_CTRL,
          multicast_groups: {}.freeze,
        ),
      )
    end

    it 'builds family info from the nlctrl reply' do
      group = {
        name: instance_double(Nl::Raw::AttributeSet::Attribute, value: 'monitor'),
        id: instance_double(Nl::Raw::AttributeSet::Attribute, value: 7),
      }
      reply = instance_double(
        Nl::Linux::Nlctrl::Messages::DoGetfamilyReply,
        family_id: 42,
        mcast_groups: [group],
      )
      nlctrl = instance_double(Nl::Linux::Nlctrl)
      client = instance_double(Nl::Genl::Client)

      expect(client).to receive(:family).with(Nl::Linux::Nlctrl).and_return(nlctrl)
      expect(nlctrl).to receive(:do_getfamily).with(family_name: 'ethtool').and_return(reply)

      expect(described_class.new.call(client, 'ethtool')).to eq(
        Nl::Genl::FamilyInfo.new(id: 42, multicast_groups: {'monitor' => 7}.freeze),
      )
    end
  end

  describe 'DEFAULT_RESOLVER' do
    subject(:default_resolver) { Nl::Linux::DEFAULT_RESOLVER }

    it { is_expected.to be_an_instance_of(Nl::Linux::NlctrlResolver).and be_frozen }
  end
end
