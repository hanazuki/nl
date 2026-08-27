require 'async'
require 'nl/linux'

def print_results(loopback, links)
  puts "Loopback interface: #{loopback.ifname}"
  puts "All interfaces: #{links.map(&:ifname).join(', ')}"
end

Sync do
  Nl::Linux::RtLink.open(executor: :fiber) do |rtlink|
    loopback = rtlink.async.do_getlink(ifi_index: 1)
    links = rtlink.async.dump_getlink

    print_results(loopback.await, links.to_a)
  end
end
