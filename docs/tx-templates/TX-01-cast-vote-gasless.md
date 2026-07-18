# TX-01 — Cast (or change) an advisory vote, gasless

The holder needs **zero KDA on any chain**. The station pays the network fee; the holder's
key only authorizes the vote itself. Voting is **chain-local**: submit on the chain where
the test-shares live; weight = the account's full current balance there. Re-submitting
with a new direction replaces the previous vote.

| | |
|---|---|
| Actor | holder (or their registered voting key — see TX-03) |
| Chain | `$CHAIN` = wherever the voter's test-shares live |
| Sender / gas | station account, ≤ 1500 gas @ ≤ 0.000001 |
| Verification | `devnet-verified` (2026-07-18: sponsored zero-KDA vote + hot-key vote, against this repo's `contracts/testnet06/` sources) + `network-proven` (pre-reset gasless campaign votes) |

## Before building

- `STATION` (once): `/local` → `$NS.smartpacts-gas-station.GAS_STATION`
- The proposal must be `active` on `$CHAIN` and before `close-at`
  (`($NS.smartpacts-shares.proposal-details "<PROPOSAL>")` — see TX-11).
- The voter must hold test-shares on `$CHAIN` (`get-balance`).

## The signable command (payload object — serialize once, sign the blake2b-256 hash)

```json
{
  "networkId": "$NETWORK",
  "payload": {
    "exec": {
      "code": "($NS.smartpacts-shares.cast-vote \"<VOTER>\" \"<PROPOSAL>\" true)",
      "data": {
        "tx-type": "exec",
        "exec-code": ["($NS.smartpacts-shares.cast-vote \"<VOTER>\" \"<PROPOSAL>\" true)"]
      }
    }
  },
  "signers": [
    {
      "pubKey": "<SIGNER_PUBKEY_HEX>",
      "clist": [
        { "name": "$NS.smartpacts-shares.VOTE", "args": ["<VOTER>"] },
        { "name": "$NS.smartpacts-gas-station.GAS_PAYER",
          "args": ["<VOTER>", { "int": "1500" }, { "decimal": "0.000001" }] }
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

- `true` = approve, `false` = reject.
- The `data` block mirroring the code is **optional** (the node injects the real
  transaction type + executed code into the sponsorship check — devnet-proven; see
  README §sponsored). Keeping the mirror byte-identical is the network-proven
  belt-and-braces shape; a mismatch is ignored, not fatal.
- `<SIGNER_PUBKEY_HEX>` = the key holding the vote right: the account's **main key**, or
  the account's **registered voting key** (TX-03) — the contract accepts either; the
  transaction shape is identical. One signature, by that key, over the command hash.
- The `GAS_PAYER` capability carries **no authority** — its arguments are conventional.
  Signing it scoped costs nothing and enables nothing beyond asking the station to pay.
- Do **not** add any other expression to `code` — one sponsored call per transaction,
  or the station refuses.

## Expected result

`"vote cast"` + a `VOTE-CAST (voter proposal weight direction)` event. Verify with
`($NS.smartpacts-shares.vote-weight "<VOTER>" "$CHAIN" "<PROPOSAL>")` (TX-11).

## Failure modes

| Error | Meaning / fix |
|---|---|
| `Not a sponsored call…` | `code` isn't exactly one allowlisted call (extra expressions, wrong namespace, wrong function) |
| `gas station epoch cap reached…` | day's sponsorship budget exhausted — self-pay (TX-02) or wait |
| `Gas limit must be <= 1500` (or price) | meta exceeds the station ceilings |
| `proposal not active` / `voting closed` | wrong id, cancelled, or past `close-at` |
| `no voting weight` | zero balance on THIS chain — vote where the test-shares live |
| `neither account guard nor registered vote key satisfied` | wrong signing key |
| `Keyset failure` on buying gas | `sender` is not the station account you read on this chain |
