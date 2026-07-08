# External red-team — SmartPacts / SPT (July 2026)

- **Auditor:** Oberlus / DNNS (community security), good-faith engagement invited by the maintainer.
- **Target:** the three Pact modules in [`contracts/testnet06/`](../contracts/testnet06/) — `smartpacts-shares`, `smartpacts-ipo`, `smartpacts-gas-station` — namespace `n_d97ffd2ca290429b5dc85ce551a8d07d038e9641`, Kadena testnet06.
- **Date:** 2026-07-08.
- **Method:** executed attacks (real `.repl` runs against the Pact 5.4 interpreter using this repo's own harness and fixtures), not paper review. Two engines — reverse-coverage (inverting the documented defenses) and invariant hunting (properties the code satisfies but never states) — a 20-mutation-per-front depth standard, differential-oracle testing with a negative control, and an artifact filter that discards any "break" depending on REPL-only primitives (`test-capability`, `coin.GAS`, single-DB 20-chain simulation) so the verdict reflects on-chain behavior.

## Result

**88 executed attacks across 12 fronts, plus a 20-mutation differential deep-dive on the dividend accounting. Zero confirmed vulnerabilities — the contracts held on every front.**

| Front | Module | Attacks | Verdict |
|---|---|---|---|
| Gas-station drain / sponsorship abuse | gas-station | 6 | held |
| Dividend solvency | shares | 8 | held |
| Dividend fairness under share movement | shares | 7 | held |
| Vote double-counting | shares | 7 | held |
| Tally freeze / report injection | shares | 5 | held |
| Time-locks / tranches | shares | 7 | held |
| Reserve extraction | shares / ipo | 6 | held |
| Fixed supply / mint surface | shares | 17 | held |
| Dedicated voting key | shares | 6 | held |
| Initial sale (IPO) | ipo | 6 | held |
| Upgrade / migration | shares | 6 | held |
| Arithmetic / precision | shares | 7 | held |

### Dividend accounting deep-dive (differential oracle)

The most dangerous DeFi bug class is drift between an O(1) aggregate and the O(n) reality. The dividend accounting was swept with 20 mutations (extreme rates, temporal boundaries, wash-churn, dust at 1e-12, splitting a holder into sub-accounts, zero-float rounds, excluded reserves) while asserting, after every step, that the contract's O(1) liability equals a naive O(n) sum over all accounts. A **negative control** (deliberately amputating the O(n) reference) confirmed the oracle would diverge on a real double-count — so the 20/20 agreement is a positive signal, not a tautology. Solvency, rounding sub-additivity (`Σ floor(owed_i) ≤ floor(Σ owed_i)` — splitting never wins), and no-double-pay held throughout.

## Observations (defense-in-depth — not vulnerabilities)

Two hardening notes surfaced; neither is exploitable, and both are already being addressed in PR #6:

- **O1 — gas-ceiling positivity.** The gas-station price/limit ceilings use `<=` only, accepting values ≤0. Not exploitable (the protocol rejects such values before the contract, and the per-epoch counter charges the maximum regardless), but adding `(> price 0)` / `(> limit 0)` is good hygiene.
- **O2 — dangling vote row after close.** After a tally freezes at `close-at`, an `account-votes` row can be left with `weight > balance` if shares move afterward. Cosmetic only — the tally is frozen, no second vote is possible, and the final result copies the frozen tally, so there is no double-count.

## Scope and honest limits

- REPL-based: cross-chain SPV paths (transfer step 2, tally reports to the hub) cannot be exercised in the REPL and were not tested here — they require a multi-chain devnet, as the project's own notes state.
- Residual trust (unchanged by this review): modules are upgradeable under the admin keyset until `FROZEN-MODULE`; that is an accepted trust assumption, not a finding.
- "Held after 88 executed attacks" is an independent adversarial signal, not a proof of absence of all bugs.

## Reproducibility

Every attack is a runnable `.repl` against this repo's harness; the full suites are available on request. The general methodology (offensive skill, `/red-team` command, attacker agent) has been contributed to the community toolkit at `Pact-Community-Organization/pact-kit`.

_Published with the maintainer's request and permission._
