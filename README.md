# Smart Pacts · SPT

**Smart Pacts** is an on-chain company on the Kadena community network (KDA-CE). Its token, **SPT**,
gives holders two things, both enforced entirely by the smart contracts in this repository:

- **Advisory governance voting** — token-weighted, gas-free for holders, tallied on-chain across
  all 20 chains.
- **KDA distributions** — revenue earned by future on-chain products flows to an on-chain revenue
  account and is distributed to holders; claims are permissionless and gas-free.

Everything is verifiable by anyone: the contracts here are the exact modules deployed on-chain, the
governance results are computed on-chain, and every operational transaction is explorer-searchable.

> **Status: public testnet.** Everything described here runs on Kadena **testnet06**. All tokens
> involved are test tokens with **no monetary value**. Nothing here is an offer to sell any
> instrument. A mainnet deployment happens only after the community's advisory vote, external legal
> review, and a fresh independent audit of the frozen source.

## 🗳️ Live now: the public testnet event (July 2026)

An open community event is running: create a test account, buy test-shares in a simulated sale,
cast an advisory vote on the **MAINNET-GO** proposal — *"Approve the Smart Pacts contracts to be
deployed to mainnet"* — and claim test distributions. The vote is live on all 20 chains and
**closes 2026-07-18 05:56 UTC**; the final result is aggregated on-chain.

- **Portal (everything in the browser):** https://smartpacts.io/event/
- **Step-by-step guide (CLI path):** [docs/EVENT-GUIDE.md](docs/EVENT-GUIDE.md)
- **Website:** https://smartpacts.io

## What's in this repository

| Path | Contents |
|---|---|
| [`contracts/`](contracts/) | The three deployed Pact modules, **verbatim** — the same source that produced the on-chain module hashes (see verification) |
| [`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md) | **Start here** — the whole system in plain language: every module, account, and mechanism, with the reasoning |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | The terse engineering summary of the same design |
| [`docs/VERIFICATION.md`](docs/VERIFICATION.md) | How to verify the deployment, the vote, and the results yourself |
| [`docs/EVENT-GUIDE.md`](docs/EVENT-GUIDE.md) | The community event guide (CLI walkthrough) |
| [`SECURITY.md`](SECURITY.md) | How to report a vulnerability |

## The three modules

- **`smartpacts-shares`** — the SPT token (standard `fungible-v2` + `fungible-xchain-v1`
  interfaces), distribution accounting, the pre-committed founder/treasury/liquidity time-locks,
  the dedicated-voting-key registry, the per-chain revenue account, and the full governance
  mechanism (proposals, votes, tallies, on-chain result aggregation).
- **`smartpacts-ipo`** — the fixed-price initial token sale (chain 0). On testnet this is a
  simulated sale at a test price.
- **`smartpacts-gas-station`** — pays network gas for holders' votes and distribution claims, with
  strict on-chain limits so the subsidy cannot be drained.

Two design decisions worth noticing up front: the founder, treasury, and liquidity reserves sit on
**pre-committed on-chain time-locks** — releasable by anyone, only on a schedule frozen in the
code, impossible to accelerate or redirect; and any holder can register a **dedicated voting key**,
so the hot key that votes has no power over the shares themselves. Both are explained in
[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md); an independent security review was performed before
deployment and its findings were addressed prior to going live.

## Deployment (testnet06, all 20 chains)

| Fact | Value |
|---|---|
| Namespace | `n_d97ffd2ca290429b5dc85ce551a8d07d038e9641` |
| Chains | 0–19 (governance hub: chain 0) |
| Supply | 100,000 SPT, fixed at initialization — no further minting is possible |
| API base | `https://api.testnet.chainweb-community.org` |
| Explorer | `https://explorer.chainweb-community.org/testnet` |

Full verification instructions, including on-chain module hashes and live queries you can run
yourself, are in [docs/VERIFICATION.md](docs/VERIFICATION.md).

## Disclaimer

> **[DRAFT — PENDING COUNSEL]**
> This is experimental software deployed on a public **test network**. Test tokens have no monetary
> value and confer no rights of any kind. Participation in the testnet event is free and creates no
> obligation on any party. The MAINNET-GO vote is **advisory only** — it is not binding, and it is
> not a commitment to deploy. Nothing in this repository is investment, legal, accounting, or tax
> advice, and nothing here is an offer or solicitation to buy or sell any instrument, in any
> jurisdiction.

## License

[MIT](LICENSE) © Smart Pacts
