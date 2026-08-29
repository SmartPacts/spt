# SPT — Smart Pacts Token

SPT is a token on [Kadena Community Edition](https://kda-chain.org) with governance and awards built into the contract
itself: holders vote on proposals weighted by what they hold, and awards accrue in KDA and never
expire. It is two Pact modules, a fixed supply of 100,000, and no mint path after setup.

> ## 🟢 DEPLOYED — Kadena mainnet (`mainnet01`)
>
> Since 2026-08-28 these contracts run on Kadena mainnet under the namespace
> `n_48867b242317a0216a67f8c7ca26696b5878e0e3`: `SPT` on all 20 chains, and `SPT-launch` (the
> sale) on chain 0 only. **The code on chain is byte-for-byte the module form in `deploy-bytes/`**
> — measured against chain 0 on 2026-08-29 — and `VERIFY.md` §3 shows how to check that yourself
> in three commands, with no account and no wallet.
>
> Nothing is in circulation yet. The contract is **not yet frozen**, so until it is the `spt-gov`
> keyset can still upgrade it; freezing is permanent. The sale opens on 1 September 2026 at
> 16:00 UTC at [smartpacts.io/sell](https://smartpacts.io/sell/), and
> [smartpacts.io/transparency](https://smartpacts.io/transparency/) reads every contract figure
> live — where the tokens are, what is time-locked and until when, and what the administrator
> can and cannot do.

## Which file am I reading?

This is the single most important thing to get right, so the repository makes it structural:

| | |
|---|---|
| **`deploy-bytes/SPT.pact`** · **`deploy-bytes/SPT-launch.pact`** | 🔴 **THE BYTES THAT DEPLOY.** Exactly the payload submitted to the chain — no comments, nothing added. `SHA256SUMS` covers them. |
| **`pact/modules/SPT.pact`** · **`pact/modules/SPT-launch.pact`** | The **annotated source**: the same program with the reasoning left in. Every file carries a header saying so. |

They are **the same program**. A Pact module hash excludes `;;` comments, so both carry the same
module hash — and CI proves the stronger claim on every push: stripping the annotated source
produces the deploy bytes **byte for byte**. Read the annotated copy; audit either.

Nothing else in this repository deploys.

## What is in here

```
deploy-bytes/     the exact payload, and its SHA256SUMS
pact/modules/     the annotated source
pact/test/        the full test suite — 58 files, run by pact/test/run-tests.sh
.github/scripts/  the gates the suite runs (static analysis, deploy budget,
                  hash baseline, DML surface, negative-test arity, promise gate)
tools/            check-namespace.sh
verification/     the recorded artifact identity
docs/             SPT-WHAT-IT-DOES.md — plain language, written for a non-engineer
audits/           an independent review of these exact bytes
VERIFY.md         how to check this repository — locally, and against the chain
```

## Run the tests yourself

You need the [Pact 5.4ce](https://github.com/kda-community/pact-5) binary on your PATH, plus `python3`.
That is the Community Edition engine — the one this artifact is measured against, and the one CI
pins by content hash. See [kda-chain.org](https://kda-chain.org).

```bash
cd pact/test && ./run-tests.sh
```

That is the same command CI runs, with no reduced subset — a CI that runs less than you do
teaches you to trust a green tick that means less than you think. It runs every suite, every
negative fixture, and every gate, and prints `ALL SUITES PASS` or names what failed.

## Two admin tiers

| tier | threshold | what it can reach |
|---|---|---|
| `spt-gov` | **2 of 3** devices | anything irreversible, or that moves value out — upgrades, the freeze, disbursing company tokens, withdrawing funds, funding the award pool, declaring an award round, setting the sale price, changing a limit |
| `spt-ops` | **any 1 of 3** | reversible day-to-day work — announcing a proposal or cancelling one before it opens, opening and closing the sale, scheduling or cancelling a record date, withdrawing a declared round before it takes effect, operating *within* a limit |

The split is enforced in the contract and covered by named negative tests: each tier is proven to
**refuse** the other's authority, not merely to accept its own.

## What SPT cannot do

- **Mint beyond 100,000, or burn.** Supply is fixed once setup completes; there is no mint path.
- **Move your tokens without your signature.** Every account is guarded.
- **Let one device do everything.** See the tiers above.
- **Be upgraded after the freeze.** Freezing is permanent and deliberate.

Read [`docs/SPT-WHAT-IT-DOES.md`](docs/SPT-WHAT-IT-DOES.md) for the long version in plain
language, including what is *not* guaranteed — it is more useful than this section.

## Reporting a problem

See [`SECURITY.md`](SECURITY.md). There is no bug bounty; there is a real address and a
commitment to answer.

## Licence

Apache-2.0 — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
