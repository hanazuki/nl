# Nl - Netlink libraries for Ruby

This repository is the home to three gems:

- `nl` -- Core Netlink protocol library.
- `ynl` -- YNL (YAML Netlink Specification) parser and code generator.
- `nl-linux` -- Client definitions for Linux Netlink subsystems.

## Synopsis

```ruby
require 'nl/linux'
require 'ipaddr'

# List IP addresses by interface
Nl::Raw::Client.open(protonum: Nl::Raw::NETLINK_ROUTE) do |client|
  rtaddr = client.family(Nl::Linux::RtAddr)
  rtlink = client.family(Nl::Linux::RtLink)

  links = rtlink.dump_getlink.to_h { |link| [link.ifi_index, link] }

  rtaddr.dump_getaddr.group_by(&:ifa_index).each do |ifindex, addrs|
    ips = addrs.map { |addr| "#{IPAddr.new_ntoh(addr.address)}/#{addr.ifa_prefixlen}" }
    link = links.fetch(ifindex)

    puts "#{link.ifname}: #{ips.join(', ')}"
  end
end

# List interface speeds
Nl::Linux::Ethtool.open do |ethtool|
  ethtool.dump_linkmodes_get.each do |dev|
    puts "#{dev.header.dev_name}: #{dev.speed} Mbps"
  end
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/hanazuki/nl>.

## License

`nl` and `ynl` gems are available under [The MIT License](https://opensource.org/licenses/MIT). `nl-linux` gem is dual-licensed under [GPL-2.0 WITH Linux-syscall-note](https://www.kernel.org/doc/html/latest/process/license-rules.html) and [The 3-Clause BSD License](https://opensource.org/license/bsd-3-clause) because it contains derived works of the Linux kernel's Netlink YAML definitions.

## References

- "[Netlink protocol specifications (in YAML)](https://www.kernel.org/doc/html/latest/userspace-api/netlink/specs.html)". *[Netlink Handbook](https://www.kernel.org/doc/html/latest/userspace-api/netlink/)*.
- Jakub Kicinski. "[YAML Netlink](https://lpc.events/event/16/contributions/1347/attachments/1022/1982/YAML%20Neltink.pdf)". Linux Plumbers Conference 2022.
