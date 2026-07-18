# TX-08 — Cancel a still-running proposal (operator)

Kills a live vote. A cancelled proposal has no result: further votes are refused,
reporting is refused, the aggregate never forms. The only way to withdraw a mis-announced
proposal (there is no edit). **A public act** — the `PROPOSAL-CLOSED` event with status
`cancelled` is permanent; pair it with an announcement. Run on every announced chain.

| | |
|---|---|
| Actor | operator (admin keyset) |
| Chain | every announced chain |
| Sender / gas | operator's gas account, self-paid |
| Verification | `devnet-verified` (2026-07-18: cancel + refusal to report the cancelled proposal) |

## The signable command (per chain)

```json
{
  "networkId": "$NETWORK",
  "payload": {
    "exec": { "code": "($NS.smartpacts-shares.cancel-proposal \"<ID>\")", "data": {} }
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

## Failure modes

| Error | Meaning / fix |
|---|---|
| `only active can cancel` | already closed/cancelled here, or wrong id |
| cancelled on some chains only | finish the loop — until then the untouched chains keep collecting votes that will never aggregate |
