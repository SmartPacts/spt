# Testnet vs. mainnet: the two contract lineages

This repository carries the SPT contracts in two directories, and the difference between them is
the point of this page.

| Directory | What it is | How to check it |
|---|---|---|
| [`contracts/testnet06/`](../contracts/testnet06/) | **The live deployment.** Byte-identical to the source stored on all 20 chains of the Kadena community testnet. | `cd scripts && node verify.mjs` — byte-compares every file against the live network. |
| [`contracts/mainnet/`](../contracts/mainnet/) | **The mainnet release candidate. Not deployed — published for review.** | `cd scripts && node compare-lineages.mjs` — proves it is exactly the deployed system minus the differences listed below. |

## The disclaimer, plainly

**No mainnet deployment exists, and nothing in this repository implies one is scheduled.** The
candidate is published so that anyone reviewing the code can read the version that would carry
real value — instead of reverse-engineering it from the test deployment. It becomes final only at
the pre-mainnet freeze, after a full re-audit, and the frozen artifact will be tagged here.

"Nothing taken on trust" still holds, with honesty about what each check proves: the testnet
lineage is verified **against a live chain**; the candidate is verified **against the testnet
lineage** — a mechanical proof that it is the same tested system, with every difference enumerated.

## Why two versions exist at all

A public test event is a *lifecycle*: contracts get deployed, exercised, upgraded in place, and
migrated — and honest operations leave visible traces in the deployed source (a one-shot migration
function, upgrade history in [DEPLOYMENTS.md](DEPLOYMENTS.md)). A fresh mainnet deployment has no
such history: it writes its full schema on day one and never migrates. Publishing only the
testnet version would make reviewers wade through machinery that will never ship to mainnet;
publishing only a "clean" version would break the byte-for-byte match with the live chain. So:
both, with the bridge between them checkable.

## The exact differences

This list is duplicated in executable form in
[`scripts/compare-lineages.mjs`](../scripts/compare-lineages.mjs) — the script fails if the
lineages ever drift beyond it.

1. **`migrate-adr015` (testnet only).** The one-shot, self-guarding data migration that healed the
   in-place dividend-accrual upgrade of 2026-07-05 (see DEPLOYMENTS.md). It ran once per chain, is
   permanently inert ("already migrated"), and stays in the deployed source as the honest record of
   how the upgrade happened. A fresh mainnet deployment writes the full schema at `init` and never
   needs it — so the candidate does not carry it.

2. **The admin keyset name.** The testnet source hardcodes its namespace
   (`n_d97ffd2c….spt-admin`); the candidate derives it from the deploy transaction
   (`(format "{}.spt-admin" [(read-msg 'ns)])`). Same trust model — the deployer controls the
   value either way — but no per-network source edit and no substitution step at deploy time. The
   mainnet namespace does not exist yet (it is created by a key ceremony at deployment), which is
   also why the candidate cannot hardcode one.

3. **The gas station's sponsored-call allowlist.** Same change, same reason: the two allowlisted
   call prefixes derive their namespace from the deploy transaction instead of hardcoding it.

4. **Token identity constants (candidate only).** `NAME` ("Smart Pacts Token") and `SYMBOL`
   ("SPT") as constants in `smartpacts-shares` — self-documentation readable via
   `describe-module`. No wallet or explorer consumes such constants today; they are added to the
   candidate (not retrofitted to testnet) because constants are compiled code — the module hash
   changes — and the only free moment to add them is before a hash-anchored deployment exists.

6. **Gas-ceiling positivity guard (candidate only, temporary).** The candidate's gas station
   additionally rejects a non-positive gas price/limit (`> 0`), on top of the existing
   at-or-below-ceiling checks — defense in depth, so the contract no longer relies on Chainweb
   rejecting such values upstream. A hardening surfaced by an external community red-team; it is in
   the candidate now (pre-freeze is the free moment) and will also land on the testnet lineage when
   that is next re-frozen. Not a permanent architectural split — a pending improvement.

7. **`account-votes` post-close note (candidate only, temporary).** A schema-doc note recording
   that the `weight <= balance` invariant holds only while a proposal is active; after close the
   row is inert history that nothing reads (documentation, not behavior). Same red-team origin and
   same temporary status as #6.

8. **A review banner** at the top of each candidate file, so the file itself says what it is even
   when read in isolation.

Nothing else differs — not a function and not a check; the only constants that differ are the
identity pair above and the namespace-derived values in (2) and (3).

## What the tests say

The full regression suite ([`tests/`](../tests/)) runs against the deployed testnet lineage.
Because the candidate is code-identical minus the list above, those results transfer; what needs
proving separately is exactly the delta, and
[`tests/mainnet-lineage.repl`](../tests/mainnet-lineage.repl) does that: the candidate deploys
fresh into an arbitrary namespace with nothing in the source pinning one, the derived constants
resolve correctly, and the dividend core (declared round → exact accrual → exact liability) runs
on it end-to-end. The three `smartpacts-upgrade*` suites apply only to the testnet lineage — they
test the upgrade-and-migrate lifecycle, which is precisely what the mainnet candidate does not
have.
