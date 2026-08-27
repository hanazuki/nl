require 'nl/linux'

def print_results(loopback, links)
  puts "Loopback interface: #{loopback.ifname}"
  puts "All interfaces: #{links.map(&:ifname).join(', ')}"
end

Nl::Linux::RtLink.open do |rtlink|
  loopback = rtlink.do_getlink(ifi_index: 1)
  links = rtlink.dump_getlink

  print_results(loopback, links)
end
