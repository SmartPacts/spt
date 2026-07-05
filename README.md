# Smart Pacts · SPT

**Smart Pacts** is an on-chain company experiment on the Kadena community network (KDA-CE): a
fixed supply of 100,000 **SPT** test-shares whose ownership, governance voting, and revenue
distributions are enforced entirely by the three Pact smart contracts in this repository —
not by policy, and not by anyone's goodwill.

- **Advisory governance voting** — token-weighted, gas-free for holders, tallied on-chain across
  all 20 chains, aggregated by the contract itself.
- **KDA distributions** — revenue flows to an on-chain account and is distributed pro-rata;
  claims are permissionless, gas-free, and never expire.
- **Key-less reserves on published time-locks** — the founder, treasury, and liquidity
  allocations sit in accounts no private key controls, releasing only on a calendar frozen in
  the source.

> **Status: public testnet.** Everything here runs on Kadena **testnet06**; all tokens are test
> tokens with **no monetary value**. Nothing here is an offer to sell any instrument. A mainnet
> deployment happens only after the community's advisory vote, external legal review, and an
> external audit of the frozen source.
>
> 🗳️ **Live now:** the community event — buy test-shares, vote on **MAINNET-GO** (closes
> **2026-07-18 05:56 UTC**), claim test distributions. Portal: **https://smartpacts.io/event/** ·
> CLI guide: [docs/EVENT-GUIDE.md](docs/EVENT-GUIDE.md)

## Verify, don't trust

The contracts in [`contracts/testnet06/`](contracts/testnet06/) are the deployed modules **verbatim** — the network
stores the module source, and one command compares this repository against all 20 chains:

```bash
cd scripts && npm install && node verify.mjs
```

It byte-compares each file against the on-chain stored source, checks the module hashes are
identical everywhere, and prints the deployment request keys (each one explorer-searchable, its
payload containing the full signed source). Manual queries and everything else worth checking —
supply, reserves, time-locks, the live vote — are in [docs/VERIFICATION.md](docs/VERIFICATION.md).

## Read your way in

| Start here | If you want |
|---|---|
| [`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md) | The whole system in plain language — every module, account, and mechanism, with the business reasoning |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | The terse engineering summary of the same design |
| [`docs/SECURITY-MODEL.md`](docs/SECURITY-MODEL.md) | Invariants, threats designed against, operator powers and limits, and the honest review status |
| [`contracts/testnet06/`](contracts/testnet06/) | The three deployed Pact modules (live on testnet06, byte-verifiable) |
| [`contracts/mainnet/`](contracts/mainnet/) | The mainnet **release candidate** — not deployed, published for review; see [Testnet vs. mainnet](docs/TESTNET-VS-MAINNET.md) |
| [`tests/`](tests/) | The full regression suite — 11 REPL suites including two red-team suites, runnable offline ([how](tests/README.md)) |
| [`docs/VERIFICATION.md`](docs/VERIFICATION.md) | Every on-chain fact, and how to check it yourself |
| [`docs/DEPLOYMENTS.md`](docs/DEPLOYMENTS.md) | Dated record of every deployment and upgrade (including the deprecated prior namespace) |
| [`docs/EVENT-GUIDE.md`](docs/EVENT-GUIDE.md) | The community event, step by step (CLI) |
| [`SECURITY.md`](SECURITY.md) | How to report a vulnerability |

## The three modules

- **`smartpacts-shares`** — the SPT token (standard `fungible-v2` + `fungible-xchain-v1`
  interfaces), dividend accounting, the pre-committed founder/treasury/liquidity time-locks, the
  dedicated-voting-key registry, the per-chain revenue account, and the full governance mechanism
  (proposals, votes, tallies, on-chain result aggregation).
- **`smartpacts-ipo`** — the fixed-price initial token sale (chain 0). On testnet: a simulated
  sale at a test price.
- **`smartpacts-gas-station`** — pays network gas for holders' votes and distribution claims,
  under hard on-chain limits so the subsidy cannot be drained.

Two design decisions worth noticing up front: the insider reserves sit on **pre-committed
on-chain time-locks** — releasable by anyone, only on a schedule frozen in the code, impossible
to accelerate or redirect — and any holder can register a **dedicated voting key**, so the hot
key that votes has no power over the shares themselves. The reasoning behind every mechanism is
in [HOW-IT-WORKS](docs/HOW-IT-WORKS.md); the threat model and review status are stated plainly in
[SECURITY-MODEL](docs/SECURITY-MODEL.md).

## Deployment (testnet06, all 20 chains)

| Fact | Value |
|---|---|
| Namespace | `n_d97ffd2ca290429b5dc85ce551a8d07d038e9641` |
| Chains | 0–19 (governance hub: chain 0) |
| Supply | 100,000 SPT, fixed at initialization — no further minting is possible |
| API base | `https://api.testnet.chainweb-community.org` |
| Explorer | `https://explorer.chainweb-community.org/testnet` |
| Website | https://smartpacts.io |

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
