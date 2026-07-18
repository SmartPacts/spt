# TX-07 — Close a proposal after its deadline (operator)

Administrative tidying: the tally froze by itself at `close-at`; closing flips the status
and removes the proposal from the per-transfer bookkeeping index. Changes no numbers.
Run on **every chain** the proposal was announced on, any time after the deadline.

| | |
|---|---|
| Actor | operator (admin keyset) |
| Chain | every announced chain |
| Sender / gas | operator's gas account, self-paid |
| Verification | `devnet-verified` (2026-07-18: close on both rehearsal chains; the freeze-at-deadline was proven independently of the close) |

## The signable command (per chain)

```json
{
  "networkId": "$NETWORK",
  "payload": {
    "exec": { "code": "($NS.smartpacts-shares.close-proposal \"<ID>\")", "data": {} }
  },
  "signers": [ { "pubKey": "<ADMIN_PUBKEY_HEX>" } ],
  "meta": {
    "chainId": "<each chain>",
    "sender": "<ADMIN_GAS_ACCOUNT>",
    "gasLimit": 3000,
    "gasPrice": 0.00000001,
    "ttl": 28800,
    "creationTime": "<unix-seconds, backdated ~30 s>"
  },
  "nonce": "<unique per chain>"
}
```

Verify per chain: `proposal-details` → `status: "closed"`. Reporting (TX-09/TX-10) does
NOT require the close — only the passed deadline.

## Failure modes

| Error | Meaning / fix |
|---|---|
| `only active can close` | already closed/cancelled here (idempotency signal — fine) |
