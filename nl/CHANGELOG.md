# ChangeLog

## Unreleased

- Support fixed-length binary values and structured binary values.
- Encode Generic Netlink requests with the protocol version.
- Support building and reading attributes declared as repeatable.
- Add `Raw::Client` for using raw families with the same protocol number over one connection.
- Rename `Genl::Connection` to `Genl::Client`.
- Remove `UnknownNotification`; unsolicited messages without a registered decoder are now ignored.

## v0.3.0 (2026-09-01)

- Fix encoding of nested attributes and mark them with `NLA_F_NESTED`.
- Support encoding and decoding of nested type-value attributes.
- Support multiplexing requests via `Family.async`
- Support receiving notifications (unsolicited messages).
- Rename `Genl::Connection#open` to `Genl::Connection#family`.

## v0.2.4 (2026-08-22)

## v0.2.3 (2026-03-24)

## v0.2.2 (2026-03-02)

## v0.2.1 (2026-03-02)

## v0.2.0 (2026-03-02)

## v0.1.0 (2025-04-20)

- Initial release
