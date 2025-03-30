# Project structure

## nl

- lib/
  - nl.rb - Library entrypoint.
  - nl/
    - family.rb - High-level API to interact with Netlink protocol family.
    - protocols.rb - Low-level API to speak Netlink protocol.
    - socket.rb - Netlink socket.
    - core.rb - Definitions for the core Netlink protocol.
    - genl.rb - Definitions for the generic Netlink protocol.
    - decoder.rb - Binary message decoder.
    - encoder.rb - Binary message encoder.
    - endian.rb - Utility for endianness.

## ynl

- lib/
  - ynl.rb - Library entrypoint.
  - ynl/
    - family.rb - Easy API to generate Nl::Family from YNL definition.
    - parser.rb - Parses YNL definition.
    - models.rb - Parsing states.
    - generator.rb - Generates Nl::Family from parsed definition.

## nl-linux

- linux/ - YNL definitions imported from kernel tree.
- ext/nl-linux/