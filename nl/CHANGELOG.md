# ChangeLog

## Unreleased

- Remove `Raw::NlAttr`; attribute sets and array codecs write their headers
  directly without allocating a header object.
- Unify `Raw::Message` and `Genl::Message` as `Nl::Message`.
- Avoid validation overhead for datatypes without checks by moving validation
  into opt-in wrappers. Replace datatype constructor `check:` arguments with
  `DataTypes::Checked.new(datatype, check:)`, or `CheckedPayload` for checks on
  encoded structs and packed arrays.
- Return decoded values directly from `AttributeSet#[]` instead of attribute
  wrapper objects. Replace `attributes[:name].value` with `attributes[:name]`.
- Replace `AttributeSet#<<` with `append(name_or_id, value)`. Construct empty
  sets with `AttributeSet.new`, and use `build_attributes(params)` instead of
  passing an array of attribute wrappers to the constructor.
- Change `Message#append_attribute` to accept an attribute name or numeric
  ID and its value: `message.append_attribute(:mtu, 1500)`.
- Replace `AttributeSet::Attribute` and per-attribute classes with immutable
  `AttributeSet::Definition` records. `by_name` and `by_type` return definitions
  exposing `id`, `name`, `datatype`, `multi`, `order`, and `selector_slot`.

## v0.4.2 (2026-09-09)

## v0.4.1 (2026-09-08)

## v0.4.0 (2026-09-08)

- Represent `bitfield32` values with mutable `Bitfield32` objects.
- Support fixed-length binary values and structured binary values.
- Encode Generic Netlink requests with the protocol version.
- Support building and reading attributes declared as repeatable.
- Add `Raw::Client` for using raw families with the same protocol number over one connection.
- Rename `Genl::Connection` to `Genl::Client`.
- Remove `UnknownNotification`; unsolicited messages without a registered decoder are now ignored.
- Add context-aware encoding and decoding support for polymorphic sub-messages.

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
