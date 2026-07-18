# TX-11 — Read everything: discovery, tallies, registrations, the final result

Every read is a free `/local` call — no keys, no signatures, no account:

```
POST $API/chainweb/0.0/$NETWORK/chain/$CHAIN/pact/api/v1/local
{ "cmd": "<serialized payload with signers: []>", "hash": "<blake2b of cmd>", "sigs": [] }
```

with the payload's `code` set to one of the expressions below (`meta.sender` may be any
string, `gasLimit` 150000, `gasPrice` 0.00000001).

| Verification | `devnet-verified` (2026-07-18 — every read below exercised during the rehearsal) |
|---|---|

## Discover proposals

There is **no single "list proposals" function**. What exists:

- **Currently-indexed proposals, one call** (composes public helpers with a direct table
  read — this is the full discovery surface a third party has today):

  ```pact
  (map (lambda (i:integer)
         ($NS.smartpacts-shares.proposal-details
           (at 'id (read $NS.smartpacts-shares.prop-index ($NS.smartpacts-shares.pkey i)))))
       ($NS.smartpacts-shares.active-prop-indices))
  ```

  ⚠ Two caveats: (1) the index holds proposals until the operator *closes* them, so an
  entry can be past its `close-at` — always filter on `status == "active"` AND
  `close-at` in the future; (2) closed/cancelled proposals leave the index — historical
  discovery needs the `PROPOSAL-CREATED` event stream (block explorer / indexer), not a
  read.

- **One known id** (throws if the id was never announced on this chain — the only read
  that proves existence): `($NS.smartpacts-shares.proposal-details "<ID>")`
  → `{ title, description, created-at, close-at, status, active-slot }`

## Tallies and results

```pact
($NS.smartpacts-shares.get-results "<ID>")        ; THIS chain's running/frozen tally
($NS.smartpacts-shares.get-final-results "<ID>")  ; chain 0 ONLY: the canonical aggregate
```

- `get-results` per chain is advisory while voting runs; it freezes at `close-at`.
- `get-final-results` → `{ yes, no, participation, quorum-met, passed, complete,
  chains-reported }`. **Only `complete: true` (all 20 chains reported) makes `passed`
  meaningful** — a partial aggregate can never read `passed: true`.
- ⚠ `get-final-results` returns **zeros (not an error) for an id that does not exist** —
  it cannot prove existence; pair it with `proposal-details`.

## A voter's own state

```pact
($NS.smartpacts-shares.vote-weight "<ACCOUNT>" "$CHAIN" "<ID>")  ; recorded weight (0 if none)
($NS.smartpacts-shares.get-vote    "<ACCOUNT>" "$CHAIN" "<ID>")  ; { weight, direction } — throws if never voted
($NS.smartpacts-shares.get-vote-key "<ACCOUNT>")                 ; { guard, active } voting-key registration
($NS.smartpacts-shares.get-balance "<ACCOUNT>")                  ; = live voting weight on this chain
($NS.smartpacts-shares.pending-dividends-of "<ACCOUNT>")         ; claimable distributions here
```

## Governance events (explorer / indexer surface)

| Event | Emitted on |
|---|---|
| `PROPOSAL-CREATED (id title)` | every replica announcement |
| `VOTE-CAST (voter proposal weight direction)` | every vote / re-vote |
| `VOTE-RELEASED (voter proposal amount)` | a transfer releasing voted weight |
| `VOTE-KEY-SET (account key)` / `VOTE-KEY-CLEARED (account)` | voting-key changes |
| `PROPOSAL-CLOSED (id status)` | close (`"closed"`) and cancel (`"cancelled"`) |
| `TALLY-REPORTED (proposal chain yes no)` | each accepted per-chain report on the hub |
