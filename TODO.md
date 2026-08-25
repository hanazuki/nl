# TODO

## notifications

## multipart replies to `do` requests

Some subsystems in the kernel return multiple `NLM_F_MULTI` messages followed by `NLMSG_DONE` for `do` operations. A YNL specification cannot declare that a `do` reply is multipart. Our `do` API returns one value (a `Future` when asynchronous). `Exchange` drains a multipart reply properly but exposes only its first message.

Known operations with this behavior are:

- Generic Netlink `devlink`
  - `dpipe-table-get`
  - `dpipe-entries-get`
  - `dpipe-headers-get`
  - `resource-dump`
  - `health-reporter-diagnose`
- Generic Netlink `team`
  - `options-get`
  - `port-list-get`
- Generic Netlink `smc`
  - `SMC_PNETID_GET`
- Raw Netlink `NETLINK_AUDIT`
  - `AUDIT_LIST_RULES`

## Support batched `do_multi` requests

The nftables subsystem expects transcational operations are batched in a single Netlink datagram. This library should support this in blocking and async facade.

```ruby
nftables.batch do |b|
  b.batch_begin
  b.newtable(...)
  b.newchain(...)
  # ...
  b.batch_end
end
```

The YNL reference implemenataion provides `do_multi` action (introduced by Linux commit ba8be00f68f5c70eb1df2193251a579923bd9501).

When an nftables transaction fails, the kernel may not send an ACK for every request in the batch. The client must not wait indefinitely for those missing ACKs: on a batch error, it must cancel the remaining exchanges belonging to the batch and safely ignore or drain any late replies.
