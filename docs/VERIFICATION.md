# Verify it yourself

Nothing in this repository needs to be taken on trust. Everything below can be checked against the
live network with free, public tooling.

## Deployment facts

| Fact | Value |
|---|---|
| Network | Kadena community testnet (`testnet06`), chains 0–19 |
| Namespace | `n_58b259badf99bb9d5f4118446a01d23a3a6b51cf` |
| Modules | `smartpacts-shares` · `smartpacts-ipo` · `smartpacts-gas-station` |
| On-chain module hash (chain 0) — `smartpacts-shares` | `gHn1X5E4daGasc9FMuwa8HdugsaCohqh489JIoihNW4` |
| API base | `https://api.testnet.chainweb-community.org` |
| Pact endpoint pattern | `{base}/chainweb/0.0/testnet06/chain/{0-19}/pact/api/v1/local` |
| Explorer | `https://explorer.chainweb-community.org/testnet` |
| Faucet (test KDA) | `https://tools.chainweb-community.org/faucet/new` |

The sources in [`contracts/`](../contracts/) are the deployed modules verbatim.

## 1. Verify the deployed code

Run a local (read-only, free) query on any chain — with the
[pact CLI](https://github.com/kda-community/pact-5), any Pact-capable wallet, or the explorer's
module view:

```pact
(describe-module "n_58b259badf99bb9d5f4118446a01d23a3a6b51cf.smartpacts-shares")
```

The returned `hash` for chain 0 is listed above; the same source is deployed on every chain.

## 2. Verify the supply and reserves

```pact
(n_58b259badf99bb9d5f4118446a01d23a3a6b51cf.smartpacts-shares.get-circulating)   ; float in holders' hands
(n_58b259badf99bb9d5f4118446a01d23a3a6b51cf.smartpacts-shares.get-balance
  (n_58b259badf99bb9d5f4118446a01d23a3a6b51cf.smartpacts-ipo.reserve-account))   ; unsold sale reserve
```

Supply is fixed: the module exposes no mint function — inspect
[`contracts/smartpacts-shares.pact`](../contracts/smartpacts-shares.pact) and confirm the only
credits to reserves happen inside the one-time `init-supply`.

## 3. Verify the live vote (MAINNET-GO)

```pact
(n_58b259badf99bb9d5f4118446a01d23a3a6b51cf.smartpacts-shares.proposal-details "MAINNET-GO")
(n_58b259badf99bb9d5f4118446a01d23a3a6b51cf.smartpacts-shares.get-results "MAINNET-GO")        ; this chain's tally
(n_58b259badf99bb9d5f4118446a01d23a3a6b51cf.smartpacts-shares.get-final-results "MAINNET-GO")  ; chain 0, after close + 20-chain aggregation
```

`proposal-details` on any chain shows the proposal is live with the same closing time everywhere:
**2026-07-17T16:38:24Z**. After close, the final result is aggregated on-chain (permissionless,
finalizes only when all 20 chains are reported) — the outcome is computed by the contract.

## 4. Try it

The fastest way to verify the system is to use it: **https://smartpacts.io/event/** walks you
through the whole journey in the browser — test account, faucet, simulated purchase, gas-free
advisory vote, gas-free distribution claim. The CLI version is
[EVENT-GUIDE.md](EVENT-GUIDE.md).

> Test tokens only — nothing on testnet06 has monetary value.
