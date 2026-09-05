require 'nl/linux/nftables'
require 'nl/linux/rt_link'
require 'nl/linux/tc'

RSpec.describe 'generated Linux sub-messages' do
  def round_trip(attribute_set, values)
    encoder = Nl::Encoder.new
    attribute_set.build_attributes(values).encode(encoder)
    attribute_set.decode(Nl::Decoder.new(encoder.buffer))
  end

  it 'selects an attribute-only format using a local string selector' do
    attrs = round_trip(
      Nl::Linux::RtLink::AttributeSets::LinkinfoAttrs,
      data: {forward_delay: 100, stp_state: 1},
      kind: 'bridge',
    )

    expect(attrs[:data].value).to be_a(
      Nl::Linux::RtLink::SubMessages::LinkinfoDataMsg::Bridge,
    )
    expect(attrs[:data].value).to have_attributes(forward_delay: 100, stp_state: 1)
  end

  it 'selects a fixed-header-only format' do
    attrs = round_trip(
      Nl::Linux::Tc::AttributeSets::Attrs,
      options: {limit: 200},
      kind: 'bfifo',
    )

    expect(attrs[:options].value).to be_a(
      Nl::Linux::Tc::SubMessages::OptionsMsg::Bfifo,
    )
    expect(attrs[:options].value.limit).to eq(200)
  end

  it 'passes an external selector into a nested attribute set' do
    attrs = round_trip(
      Nl::Linux::Tc::AttributeSets::Attrs,
      stats2: {app: {maxpacket: 1_500}},
      kind: 'codel',
    )
    app = attrs[:stats2].value[:app].value

    expect(app).to be_a(Nl::Linux::Tc::SubMessages::TcaStatsAppMsg::Codel)
    expect(app.maxpacket).to eq(1_500)
  end

  it 'selects a format using an enum-backed integer selector' do
    attrs = round_trip(
      Nl::Linux::Nftables::AttributeSets::ObjAttrs,
      data: {bytes: 12, packets: 3},
      type: 1,
    )

    expect(attrs[:data].value).to be_a(
      Nl::Linux::Nftables::SubMessages::ObjData::Counter,
    )
    expect(attrs[:data].value).to have_attributes(bytes: 12, packets: 3)
  end
end
