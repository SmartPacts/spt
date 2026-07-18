# The gas station

*This page documents the registry-driven gas station carried in
[`contracts/mainnet/`](../contracts/mainnet/smartpacts-gas-station.pact) — the release-candidate
lineage that every future deployment (testnet and mainnet) will use. The station deployed during
the public test event ([`contracts/testnet06/`](../contracts/testnet06/smartpacts-gas-station.pact))
was its simpler predecessor; the differences are enumerated and mechanically checked in
[TESTNET-VS-MAINNET.md](TESTNET-VS-MAINNET.md).*

## What it is

`smartpacts-gas-station` is an autonomous on-chain account that pays transaction gas for approved
operations. It exists so that:

- **shareholders vote and claim dividends with ZERO KDA** — you never need to hold the network's
  coin just to exercise your rights;
- **platform operations run without personal gas keys** — internal actions (funding a dividend
  round, declaring a round, launch-review decisions) are sponsored by the same station, under the
  same public rules, instead of by ad-hoc personal wallets.

One module, one funded account per chain, one public policy for everything it pays for.

## How approval works

Sponsorship is an **on-chain registry** — a table with one row per approved operation. A row is
keyed by the operation's exact function-call prefix (for example
`(<namespace>.smartpacts-shares.cast-vote ` — note the trailing space, which makes the match a
whole-token match: a prefix can never accidentally match a longer, different function name).
Each row carries:

- its own **per-transaction gas ceiling** — a sponsored transaction may not bid more gas than the
  operation needs;
- its own **daily budget** (an epoch cap with on-chain spend accounting) — the total the station
  will sponsor for this operation per epoch;
- an **enabled/disabled switch** — disabling a row stops its sponsorship instantly (this is also
  how an operation is *removed* from sponsorship: the row and its lifetime accounting remain
  on-chain as auditable history);
- **lifetime spend accounting** — how much the station has ever paid for this operation.

Registering, changing, or disabling an operation is a single admin transaction (`set-entry`), and
**every such change emits a public `ENTRY-SET` event**. That means the full history of the
sponsorship policy is auditable from the event stream, and the current policy is one read away:
`(list-entries)`.

Granting sponsorship to a *future* module needs no code change and no upgrade — one admin
transaction adds the row. The prefixes are plain data, so nothing about a deployment is baked
into the source.

## The security model, honestly

What the station enforces, all of it on-chain:

- **Exec-only, exactly one call.** A sponsored transaction must be a plain execution whose code
  is exactly one registered call — read from the signed envelope the node itself parsed, not from
  anything the sender claims. Multi-call transactions, and defpact continuations (which carry no
  code that could be checked), are refused outright.
- **A global gas-price ceiling** (10⁻⁶ KDA/gas) — every sponsored transaction must bid at or
  below it, and both gas price and limit must be strictly positive (defense in depth: the node
  already rejects non-positive values before any contract code runs).
- **Per-entry gas-limit ceilings** — each operation's transactions are capped at what that
  operation actually needs (a vote gets vote-sized gas, never more).
- **Per-entry daily budgets** — every sponsored transaction pre-charges its worst-case cost
  against its entry's epoch cap. One operation's exhaustion — or deliberate abuse — never
  starves another operation's budget.
- **A global daily backstop** (2.0 KDA per chain per day) on top of the per-entry budgets, so
  even the sum of all entries is bounded.
- **Fail-closed, time-only resets.** Any check that cannot pass means the station simply does
  not pay. Budget epochs roll over on block time only — an attacker cannot buy, trigger, or
  hurry a reset. When a budget is exhausted, the worst case is that the operation costs normal
  gas until the next epoch.
- **An unregistered call is refused when the node validates the gas purchase** — the transaction
  never enters a block and costs the station nothing.
- **The station account is locked to its job.** Its KDA sits in a principal account guarded so
  funds move ONLY inside a sanctioned sponsored gas purchase, or by the admin keyset (for
  funding and recovery).

And the part you should evaluate skeptically: **the admin keyset can register any operation, at
any time, forever** — the registry deliberately stays writable even after the module's code is
frozen. This grants no new power: the same keyset already owns the KDA the station spends, so
"can sponsor anything" was always true economically. What the design adds is that every policy
change is a public, evented, on-chain fact. Mutability-with-public-events is the trust model —
you are not asked to trust that policy won't change, you are given the tools to see every change
the moment it happens.

