# Deployment record

Every deployment and upgrade of the SPT contracts on testnet06, dated, with what changed and how
to verify it. Testnet is where the design is proven; this record exists so that everything you
can find on-chain has a stated explanation.

## Current deployment — namespace `n_d97ffd2ca290429b5dc85ce551a8d07d038e9641`

| Date (UTC) | Event | Details |
|---|---|---|
| 2026-07-04 | **Deployment** — all 3 modules, 20 chains | Supply minted once on chain 0 (sale 20,000 / founder 10,000 / liquidity 15,000 / treasury 55,000 — sum enforced on-chain); the three reserve time-locks created atomically with the mint; sale opened; gas stations funded. The **MAINNET-GO** advisory proposal announced on all 20 chains, closing **2026-07-18 05:56:23 UTC**. |
| 2026-07-04 | **Source-cleanup upgrade** — all 3 modules, 20 chains | A comments-only rewrite of the deployed source (developer annotations replaced with the documentation now in this repository) plus upgrade-safe table-creation guards. **The module hashes did not change** — a Pact module hash covers the compiled module, so the unchanged hash is on-chain proof the upgrade altered zero behavior. All state (balances, time-locks, the live vote) verified intact across the upgrade. Chain-0 request keys: shares `cub3tKOMJnaWdIfXLH5tKsKYbS39bcA2YkY9LkH0SSg` · ipo `10TKBZ7uHE8ejH2mcUmo2gd6V0sBiGmr0mtOszcoAyU` · gas-station `jZQecGLuwiDx7HK19Tzm5r7eHn_rw0trUgyJriwl05Y`. |

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
