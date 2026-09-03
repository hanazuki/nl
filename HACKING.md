# Project structure

## nl

Basic Netlink protocol handling.

- lib/
  - nl.rb - Library entrypoint.
  - nl/
    - connection.rb - Socket, transport, membership, and notification ownership.
    - family.rb - Shared high-level family API.
    - datatypes.rb - Datatype codecs shared by raw and Generic Netlink schemas.
    - raw.rb - Raw family base, message, and attribute schema classes.
    - raw/
      - wire.rb - Netlink wire constants and structures.
      - protocol.rb - Raw Netlink endpoints and protocol behavior.
      - client.rb - Family binding on a shared raw Netlink connection.
    - genl.rb - Generic Netlink family base class and entrypoint.
    - genl/
      - wire.rb - Generic Netlink wire constants and structures.
      - protocol.rb - Generic Netlink endpoints and protocol behavior.
      - client.rb - Family lookup and binding on a shared Generic Netlink connection.
    - socket.rb - Netlink socket.
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

# Rake tasks

- `bundle exec rake spec` - Runs RSpec test suite.
- `bundle exec rake generate` - Regenerates nl-linux protocol definitions.
