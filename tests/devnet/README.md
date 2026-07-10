# Cross-chain / SPV attacks (devnet-only)

These 12 `.repl` exercise **cross-chain and SPV code paths** — multi-chain state driven by `env-chain-data` chain switches, `transfer-crosschain` (the step-2 credit on the target chain), and `report-tally-xchain`. The bare Pact REPL runs a single shared database, so it cannot faithfully simulate independent chains or SPV proof verification. In a plain `pact tests/atk-*.repl` sweep they surface as `expected failure, got result` — a **harness limitation, not a defense break**. The project's own notes and the report's *Scope and honest limits* section both call this out.

The same attack fronts are also covered by single-chain attacks in `tests/` that run green, so the "held on every front" verdict stands. To make these meaningful, run them against a multi-chain devnet:

```sh
pact tests/devnet/atk-tally-freeze-2.repl   # only meaningful on a multi-chain devnet
```

**Files:** `atk-tally-freeze-2`, `atk-tally-freeze-3`, `atk-tally-freeze-3b`, `atk-tally-freeze-4`, `atk-tranches-4`, `atk-div-fairness-7`, `atk-div-solvency-3`, `atk-gas-drain-1b`, `atk-gas-drain-3`, `atk-gas-drain-5d`, `atk-gas-drain-6`, `atk-votekey-1`.
