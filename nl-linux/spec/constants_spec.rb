require 'nl/linux/tcp_metrics'

RSpec.describe Nl::Linux::TcpMetrics::Constants do
  it 'exposes constants from YNL definitions' do
    expect(described_class::TCP_FASTOPEN_COOKIE_MAX).to eq 16
  end
end
