# Verify it yourself

Nothing in this repository needs to be taken on trust. Everything below can be checked against the
live network with free, public tooling.

**The one-command version:** `cd scripts && npm install && node verify.mjs` byte-compares every
contract in this repository against the source stored on all 20 chains, checks hash uniformity,
and prints the deployment request keys. The rest of this page is the manual version, plus the
supply/time-lock/vote checks the script doesn't cover. Deployment and upgrade history (with
request keys) is in [DEPLOYMENTS.md](DEPLOYMENTS.md).

The **mainnet release candidate** ([`contracts/mainnet/`](../contracts/mainnet/)) is not deployed,
so there is no chain to verify it against — `node compare-lineages.mjs` proves its exact
relationship to the deployed lineage instead ([TESTNET-VS-MAINNET.md](TESTNET-VS-MAINNET.md)).

## Deployment facts

| Fact | Value |
|---|---|
| Network | Kadena community testnet (`testnet06`), chains 0–19 |
| Namespace | `n_d97ffd2ca290429b5dc85ce551a8d07d038e9641` |
| Modules | `smartpacts-shares` · `smartpacts-ipo` · `smartpacts-gas-station` |
| On-chain hash — `smartpacts-shares` | `B_zwM2m9mGLteCrakCBPPGf7Gs_aI67GbGSTEpPaSCw` |
| On-chain hash — `smartpacts-ipo` | `vT4Z0Zwui8x5t_FbeRePsdcWLSG-gWFGsjoJWL3PPPA` |
| On-chain hash — `smartpacts-gas-station` | `2RuamqPZHYxvvYzymfFZ90LcLfmYSqiTn47bPBpe6s4` |
| API base | `https://api.testnet.chainweb-community.org` |
| Pact endpoint pattern | `{base}/chainweb/0.0/testnet06/chain/{0-19}/pact/api/v1/local` |
| Explorer | `https://explorer.chainweb-community.org/testnet` |
| Faucet (test KDA) | `https://tools.chainweb-community.org/faucet/new` |

The sources in [`contracts/testnet06/`](../contracts/testnet06/) are the deployed modules verbatim — the network
stores the module source, and you can read it back and compare byte for byte.

## 1. Verify the deployed code

Run a local (read-only, free) query on any chain — with the
[pact CLI](https://github.com/kda-community/pact-5), any Pact-capable wallet, or the explorer's
module view:

```pact
(describe-module "n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.smartpacts-shares")
```

Three fields matter:

- **`code`** — the module source **as stored on-chain**. It equals the `(module …)` form in the
  corresponding file under [`contracts/testnet06/`](../contracts/testnet06/) **byte for byte** (the file additionally
  carries the deployment wrapper — the header comment, `(namespace …)`, the keyset definition,
  and the table-creation footer — which are part of the deploy transaction but not of the stored
  module body).
- **`hash`** — the module hash the network computed. It matches the table above on **every**
  chain, for each of the three modules. Note this hash covers the *compiled* module (definitions
  and dependencies, not comments), so it pins the executable semantics.
- **`tx_hash`** — the request key of the transaction that last (re)deployed the module. Look it
  up in the explorer to see the full signed deployment, including the complete source payload.

Chain-0 deployment request keys (`tx_hash`):

| Module | Request key (chain 0) |
|---|---|
| `smartpacts-shares` | `cub3tKOMJnaWdIfXLH5tKsKYbS39bcA2YkY9LkH0SSg` |
| `smartpacts-ipo` | `10TKBZ7uHE8ejH2mcUmo2gd6V0sBiGmr0mtOszcoAyU` |
| `smartpacts-gas-station` | `jZQecGLuwiDx7HK19Tzm5r7eHn_rw0trUgyJriwl05Y` |

The same three transactions were submitted per chain, and every chain reports the same module
hash and the same stored source.

## 2. Verify the supply, reserves, and time-locks

```pact
(n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.smartpacts-shares.get-circulating)   ; float in holders' hands
(n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.smartpacts-shares.get-balance
  (n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.smartpacts-ipo.reserve-account))   ; unsold sale reserve
```

Supply is fixed: the module exposes no mint function — inspect
[`contracts/testnet06/smartpacts-shares.pact`](../contracts/testnet06/smartpacts-shares.pact) and confirm the only
credits to reserves happen inside the one-time `init-supply`.

**The reserve time-locks** (founder / treasury / liquidity) are on-chain rows — read them on
chain 0:

```pact
(n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.smartpacts-shares.get-tranche "founder")
(n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.smartpacts-shares.get-tranche "treasury")
(n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.smartpacts-shares.get-tranche "liquidity")
(n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.smartpacts-shares.tranche-releasable "founder")
```

Each row shows the fixed beneficiary, the total, how much has been released, and the cliff/vesting
end dates — compare them with the constants in the source. `tranche-releasable` shows what a
(permissionless) release would pay out right now.

## 3. Verify the live vote (MAINNET-GO)

```pact
(n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.smartpacts-shares.proposal-details "MAINNET-GO")
(n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.smartpacts-shares.get-results "MAINNET-GO")        ; this chain's tally
(n_d97ffd2ca290429b5dc85ce551a8d07d038e9641.smartpacts-shares.get-final-results "MAINNET-GO")  ; chain 0, after close + 20-chain aggregation
```

`proposal-details` on any chain shows the proposal is live with the same closing time everywhere:
**2026-07-18T05:56:23Z**. After close, the final result is aggregated on-chain (permissionless,
finalizes only when all 20 chains are reported) — the outcome is computed by the contract.

## 4. Try it

The fastest way to verify the system is to use it: **https://smartpacts.io/event/** walks you
through the whole journey in the browser — test account, faucet, simulated purchase, gas-free
advisory vote, gas-free distribution claim. The CLI version is
[EVENT-GUIDE.md](EVENT-GUIDE.md).

> Test tokens only — nothing on testnet06 has monetary value.
