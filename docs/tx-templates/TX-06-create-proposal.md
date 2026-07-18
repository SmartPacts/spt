# TX-06 — Announce a proposal (operator; identical replica on every chain)

Votes are chain-local, so a proposal must exist **identically on every chain**: the SAME
id, title, description, `created-at`, and duration — which makes every replica share ONE
closing timestamp. The operator submits this same payload once per chain (all 20 on the
public network). A chain that is missed cannot be mis-counted: the final aggregate simply
stays incomplete until its replica + report exist.

| | |
|---|---|
| Actor | operator (admin keyset) |
| Chain | every chain, one transaction each — identical `code` |
| Sender / gas | operator's gas account, self-paid (admin ops are never sponsored) |
| Verification | `devnet-verified` (2026-07-18: identical 2-chain replicas verified equal + duplicate-id and sub-72h rejections) + `network-proven` (pre-reset 20-chain announcements) |

## The signable command (repeat per chain — only `meta.chainId` changes)

```json
{
  "networkId": "$NETWORK",
  "payload": {
    "exec": {
      "code": "($NS.smartpacts-shares.create-proposal \"<ID>\" \"<TITLE>\" \"<DESCRIPTION>\" (time \"<CREATED_AT_ISO>\") <DURATION_SECONDS>)",
      "data": {}
    }
  },
  "signers": [
    { "pubKey": "<ADMIN_PUBKEY_HEX>" }
  ],
  "meta": {
    "chainId": "<each chain>",
    "sender": "<ADMIN_GAS_ACCOUNT>",
    "gasLimit": 5000,
    "gasPrice": 0.00000001,
    "ttl": 28800,
    "creationTime": "<unix-seconds, backdated ~30 s>"
  },
  "nonce": "<unique per chain>"
}
```

- `CREATED_AT_ISO` — an explicit timestamp slightly in the past (e.g. chain block-time
  −60 s), **identical on every chain**; `close-at = created-at + duration` everywhere.
  Never hand-adjust it per chain.
- `DURATION_SECONDS` — on-chain bounds: **min 259200 (72 h), max 1209600 (14 d)**.
- The admin signer is unscoped (the admin gate is a bare keyset check). With a multi-key
  admin keyset, add one signer entry per required key.
- `ttl` 28800 (8 h) so a slow multi-chain signing session cannot expire mid-batch.

## Mandatory follow-up: verify replication

Read back from **every** chain and compare — `close-at` and `status: "active"` must be
identical everywhere:

```pact
($NS.smartpacts-shares.proposal-details "<ID>")
```

## Failure modes

| Error | Meaning / fix |
|---|---|
| `duration below 72h minimum` / `above 14d maximum` | pick a compliant window |
| `created-at cannot be in the future` | your timestamp is ahead of that chain's block-time — backdate |
| `close-at already passed on this chain` | announced too late relative to created-at — re-issue with a fresh window |
| `row found for key` | duplicate id — ids are permanent, pick a new one |
| some chains missing | signing loop died — re-run those legs (safe: duplicates are rejected) and re-verify |
