# Nl - Netlink libraries for Ruby

This repository is the home to three gems:

- `nl` -- Core Netlink protocol library.
- `ynl` -- YNL (YAML Netlink Specification) parser and code generator.
- `nl-linux` -- Client definitions for Linux Netlink subsystems.

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/hanazuki/nl>.

## License

The gems are available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT) with the exception that `nl-linux` gem is licensed under the [3-Clause BSD License](https://opensource.org/license/bsd-3-clause) as the library imports YAML definitions for Netlink services (YNL) from Linux.

## References

- "[Netlink protocol specifications (in YAML)](https://www.kernel.org/doc/html/latest/userspace-api/netlink/specs.html)". *[Netlink Handbook](https://www.kernel.org/doc/html/latest/userspace-api/netlink/)*.
- Jakub Kicinski. "[YAML Netlink](https://lpc.events/event/16/contributions/1347/attachments/1022/1982/YAML%20Neltink.pdf)". Linux Plumbers Conference 2022.
