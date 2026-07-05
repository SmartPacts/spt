# Deployment record

Every deployment and upgrade of the SPT contracts on testnet06, dated, with what changed and how
to verify it. Testnet is where the design is proven; this record exists so that everything you
can find on-chain has a stated explanation.

## Current deployment — namespace `n_d97ffd2ca290429b5dc85ce551a8d07d038e9641`

| Date (UTC) | Event | Details |
|---|---|---|
| 2026-07-04 | **Deployment** — all 3 modules, 20 chains | Supply minted once on chain 0 (sale 20,000 / founder 10,000 / liquidity 15,000 / treasury 55,000 — sum enforced on-chain); the three reserve time-locks created atomically with the mint; sale opened; gas stations funded. The **MAINNET-GO** advisory proposal announced on all 20 chains, closing **2026-07-18 05:56:23 UTC**. |
| 2026-07-04 | **Source-cleanup upgrade** — all 3 modules, 20 chains | A comments-only rewrite of the deployed source (developer annotations replaced with the documentation now in this repository) plus upgrade-safe table-creation guards. **The module hashes did not change** — a Pact module hash covers the compiled module, so the unchanged hash is on-chain proof the upgrade altered zero behavior. All state (balances, time-locks, the live vote) verified intact across the upgrade. Chain-0 request keys: shares `cub3tKOMJnaWdIfXLH5tKsKYbS39bcA2YkY9LkH0SSg` · ipo `10TKBZ7uHE8ejH2mcUmo2gd6V0sBiGmr0mtOszcoAyU` · gas-station `jZQecGLuwiDx7HK19Tzm5r7eHn_rw0trUgyJriwl05Y`. |
| 2026-07-05 | **Dividend-accrual upgrade** — `smartpacts-shares` only, 20 chains | A dividend-fairness defect was surfaced during the public test event: the per-chain reward accumulator meant test-shares moving between chains while a round was being funded could be double- or under-paid. Fixed by making accrual **global via declared rounds**: a round (rate per test-share + effective timestamp) is declared on-chain on every chain identically, in advance, and is immutable once declared; holdings then accrue exactly `rate × shares held at the effective moment`, under any cross-chain movement. Funding became pure cash logistics with an **exact solvency check** (the pool must cover the chain's true liability, including the crystallized dividends of shares that have since left the chain), and claims pay the exact 12-decimal floor with any sub-precision remainder carried forward. The fix went through five independent review cycles and a full upgrade rehearsal on a private network before shipping. Applied **in place** with a one-shot migration (`migrate-adr015`, which enforces its own safety precondition on-chain); every balance, time-lock, and the live MAINNET-GO vote verified intact. **This upgrade changes behavior, and the changed module hash is the proof** (unlike a source-cleanup pass): `smartpacts-shares` is now `B_zwM2m9mGLteCrakCBPPGf7Gs_aI67GbGSTEpPaSCw`, identical on all 20 chains; `smartpacts-ipo` and `smartpacts-gas-station` were not redeployed and keep their hashes. Chain-0 request keys: upgrade `VVflyCQB950N63-R5CUrBW53Oo2XxLwgA8kIWwWUuCs` · migration `qS-sIMDhVBJwlo9tADRRGZeOTTdy0uipBaQlwCw1BCg`. Planned test dividend rounds: round 1 planned for July 11, 2026; a second round after the event ends (after July 22, 2026) — dates are operator actions and may shift until a round is declared on-chain. |
| 2026-07-05 | **Sale re-link** — `smartpacts-ipo` only, 20 chains | A Pact module pins the exact version (hash) of every module it calls, at its own deploy time. The sale contract, deployed 2026-07-04, was still pinned to the pre-upgrade `smartpacts-shares` — and the dividend-accrual upgrade deliberately did **not** bless the old hash (blessing it would have let the superseded dividend logic keep executing through sale purchases). The chain therefore refused the sale's calls (`hash not blessed`) — **fail-closed**: no purchase went through the stale logic, and state was verified untouched (circulating and liability exactly as at the upgrade) — but buying was unavailable from the upgrade until this re-link. Redeploying the sale with **byte-identical source** re-pins it to the current `smartpacts-shares`; purchases work again and flow through the corrected accounting. The source text did not change (the byte-compare in `scripts/verify.mjs` still passes); the module hash changed to `vT4Z0Zwui8x5t_FbeRePsdcWLSG-gWFGsjoJWL3PPPA` because a Pact module hash covers the compiled module **including its resolved dependencies**. Lesson recorded in our runbook: a dependency upgrade ships together with a re-link of its dependents. Chain-0 request key: `4WTf2nSb5N_fu1FS2kxlxh2aC-agr0xD1sVQ7JWyfGA`. |
| 2026-07-05 | **Presentation pass** — `smartpacts-shares` only, 20 chains | The dividend-accrual upgrade shipped with the fix cycle's engineering annotations in its source. Following the 2026-07-04 precedent, the annotations were rewritten to the documentation style of this repository and the module redeployed. **The module hash did not change** (`B_zwM2m9…` before and after, verified on all 20 chains) — on-chain proof the rewrite altered zero behavior; the stored source now matches [`contracts/smartpacts-shares.pact`](../contracts/smartpacts-shares.pact) byte for byte. One note for source readers: the string `pre-ADR-015` survives inside a migration error message — string literals are part of the compiled module (hash-covered), so it cannot be rewritten; "ADR-015" is the internal design-revision label of the dividend-accrual change. Chain-0 request key: `lb-zax9lQ6XkT56KzPY0t1V-eTy4ItCll129aFocS2M`. |

The sources in [`contracts/`](../contracts/) are this deployment's modules verbatim —
[VERIFICATION.md](VERIFICATION.md) shows how to check that byte for byte.

## Prior deployment — namespace `n_58b259badf99bb9d5f4118446a01d23a3a6b51cf` (deprecated)

An earlier iteration of the same system ran under this namespace (deployed 2026-07-01) with a
different token allocation and without the reserve time-locks and the dedicated voting key. It
was superseded on 2026-07-04 by the current deployment, which launched the revised design fresh —
new namespace, new supply, new vote — rather than migrating state on a test network.

**The old namespace still answers on-chain queries but is deprecated: do not buy, vote, or build
against it.** Its wind-down (pausing the sale, sweeping its gas stations) is in progress. Only
the `n_d97ffd2c…` deployment is current, and it is the only one this repository documents.

## What is *not* recorded here

Test networks exist for iteration: internal rehearsals, devnet drills, and pre-release
experiments happen continuously and are not deployments of record. This page records everything
a user or auditor can encounter as a live, named deployment of SPT.
