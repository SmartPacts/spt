# Testnet vs. mainnet: the two contract lineages

This repository carries the SPT contracts in two directories, and the difference between them is
the point of this page.

| Directory | What it is | How to check it |
|---|---|---|
| [`contracts/testnet06/`](../contracts/testnet06/) | **The live deployment.** Byte-identical to the source stored on all 20 chains of the Kadena community testnet. | `cd scripts && node verify.mjs` — byte-compares every file against the live network. |
| [`contracts/mainnet/`](../contracts/mainnet/) | **The mainnet release candidate. Not deployed — published for review.** | `cd scripts && node compare-lineages.mjs` — proves `smartpacts-shares`/`smartpacts-ipo` are exactly the deployed system minus the differences listed below, and that the gas station's deliberate redesign matches its declared deltas exactly. |

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

### `smartpacts-shares` and `smartpacts-ipo`: identical minus this list

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

3. **Token identity constants (candidate only).** `NAME` ("Smart Pacts Token") and `SYMBOL`
   ("SPT") as constants in `smartpacts-shares` — self-documentation readable via
   `describe-module`. No wallet or explorer consumes such constants today; they are added to the
   candidate (not retrofitted to testnet) because constants are compiled code — the module hash
   changes — and the only free moment to add them is before a hash-anchored deployment exists.

4. **`account-votes` post-close note (candidate only, temporary).** A schema-doc note recording
   that the `weight <= balance` invariant holds only while a proposal is active; after close the
   row is inert history that nothing reads (documentation, not behavior). Surfaced by an external
   community red-team; it will also land on the testnet lineage when that is next re-frozen.

5. **A review banner** at the top of each candidate file, so the file itself says what it is even
   when read in isolation.

Nothing else differs in these two modules — not a function and not a check; the only constants
that differ are the identity pair above and the namespace-derived value in (2).

### `smartpacts-gas-station`: redesigned, by design

The candidate station is **not** the testnet06 station minus cosmetics — it is a redesign, and
pretending line-identity there would be dishonest. The sponsorship policy moved from compiled-in
constants to an admin-managed on-chain registry; the full design is documented for outside readers
in [GAS-STATION.md](GAS-STATION.md). The comparison script therefore switches mode for this
module: it mechanically asserts every named delta below on both files, plus the parts that must
stay identical.

What changed:

- **Registry replaces the compiled-in allowlist.** testnet06 carries
  `defconst SPONSORED-PREFIXES` (two hardcoded call prefixes); the candidate carries `registry` +
  `prefix-index` tables, the admin function `set-entry`, the `REGISTRY-ADMIN` gate and the public
  `ENTRY-SET` event. Granting or revoking sponsorship is an admin transaction, not a module
  upgrade.
- **Exec-only.** testnet06 also sponsored `cont` (defpact-continuation) transactions, bounded only
  by the aggregate cap because a cont carries no code to allowlist; the candidate refuses cont
  sponsorship entirely.
- **Per-entry budgets.** testnet06 metered one global 24 h cap for everything; the candidate gives
  every registered operation its own per-transaction gas ceiling, its own epoch budget and
  lifetime accounting (`charge-entry`) **and** keeps a global epoch backstop on top
  (`charge-global`). One operation's exhaustion or abuse can no longer starve the others.
- **Deploy-time namespace binding.** The candidate hardcodes no namespace anywhere: the admin
  keyset name derives from the deploy transaction, and sponsored prefixes are per-network data
  rows, not source.

What must stay identical — and is asserted code-exact:

- the sponsored gas-price ceiling constant;
- the global meter row shape (the deployed meter row survives an in-place upgrade);
- the **guard machinery** (`ALLOW_GAS`, `gas-payer-pred`, `station-guard-pred`,
  `create-gas-payer-guard`, the `GAS_STATION` principal). The funded station account's guard
  resolves the predicate functions **by name** — renaming them in any future upgrade would brick
  the account, so the comparison fails if they ever change.

Two further candidate-only hardenings, both asserted by the script: the **gas-ceiling positivity
guard** (the candidate additionally rejects a non-positive gas price/limit — defense in depth
from the community red-team; Chainweb already rejects such values upstream), and an
**admin-gated `init`** (the one-shot initializer runs under the governance capability — on a
live station both of its writes already fail closed, so this too is defense in depth). Both land
on the testnet lineage at its next redeploy.

## What the tests say

The full regression suite ([`tests/`](../tests/)) runs against the deployed testnet lineage.
For `smartpacts-shares` and `smartpacts-ipo` the candidate is code-identical minus the list
above, so those results transfer; what needs proving separately is exactly the delta, and
[`tests/mainnet-lineage.repl`](../tests/mainnet-lineage.repl) does that: the candidate deploys
fresh into an arbitrary namespace with nothing in the source pinning one, the derived constants
resolve correctly, and the dividend core (declared round → exact accrual → exact liability) runs
on it end-to-end.

The redesigned gas station gets no transfer credit: it has its **own full adversarial suite
against the candidate source**, [`tests/mainnet-gas-station.repl`](../tests/mainnet-gas-station.repl)
— registry admin gate and validation, prefix-boundary spoofs, exec-only and single-call
enforcement, per-entry ceilings and epoch caps, the isolation proof (an exhausted entry does not
starve the others), the global backstop, kill switch, meter protection, station guard, upgrade
survival, and worst-case sponsored-path gas at a full registry.
(`tests/smartpacts-gas-station.repl` continues to cover the deployed testnet06 station.)

The three `smartpacts-upgrade*` suites apply only to the testnet lineage — they test the
upgrade-and-migrate lifecycle, which is precisely what the mainnet candidate does not have.
