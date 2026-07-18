# TX-05 — Claim accrued distributions, gasless

Pays the account's accrued distributions (KDA) to the holder's own guard-bound account —
free of charge, on the chain where the test-shares sit. The claim is **permissionless**:
any key may submit it for any account; the payout always goes to the named account's own
guard, never to the submitter. That is why NO account-authorizing capability appears
below — only the (authority-free) sponsorship request.

| | |
|---|---|
| Actor | anyone (usually the holder) |
| Chain | `$CHAIN` = where the claiming account's test-shares are |
| Sender / gas | station account, ≤ 1500 @ ≤ 0.000001 |
| Verification | `devnet-verified` (2026-07-18: holder claim + a third-party-triggered claim — the payout landed with the holder, not the submitter) + `network-proven` (pre-reset) |

## The signable command

```json
{
  "networkId": "$NETWORK",
  "payload": {
    "exec": {
      "code": "($NS.smartpacts-shares.claim-dividends \"<ACCOUNT>\")",
      "data": {
        "tx-type": "exec",
        "exec-code": ["($NS.smartpacts-shares.claim-dividends \"<ACCOUNT>\")"]
      }
    }
  },
  "signers": [
    {
      "pubKey": "<ANY_PUBKEY_HEX>",
      "clist": [
        { "name": "$NS.smartpacts-gas-station.GAS_PAYER",
          "args": ["<ACCOUNT>", { "int": "1500" }, { "decimal": "0.000001" }] }
      ]
    }
  ],
  "meta": {
    "chainId": "$CHAIN",
    "sender": "<STATION>",
    "gasLimit": 1500,
    "gasPrice": 0.000001,
    "ttl": 1800,
    "creationTime": "<unix-seconds, backdated ~30 s>"
  },
  "nonce": "<unique>"
}
```

- `<STATION>`: `/local` → `$NS.smartpacts-gas-station.GAS_STATION` (same on every chain).
- Check what is claimable first (free):
  `($NS.smartpacts-shares.pending-dividends-of "<ACCOUNT>")`.
- Amounts pay at 12-decimal precision; any finer remainder stays credited and rides into
  the next claim.

## Expected result

The paid amount (decimal) + a `DIVIDEND-CLAIMED (account amount)` event; the KDA arrives
at the holder's own guard-bound account (for `k:` accounts: the same name in `coin`).

## Failure modes

| Error | Meaning / fix |
|---|---|
| `nothing to claim` | zero accrued on this chain (or an excluded reserve account) |
| `Not a sponsored call…` / cap / ceiling errors | as TX-01 |
