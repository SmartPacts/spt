# TX-02 — Cast (or change) an advisory vote, self-paid

The ordinary-transaction variant of TX-01: the voter pays their own gas. Use it when the
station's daily budget is exhausted, or from tooling that cannot set a foreign sender.
Everything about the vote itself (chain-local, live weight, re-vote replaces) is identical
to TX-01.

| | |
|---|---|
| Actor | holder (or their registered voting key) |
| Chain | `$CHAIN` = wherever the voter's test-shares live |
| Sender / gas | the voter's own account, ~400–800 gas at normal price |
| Verification | `devnet-verified` (2026-07-18: self-paid vote + chain-local second vote) + `network-proven` (pre-reset) |

## The signable command

```json
{
  "networkId": "$NETWORK",
  "payload": {
    "exec": {
      "code": "($NS.smartpacts-shares.cast-vote \"<VOTER>\" \"<PROPOSAL>\" true)",
      "data": {}
    }
  },
  "signers": [
    {
      "pubKey": "<SIGNER_PUBKEY_HEX>",
      "clist": [
        { "name": "coin.GAS", "args": [] },
        { "name": "$NS.smartpacts-shares.VOTE", "args": ["<VOTER>"] }
      ]
    }
  ],
  "meta": {
    "chainId": "$CHAIN",
    "sender": "<VOTER>",
    "gasLimit": 2500,
    "gasPrice": 0.00000001,
    "ttl": 1800,
    "creationTime": "<unix-seconds, backdated ~30 s>"
  },
  "nonce": "<unique>"
}
```

- With a **registered voting key** (TX-03) the voting key CAN sign the `VOTE` capability,
  but the gas payer (`sender` + `coin.GAS`) must be an account that key controls — a
  voting key usually has no funded account, so hot-key voting is normally done gasless
  (TX-01), where no signer needs funds.
- `gasLimit` 2500 is comfortable headroom; a vote measures a few hundred gas.

## Expected result / failure modes

As TX-01, minus the station rows: no allowlist, no epoch cap, no ceiling errors. Add:

| Error | Meaning / fix |
|---|---|
| `Attempt to buy gas failed` / insufficient funds | the sender account lacks KDA on `$CHAIN` |
