# Independent review — the registry-driven gas station (mainnet release candidate)

| | |
|---|---|
| **Target** | [`contracts/mainnet/smartpacts-gas-station.pact`](../contracts/mainnet/smartpacts-gas-station.pact) |
| **Suite** | [`tests/mainnet-gas-station.repl`](../tests/mainnet-gas-station.repl) (adversarial) + [`tests/mainnet-lineage.repl`](../tests/mainnet-lineage.repl) (smoke) |
| **Reviewer** | internal, independent — fresh context, no implementation history, code read cold |
| **Method** | two passes: a full structured audit, then a delta re-review after its findings were fixed |
| **Date** | 2026-07-18 |
| **Verdict** | **GO** as a mainnet release candidate (the pre-mainnet freeze re-audit gate in the file banner stands) |

This is the project's internal review discipline, published for transparency. It is **not** an
external third-party audit — that remains planned on the frozen source before any mainnet
deployment (see [SECURITY-MODEL.md](../docs/SECURITY-MODEL.md), "Review status").

## Result summary

**No CRITICAL, HIGH, or MEDIUM findings** in either pass. Two LOW findings in the first pass,
both closed the same day and re-verified in the delta pass:

| # | Severity | Finding | Disposition |
|---|---|---|---|
| 1 | LOW | `init` was a public function with unguarded writes (not exploitable: on a live station both writes fail closed, and the account guard is hardcoded to the module's own guard — defense-in-depth gap only) | **Fixed**: `init` now runs under the governance capability; a negative test pins that a non-admin call fails |
| 2 | LOW (liveness) | Freeze composition: after the one-way code freeze, the 32-entry registry bound can never be raised — a frozen station with a full registry could never onboard a 33rd distinct operation | **Dispositioned**: the in-source trust-model text now states the bound freezes with the code and must be confirmed (or raised) *before* any freeze; final confirmation is part of the pre-freeze re-audit |
| — | INFO | With `init` governance-gated, a *fresh* deploy of a source already set to frozen would abort at the deploy footer's `init` (the normal freeze path — an in-place upgrade — is unaffected; expanding a frozen station to a new chain takes deploy-then-freeze, two transactions) | Recorded for the freeze runbook |

## Properties the reviewer verified sound

- **Drain defense, fail-closed end to end:** the pay permission is composed only after
  exec-only + single-call + prefix-match + enabled + gas-price + gas-limit + per-entry budget +
  global budget all pass; any abort means the station pays nothing. Budgets charge the
  *worst-case* transaction cost up front, so caps bite early, never late.
- **Weak-capability containment:** the internal permission tokens cannot be acquired from
  outside the module (pinned by tests); the budget meters cannot be charged externally; no
  public path reaches a privileged write without a real guard.
- **At-most-one-match by construction:** registered prefixes must contain exactly one space
  (the trailing one), so no registered prefix can ever contain another — at most one registry
  row can match any transaction code.
- **Node-safety of every `enforce`:** no table read or write sits inside an enforce condition
  (a class of defect that passes in the offline interpreter but fails on the live node).
- **Upgrade and deploy modes:** fresh / migrate-from-the-prior-design / plain upgrade all
  fail closed on double-runs; registry rows and meters provably survive an in-place upgrade.
- **Guard-machinery identity:** the funded station account resolves its guard predicates by
  name; the review confirmed they are code-identical to the deployed lineage (also asserted
  mechanically by [`scripts/compare-lineages.mjs`](../scripts/compare-lineages.mjs)).

## Suite gaps named by the reviewer — all closed

1. a fail-closed test for a malformed (single-character string) transaction-code envelope;
2. a negative test for non-admin `init`;
3. a proof that an entry's budget epoch rolls on its **own** clock while the global 24-hour
   meter keeps accumulating (an hourly-budget entry: one sponsored transaction fits, the second
   within the hour is refused, the entry rolls after its hour, the global meter does not reset).

## Live-network evidence

Two properties cannot be proven in the offline interpreter and were demonstrated on a live
KDA-CE development network running this exact code (module hash
`CY7qCgs4ZRLinhCSLmUNTd7aFATmIL0NYEOPUtlw7zo`, stored source byte-equal to this repository's
file minus the review banner):

- **The sponsored hot path executes inside a real gas purchase**: a registered call was
  sponsored with the station as gas payer; the call failed in its own logic (by design of the
  probe), the station still paid the gas, and the on-chain budget meter advanced by exactly the
  worst-case charge — the griefing case behaves as documented, bounded and accounted.
- **The migration deploy mode** (upgrading over a live deployment of the prior
  constant-allowlist design) created the new tables while the existing meter row and funded
  station account survived.

An unregistered call, for comparison, is refused when the node validates the gas purchase — it
never enters a block and costs the station nothing.