## Supported operations

The registry as configured at publication (2026-07-18):

| Operation | Who it serves | Per-tx gas ceiling | Daily budget |
|---|---|---|---|
| `smartpacts-shares.cast-vote` | shareholders (gasless voting) | 1,500 | 0.15 KDA |
| `smartpacts-shares.claim-dividends` | shareholders (gasless claims) | 1,500 | 0.15 KDA |
| `smartpacts-shares.fund-dividends` | operations (dividend funding) | 3,000 | 0.15 KDA |
| `smartpacts-shares.declare-round` | operations (dividend rounds) | 1,500 | 0.05 KDA |
| `sp-launchpad.register` | the launch-review operator | 1,500 | 0.05 KDA |
| `sp-launchpad.reject` | the launch-review operator | 1,500 | 0.05 KDA |
| `sp-launchpad.deregister` | the launch-review operator | 1,500 | 0.05 KDA |

Budgets and entries are **per network and may evolve**; the on-chain registry —
`(list-entries)` plus the `ENTRY-SET` event stream — is always the authoritative live list.

## Verify, don't trust

On any network carrying this station (all reads are free `local` calls; `<ns>` is the
deployment's namespace):

```pact
<ns>.smartpacts-gas-station.GAS_STATION          ; the station account name
(<ns>.smartpacts-gas-station.list-entries)       ; the FULL current policy + all meters
(<ns>.smartpacts-gas-station.get-epoch-spent)    ; KDA sponsored in the current global epoch
(<ns>.smartpacts-gas-station.allowlisted? "(<ns>.smartpacts-shares.cast-vote \"k:you\" \"P1\" true)")
                                                 ; would THIS exact code be sponsored?
(coin.get-balance <ns>.smartpacts-gas-station.GAS_STATION)  ; the station's float
```

- **Watch `ENTRY-SET` events** to see every sponsorship-policy change as it happens.
- **Check the module hash** (`(at 'hash (describe-module "<ns>.smartpacts-gas-station"))`)
  against this repository's source — the station you are trusting is the station you can read.

## How to use it (the gasless transaction shape)

One transaction, shaped like this — using a vote as the example:

- **code:** exactly one sponsored call, nothing else:
  `(<ns>.smartpacts-shares.cast-vote "k:<you>" "<proposal-id>" true)`
- **meta:** `sender` = **the station account** (read it once from
  `<ns>.smartpacts-gas-station.GAS_STATION`); gas limit at or below the entry's ceiling
  (1,500 for a vote), gas price at or below 0.000001.
- **signers:**
  - your key, scoped to your own action's capability
    (`<ns>.smartpacts-shares.VOTE "k:<you>"`) — this is your authorization;
  - any key, scoped to `<ns>.smartpacts-gas-station.GAS_PAYER "<any>" 1500 0.000001` — this
    merely *requests* sponsorship and carries **no authority**; your own key can sign both.

You spend zero KDA. If the station refuses (`Not a sponsored call`, `entry epoch cap reached`,
`global epoch cap reached`, `Gas limit must be <= …`), the same code always works self-paid:
set yourself as sender with the ordinary `coin.GAS` capability.

## Upgrade discipline

One rule binds every future version of this module: the station account's guard resolves the
predicate functions `station-guard-pred` and `gas-payer-pred` **by name**. Any upgrade must keep
those names (and the guard construction) exactly — renaming them would brick the funded account.
The lineage comparison ([`scripts/compare-lineages.mjs`](../scripts/compare-lineages.mjs)) checks
this mechanically, and the adversarial test suite
([`tests/mainnet-gas-station.repl`](../tests/mainnet-gas-station.repl)) attacks the rest of the
policy surface: prefix-boundary spoofs, call smuggling, budget exhaustion and isolation, meter
protection, kill-switch behavior, and upgrade survival of all registry state.

The candidate went through a two-pass fresh-context security review — findings, dispositions,
and the live-network evidence are published in
[`audits/2026-07-gas-station-registry-review.md`](../audits/2026-07-gas-station-registry-review.md).
