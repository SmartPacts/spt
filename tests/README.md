# Test suites

The full regression suite for the deployed contracts — the same suites the project runs before
any change ships. Everything runs **offline** against the sources in [`contracts/testnet06/`](../contracts/testnet06/)
(the deployed modules, verbatim): no network, no keys, no accounts needed.

## Run them

Requirements: the Pact 5 CLI (5.4+ — [kda-community/pact-5](https://github.com/kda-community/pact-5),
prebuilt releases available).

```bash
cd tests
./run-tests.sh          # all 15 suites
pact smartpacts-governance.repl   # or any single suite
```

Every suite prints `… PASSED` on success; `run-tests.sh` exits non-zero on any failure.

## What each suite covers

| Suite | Covers |
|---|---|
| `smartpacts-shares.repl` | Token surface: transfers, accounts, guards, precision, dividend accounting through balance changes |
| `smartpacts-shares-init.repl` | Initialization: chain-0-only mint, enforced cap-table sum, double-init rejection, tranche locks created atomically |
| `smartpacts-shares-ext.repl` | Dividend edge cases: checkpoint-at-transfer exactness, float exclusion, claim behavior, tranche release gating |
| `smartpacts-ipo.repl` / `smartpacts-ipo-ext.repl` | The sale: pricing, pause/resume, reserve accounting, proceeds withdrawal, purchase edge cases |
| `smartpacts-governance.repl` | Live voting: weight = current balance, re-vote, release-on-transfer, tally freeze at close, chain-local replicas, hub aggregation |
| `smartpacts-tranches.repl` | Time-locks: nothing before cliff, linear release, exact final top-up, permissionless trigger, no acceleration/redirect path |
| `smartpacts-votekey.repl` | Dedicated voting key: main-guard-only registration, vote-only power, no lockout, revocation on rotation |
| `smartpacts-gas-station.repl` | Sponsorship policy (adversarial): allowlist boundaries, single-call rule, gas ceilings, per-epoch cap, fail-closed behavior |
| `smartpacts-attacks.repl` | Red team, token + governance: guard bypasses, reserve-move attempts, dust-grief vote suppression, key collisions, excluded-reserve votes |
| `smartpacts-attacks-voting.repl` | Red team, voting: double-vote via transfer/re-vote sequences, tally injection attempts, report-path boundaries, quorum edge cases |
| `smartpacts-dividend-fairness.repl` | Dividend fairness under cross-chain movement (the test-event finding, DF-1..DF-11): no double-pay / no under-pay for moved shares, declared-round ordering, effective-time gating, exact liability == Σ owed, the solvency guard, precision-floored claims with carried remainders, funding at zero float |
| `smartpacts-upgrade.repl` | The in-place upgrade path: pre-upgrade state survives, the un-migrated window fails closed, `migrate-adr015` heals and is idempotent, dead-chain funding refused |
| `smartpacts-upgrade-float.repl` | Upgrade with real balances present: zeroed counters proven exact, first post-upgrade round accrues exactly rate × balance, pre-funding at zero liability allowed |
| `smartpacts-upgrade-rps-guard.repl` | The migration's safety precondition: a chain that had funded a round under the old model is refused |
| `mainnet-lineage.repl` | The mainnet release candidate's delta: fresh deploy into an arbitrary namespace, namespace-derived constants resolve, dividend core exact (see [TESTNET-VS-MAINNET.md](../docs/TESTNET-VS-MAINNET.md)) |

The `attacks` suites are the threat model in executable form, and the `dividend-fairness` suite is the test-event finding in executable form: each documented attack is run
and shown to fail.

## Notes

- `setup.repl` loads the coin contract and interface fixtures (in [`fixtures/`](fixtures/), from
  [kda-community/chainweb-node](https://github.com/kda-community/chainweb-node)), then the three
  modules from `contracts/testnet06/` — so what you test is exactly what is deployed. The mainnet release candidate has its own smoke suite (`mainnet-lineage.repl`) covering exactly its delta — see [TESTNET-VS-MAINNET.md](../docs/TESTNET-VS-MAINNET.md).
- Cross-chain SPV transport (the second step of `transfer-crosschain` and
  `report-tally-xchain`) cannot be exercised in the REPL — SPV proofs need a real
  multi-chain network. Those paths are validated against a devnet before deployment; the REPL
  suites cover everything up to and around the yield/resume boundary.
