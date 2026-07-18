# TX-10 — Carry a non-hub chain's frozen tally to the hub (2-step, permissionless)

For every chain except 0: a two-step carrier moves the chain's frozen tally to the hub
aggregate — step 0 on the source chain packages the numbers, step 1 lands them on chain 0
with a cross-chain proof. Identical mechanics to a cross-chain transfer continuation.
Anyone may run it; the payload is contract-computed (no caller input) and duplicates die
on the hub insert.

| | |
|---|---|
| Actor | anyone |
| Chains | step 0: the source chain `$CHAIN` (≠ 0) · step 1: chain `0` |
| Gas | step 0 self-paid · step 1 self-paid **or station-sponsored** (both work) |
| Verification | `devnet-verified` (2026-07-18: step 0 by a neutral key; step 1 landed as a station-sponsored continuation) + `network-proven` (pre-reset 20/20) |

## Step 0 — package the tally (source chain)

```json
{
  "networkId": "$NETWORK",
  "payload": {
    "exec": { "code": "($NS.smartpacts-shares.report-tally-xchain \"<PROPOSAL>\")", "data": {} }
  },
  "signers": [ { "pubKey": "<SUBMITTER_PUBKEY_HEX>", "clist": [ { "name": "coin.GAS", "args": [] } ] } ],
  "meta": {
    "chainId": "$CHAIN",
    "sender": "<SUBMITTER_ACCOUNT>",
    "gasLimit": 2500,
    "gasPrice": 0.00000001,
    "ttl": 1800,
    "creationTime": "<unix-seconds, backdated ~30 s>"
  },
  "nonce": "<unique>"
}
```

The step-0 **request key is the continuation id**. Wait for it to mine, then fetch the
proof (retry until available — typically 1–3 minutes):

```
POST $API/chainweb/0.0/$NETWORK/chain/$CHAIN/pact/spv
{ "requestKey": "<STEP0_REQUEST_KEY>", "targetChainId": "0" }
```

## Step 1 — land it on the hub (chain 0, continuation payload)

Station-sponsored variant (no funds needed on chain 0):

```json
{
  "networkId": "$NETWORK",
  "payload": {
    "cont": {
      "pactId": "<STEP0_REQUEST_KEY>",
      "step": 1,
      "rollback": false,
      "data": { "tx-type": "cont" },
      "proof": "<SPV_PROOF_STRING>"
    }
  },
  "signers": [
    { "pubKey": "<ANY_PUBKEY_HEX>",
      "clist": [ { "name": "$NS.smartpacts-gas-station.GAS_PAYER",
                   "args": ["reporter", { "int": "1500" }, { "decimal": "0.000001" }] } ] }
  ],
  "meta": {
    "chainId": "0",
    "sender": "<STATION>",
    "gasLimit": 1500,
    "gasPrice": 0.000001,
    "ttl": 1800,
    "creationTime": "<unix-seconds, backdated ~30 s>"
  },
  "nonce": "<unique>"
}
```

Self-paid variant: `sender` = your chain-0 account, normal gas, `clist` = `coin.GAS`,
`data: {}`. (A continuation carries no code, so the station checks only its gas ceilings
and daily budget on this leg.)

## Failure modes

| Error | Meaning / fix |
|---|---|
| step 0: `use report-tally-hub on the hub` | you ran it on chain 0 |
| step 0: `voting still open on this chain` | deadline not passed here yet |
| proof endpoint 4xx/5xx or empty | not provable yet — keep polling |
| step 1: `…already exists in the table…` | this chain already reported — done |
| step 1: `gas station epoch cap reached…` | sponsorship budget out — use the self-paid variant |
