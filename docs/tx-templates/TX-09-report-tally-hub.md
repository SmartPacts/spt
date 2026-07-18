# TX-09 — Report chain 0's frozen tally into the aggregate (permissionless)

After a proposal's deadline passes, each chain's tally is frozen and must be *reported*
once into the hub aggregate on chain 0. This template covers **chain 0's own numbers**;
every other chain uses TX-10. Reporting is open to anyone: the numbers are read by the
contract from its own frozen tally — the submitter cannot inject values — and a duplicate
report fails harmlessly.

| | |
|---|---|
| Actor | anyone with a little KDA on chain 0 |
| Chain | `0` only |
| Sender / gas | submitter's account, self-paid (~150 gas) |
| Verification | `devnet-verified` (2026-07-18: reported by a neutral non-holder key; duplicate + cancelled-proposal rejections) + `network-proven` (pre-reset 20/20 aggregation) |

## The signable command

```json
{
  "networkId": "$NETWORK",
  "payload": {
    "exec": { "code": "($NS.smartpacts-shares.report-tally-hub \"<PROPOSAL>\")", "data": {} }
  },
  "signers": [ { "pubKey": "<SUBMITTER_PUBKEY_HEX>", "clist": [ { "name": "coin.GAS", "args": [] } ] } ],
  "meta": {
    "chainId": "0",
    "sender": "<SUBMITTER_ACCOUNT>",
    "gasLimit": 2500,
    "gasPrice": 0.00000001,
    "ttl": 1800,
    "creationTime": "<unix-seconds, backdated ~30 s>"
  },
  "nonce": "<unique>"
}
```

## Expected result

`"reported"` + `TALLY-REPORTED (proposal "0" yes no)`. Read the running aggregate any
time: `($NS.smartpacts-shares.get-final-results "<PROPOSAL>")` (TX-11).

## Failure modes

| Error | Meaning / fix |
|---|---|
| `voting still open on this chain` | `close-at` not reached in block-time yet |
| `…already exists in the table…` (insert) | chain 0 already reported — done, move on |
| `cancelled proposal has no result` | cancelled proposals cannot be reported |
| `hub tally reports locally; use report-tally-xchain off-hub` | you sent this to a non-hub chain |
