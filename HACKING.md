# Project structure

## nl

Basic Netlink protocol handling.

- lib/
  - nl.rb - Library entrypoint.
  - nl/
    - family.rb - High-level API to interact with Netlink protocol families.
    - protocols/
      - raw.rb - Low-level implementation of the raw Netlink protocol (netlink-raw).
      - genl.rb - Low-level implementation of the Generic Netlink protocol (netlink-generic).
    - socket.rb - Netlink socket.
    - core.rb - Core Netlink structures and constants (NlMsgHdr, NlAttr, etc.).
    - genl.rb - Generic Netlink message handling.
    - decoder.rb - Binary message decoder.
    - encoder.rb - Binary message encoder.
    - endian.rb - Endianness utilities.
    - version.rb - Gem version.

## ynl

YAML Netlink Specification parser and code generator.

- lib/
  - ynl.rb - Library entrypoint.
  - ynl/
    - family.rb - Easy API to generate Nl::Family from a YNL definition file.
    - parser.rb - Parses YNL definition YAML into models.
    - models.rb - Data models for parsed YNL definitions.
    - generator.rb - Generates Ruby code (Nl::Family subclass) from parsed definitions.
    - version.rb - Gem version.

## nl-linux

Netlink protocol definitions imported from the Linux kernel tree.

- linux/ - YNL definitions imported from the kernel tree.
- generated/ - Ruby files generated from the YNL definitions (do not edit).
- lib/
  - nl-linux.rb - Alias for nl/linux.rb.
  - nl/linux.rb - Library entrypoint - requires all Netlink families.
  - nl/linux/
    - version.rb - Gem version.
- ext/nl-linux/
  - rakefile.rb - Rake tasks for regenerating files in generated/ from linux/.
- bin/
  - import-nlspec - Script to import YNL specs from a kernel git tree.
- NLSPEC_VERSION - Tracks the kernel version of the imported YNL specs.

## Top-level

- spec/ - Integration tests.
