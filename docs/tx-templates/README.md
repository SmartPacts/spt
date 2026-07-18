# Governance transaction templates

The complete, signable transaction for **every governance operation** of the SPT
test-share system — everything a third-party client (CLI script, dapp, wallet
integration) needs to vote, claim, and report **without any of our tooling**. Nothing
here requires a special SDK: any ed25519 + blake2b-256 implementation can produce these
transactions.

> Testnet only, valueless test tokens, advisory votes — everything in
> [the event guide](../EVENT-GUIDE.md)'s disclaimers applies here.

## Parameters

Every template uses these placeholders — resolve them once:

| Placeholder | Meaning | Current value |
|---|---|---|
| `$API` | Chainweb service API base URL | `https://api.testnet.chainweb-community.org` |
| `$NETWORK` | network id | `testnet06` |
| `$NS` | the deployment namespace | `n_d97ffd2ca290429b5dc85ce551a8d07d038e9641` |
| `$CHAIN` | a chain id, `"0"`–`"19"` (chain `0` = hub: supply + final aggregation) | per operation |

Module references are always namespace-qualified: `$NS.smartpacts-shares`,
`$NS.smartpacts-gas-station`. After any network reset or redeployment these values are
re-confirmed in [VERIFICATION.md](../VERIFICATION.md) — the templates themselves stay
valid unchanged.

## Index

| Template | Operation | Actor | Gas |
|---|---|---|---|
| [TX-01](TX-01-cast-vote-gasless.md) | Cast / change an advisory vote — **gasless** | holder (zero KDA needed) | station-paid |
| [TX-02](TX-02-cast-vote-self-paid.md) | Cast / change an advisory vote — self-paid | holder | self |
| [TX-03](TX-03-set-vote-key.md) | Register / replace a dedicated voting key | holder (MAIN key) | self |
| [TX-04](TX-04-clear-vote-key.md) | Deactivate the voting key | holder (MAIN key) | self |
| [TX-05](TX-05-claim-distributions-gasless.md) | Claim accrued distributions — **gasless** | anyone (pays the holder) | station-paid |
| [TX-06](TX-06-create-proposal.md) | Announce a proposal (identical replica per chain) | operator | self |
| [TX-07](TX-07-close-proposal.md) | Close a proposal after its deadline | operator | self |
| [TX-08](TX-08-cancel-proposal.md) | Cancel a still-running proposal | operator | self |
| [TX-09](TX-09-report-tally-hub.md) | Report chain 0's frozen tally (hub) | anyone | self |
| [TX-10](TX-10-report-tally-xchain.md) | Carry a non-hub chain's tally to the hub (2-step) | anyone | self / station |
| [TX-11](TX-11-reads-discovery.md) | Read everything: discovery, tallies, final result | anyone | free (`/local`) |

## The command envelope (shared by every template)

A Kadena transaction is a JSON **command** submitted to
`POST $API/chainweb/0.0/$NETWORK/chain/$CHAIN/pact/api/v1/send` as
`{"cmds":[{ "cmd": <string>, "hash": <string>, "sigs": [ {"sig": <hex>} … ] }]}`:

- `cmd` — the **exact JSON string** serialization of the payload object shown in each
  template. The signature covers these bytes; build the object, `JSON.stringify` it once,
  and never re-serialize.
- `hash` — blake2b-256 of the `cmd` string, base64url without padding. This is also the
  request key you poll on `…/api/v1/poll`.
- `sigs` — ed25519 signatures **over the hash bytes**, hex-encoded, **one per entry in
  `signers`, in the same order**.

Payload object shape (exec):

```json
{
  "networkId": "$NETWORK",
  "payload": { "exec": { "code": "<pact code>", "data": { } } },
  "signers": [ { "pubKey": "<hex>", "clist": [ { "name": "<cap>", "args": [ ] } ] } ],
  "meta": { "chainId": "$CHAIN", "sender": "<gas payer account>",
            "gasLimit": 0, "gasPrice": 0, "ttl": 1800, "creationTime": 0 },
  "nonce": "<any unique string>"
}
```

Conventions the node enforces:

- **Typed arguments in `clist.args`:** decimals as `{"decimal":"0.000001"}`, integers as
  `{"int":"1500"}` (strings inside), plain strings/booleans as JSON strings/booleans.
  A bare JSON float where a decimal is expected changes the capability's identity and the
  signature will not match the acquired capability.
- **`creationTime`** is unix **seconds** and must not be ahead of chain block-time —
  backdate it ~15–60 s (block-time can lag wall clocks).
- **Scoped vs unscoped signatures:** a signer **with** a `clist` authorizes *only* those
  capabilities; a signer with **no** `clist` field is unscoped (authorizes any guard its
  key satisfies — avoid for holder keys; every holder template here is scoped).
- Reads cost nothing: `POST …/api/v1/local` with the same payload shape, `signers: []`,
  `sigs: []` (see TX-11).

## The sponsored (gasless) envelope

TX-01, TX-05 and the TX-10 continuation are paid by the **station** — the system's
sponsorship account (see [GAS-STATION.md](../GAS-STATION.md)). The station only releases
its funds when the transaction matches ALL of the following (drain protection; any
mismatch = refusal):

1. `meta.sender` = the station account — read it once:
   `/local` → `$NS.smartpacts-gas-station.GAS_STATION`.
2. `meta.gasLimit` ≤ **1500** and `meta.gasPrice` ≤ **0.000001**.
3. The code is **exactly one call** to a sponsored function
   (`$NS.smartpacts-shares.cast-vote` or `$NS.smartpacts-shares.claim-dividends`) —
   nothing else in `code`, one top-level expression, fully namespace-qualified.
4. One signer requests sponsorship by including the capability
   `$NS.smartpacts-gas-station.GAS_PAYER` in its `clist`. The capability's arguments
   carry **no authority** — any key may sign it (conventionally
   `["<account>", {"int":"1500"}, {"decimal":"0.000001"}]`).
5. The station has daily budget left (per-chain aggregate cap; when exhausted:
   `gas station epoch cap reached` — retry next epoch or self-pay).

You may additionally mirror the executed code into `payload.exec.data` as
`"tx-type": "exec"` + `"exec-code": ["<code>"]` (for a continuation:
`"tx-type": "cont"`). This is **not required** — the node itself injects the
transaction type and the actually-executed code into the sponsorship check, so the
allowlist cannot be spoofed and needs nothing from you. The mirror is a harmless,
long-proven belt-and-braces shape; verified both ways (2026-07-18).

## Verification labels

Each template carries a verification row: `devnet-verified (2026-07-18)` = the exact
transaction shape was executed end-to-end against **this repository's
`contracts/testnet06/` sources** on a local development network rehearsal;
`network-proven (pre-reset)` = additionally exercised on public testnet06 before its
reset. After the network returns, VERIFICATION.md re-anchors the live values.
