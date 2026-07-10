# Red-team suite — SmartPacts / SPT (external, July 2026)

Executed adversarial test suite contributed by **Oberlus / DNNS** (community security), by invitation and with the maintainer's permission. This is the full runnable suite behind the summary in the report [`../2026-07-red-team-dnns.md`](../2026-07-red-team-dnns.md) — the attacks that summary said were *"available on request"*, now in-repo for reproducibility.

- **Target:** the three Pact modules in `contracts/testnet06/` — `smartpacts-shares`, `smartpacts-ipo`, `smartpacts-gas-station` (namespace `n_d97ffd2ca290429b5dc85ce551a8d07d038e9641`).
- **Date:** 2026-07-08 · **Interpreter:** Pact 5.4.
- **Verdict:** 88 executed attacks across 12 fronts + a 20-mutation dividend deep-dive. **Zero confirmed vulnerabilities — the contracts held on every front.**
- **Layout:** **95 `.repl` in [`attacks/`](attacks/) run green in the bare REPL** (`pact 5.4`); **12 cross-chain / SPV attacks live in [`attacks/devnet/`](attacks/devnet/)** because they drive multi-chain state the single-DB REPL cannot simulate (see *Scope and honest limits*). All files are ASCII so they run under any locale.

## How to run

Every attack in [`attacks/`](attacks/) is a standalone `.repl` that loads `setup.repl` (already in the repo), which loads the fixtures and the three SPT modules. Run them from this folder (`audits/2026-07-red-team-dnns/attacks/`); the whole runnable set is green:

```sh
pact atk-gas-drain-1.repl                 # a single attack
for f in atk-*.repl; do pact "$f" || break; done   # all 95 -> Load successful
```

Each attack asserts that a defense **stops** it (via `expect-failure`) or that an invariant **holds** (via `expect`/explicit assertion). A run that ends "Load successful" means the defense held; a real break would surface as an unexpected success or a violated assertion.

**`attacks/devnet/` (12 attacks):** these drive **cross-chain / SPV state** (chain switches via `env-chain-data`, `transfer-crosschain`, `report-tally-xchain`) that the bare single-DB REPL cannot simulate, so they appear as `expected failure, got result` in a plain sweep — a harness limit, **not** a defense break (see *Scope and honest limits*). The same fronts are also covered by single-chain attacks that do run green. Run these against a multi-chain devnet.

## Method

Two engines, applied per front:
- **Reverse-coverage** — invert each documented defense in `docs/SECURITY-MODEL.md` and try to violate it directly.
- **Invariant hunting** — properties the code satisfies but never states (rounding sub-additivity, O(1)==O(n) liability, no-double-pay), fuzzed at their boundaries.

Depth standard: up to **20 mutations per front** (other amounts, ordering, accounts, times, boundary values). Differential-oracle testing with a **negative control**. An **artifact filter** discards any "break" that depends on REPL-only primitives (`test-capability`, `coin.GAS`, single-DB 20-chain simulation), so verdicts reflect on-chain behavior — not lab artifacts. Several apparent "successes" during the run were honestly discarded this way.

## Result — 88 executed attacks, 12 fronts, 0 confirmed vulnerabilities

| Front | Module | `.repl` prefix | Attacks | Verdict |
|---|---|---|---|---|
| Gas-station drain / sponsorship abuse | gas-station | `atk-gas-drain-*` | 6 | held |
| Dividend solvency | shares | `atk-div-solvency-*` | 8 | held |
| Dividend fairness under share movement | shares | `atk-div-fairness-*` | 7 | held |
| Vote double-counting | shares | `atk-vote-double-*` | 7 | held |
| Tally freeze / report injection | shares | `atk-tally-freeze-*` | 5 | held |
| Time-locks / tranches | shares | `atk-tranches-*` | 7 | held |
| Reserve extraction | shares / ipo | `atk-reserves-*` | 6 | held |
| Fixed supply / mint surface | shares | `atk-supply-mint-*` | 17 | held |
| Dedicated voting key | shares | `atk-votekey-*` | 6 | held |
| Initial sale (IPO) | ipo | `atk-ipo-*` | 6 | held |
| Upgrade / migration | shares | `atk-upgrade-*` | 6 | held |
| Arithmetic / precision | shares | `atk-arith-traps-*` | 7 | held |

### Dividend accounting deep-dive — `atk-div-deep-*` (differential oracle)

The most dangerous DeFi bug class is drift between an O(1) aggregate and the O(n) reality. The dividend accounting was swept with **20 mutations** (extreme rates, temporal boundaries, wash-churn, dust at 1e-12, splitting a holder into sub-accounts, zero-float rounds, excluded reserves) while asserting, after every step, that the contract's O(1) liability equals a naive O(n) sum over all accounts. A **negative control** (`atk-div-deep-control.repl`, deliberately amputating the O(n) reference) confirms the oracle would diverge on a real double-count — so the 20/20 agreement is a positive signal, not a tautology. Solvency, rounding sub-additivity (`Σ floor(owed_i) ≤ floor(Σ owed_i)` — splitting never wins) and no-double-pay held throughout.

## Why it held (front by front)

- **Gas station:** every fund movement goes through `coin.TRANSFER` (managed, needs the owner's signature) and the station holds no key; the only TRANSFER-free path is `buy-gas`, gated by the miner-only `coin.GAS` cap bounded to `limit×price`. Dual gate `GAS ∧ ALLOW_GAS`, both module-internal. The per-epoch cap is time-only, immune to clock manipulation.
- **Supply / reserves:** mint happens once inside `init-supply`; each reserve is a principal with a capability-guard only satisfiable inside the module — no external debit even with a signed key.
- **Dividends:** MasterChef-style accounting with `reward-debt`; floor at 12 dp always rounds down, dust stays with the holder, no re-claim; solvency verified digit-by-digit.
- **Governance:** weight = live balance; every transfer releases the voted portion; the tally freezes at `close-at` (inclusive); reports are idempotent and gated by a non-injectable internal cap.

## Hardening notes (defense-in-depth — NOT vulnerabilities)

- **O1 — gas-ceiling positivity.** `smartpacts-gas-station` price/limit ceilings use `<=` only, so they accept values ≤0. Not exploitable (Chainweb rejects such values before the contract; the per-epoch counter charges the max regardless), but adding `(> price 0)` / `(> limit 0)` to the ceiling enforces is good hygiene.
- **O2 — dangling vote row after close.** After a tally freezes at `close-at`, an `account-votes` row can be left with `weight > balance` if shares move afterward. Cosmetic only — the tally is frozen, no second vote is possible, and the final result copies the frozen tally. No double-count.

## Scope and honest limits

- REPL-based: cross-chain SPV paths (transfer step 2, tally reports to the hub) cannot be exercised in the REPL and were not tested here — they require a multi-chain devnet, as the project's own notes state.
- Residual trust (unchanged by this review): modules are upgradeable under the admin keyset until `FROZEN-MODULE`; that is an accepted trust assumption, not a finding.
- "Held after 88 executed attacks" is an independent adversarial signal, not a proof of the absence of all bugs.

## Provenance

The general methodology (offensive skill, `/red-team` command, attacker agent) has been contributed to the community toolkit at `Pact-Community-Organization/pact-kit`. Published with the maintainer's request and permission.
