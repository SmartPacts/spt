# TX-04 — Deactivate the voting key

Flips the registration inactive; voting falls back to the main guard alone. The row
remains — re-register any time with TX-03. Run it immediately if the voting key leaks
(worst case before that: the thief re-votes this account's balance — funds are never
exposed).

| | |
|---|---|
| Actor | account owner — MAIN key only |
| Chain | `$CHAIN` = where the key was registered |
| Sender / gas | the owner's account, self-paid |
| Verification | `devnet-verified` (2026-07-18: full voting-key lifecycle rehearsal) |

## The signable command

```json
{
  "networkId": "$NETWORK",
  "payload": {
    "exec": {
      "code": "($NS.smartpacts-shares.clear-vote-key \"<ACCOUNT>\")",
      "data": {}
    }
  },
  "signers": [
    {
      "pubKey": "<MAIN_PUBKEY_HEX>",
      "clist": [
        { "name": "coin.GAS", "args": [] },
        { "name": "$NS.smartpacts-shares.VOTE-KEY-ADMIN", "args": ["<ACCOUNT>"] }
      ]
    }
  ],
  "meta": {
    "chainId": "$CHAIN",
    "sender": "<ACCOUNT>",
    "gasLimit": 2500,
    "gasPrice": 0.00000001,
    "ttl": 1800,
    "creationTime": "<unix-seconds, backdated ~30 s>"
  },
  "nonce": "<unique>"
}
```

## Failure modes

| Error | Meaning / fix |
|---|---|
| `Keyset failure` | not the MAIN key, or the capability missing/mis-scoped |
| `row not found` | never registered on this chain |
