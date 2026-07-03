# SPT — Architecture

This document describes the system as deployed. Each section states the design and *why* it is
built that way. The sources in [`contracts/`](../contracts/) are the deployed modules, verbatim.

## 1. Token

- **Standards:** `fungible-v2` + `fungible-xchain-v1` — SPT behaves like any standard Kadena
  fungible, including cross-chain transfers.
- **Supply:** 100,000 SPT, precision 12, minted exactly once at initialization on chain 0 into
  contract-controlled reserves. There is no mint function on the module's surface — the supply
  cannot be increased.
- **Accounts:** every internal account (treasury, funders reserve, sale reserve, revenue,
  distribution pool) is a **capability-guarded principal** — controlled by module capabilities,
  not by any private key. No individual can move reserve funds outside the contract's rules.

**Why:** fixed supply and key-less reserves make the economics auditable from the chain alone;
standard interfaces make SPT compatible with existing wallets and tooling.

## 2. Distributions (revenue → holders)

- Revenue (KDA) accumulates in a per-chain, contract-controlled **revenue account**; the operator
  routes it either to the **distribution pool** or to operations — both movements are on-chain and
  public.
- Distribution accounting uses a **pool-accumulator pattern** (`reward-per-share` accumulator with
  per-account checkpoints, updated on every balance change): funding a round costs O(1), and each
  holder's entitlement accrues proportionally to holdings, with rounding always in the pool's
  favor.
- The **float is the base**: the treasury and unsold reserves are excluded from *both* accrual and
  the denominator. Reserves never dilute holders' distributions.
- **Claims are permissionless and never expire** — entitlements accumulate until claimed, and
  claiming is gas-free for holders (see §5).

**Why:** O(1) funding scales to any number of holders; excluding reserves means 100% of a
distribution round reaches actual holders; checkpoint-per-transfer makes the accounting exact even
as balances move.

## 3. Governance (advisory voting)

- **Live voting, chain-local:** a vote's weight is the voter's *current* SPT balance on the chain
  where the vote is cast. Re-voting updates the recorded vote in place. When tokens move — any
  debit, including the first step of a cross-chain transfer — the moved tokens' voting weight is
  automatically released from that chain's tally, and the receiver's tokens arrive unvoted.
- **Votes never cross chains.** Proposals are replicated by the operator to all 20 chains with an
  identical creation time and duration, so every replica shares one closing timestamp. Each
  chain's tally freezes at that moment.
- **Result aggregation is on-chain and permissionless:** after close, anyone can report each
  chain's frozen tally to the hub (chain 0); the final result only finalizes when **all 20 chains**
  are reported. The outcome is computed by the contract, not by the operator.
- **Safeguards:** contract-controlled reserves (treasury, unsold sale reserve, unvested
  allocations) can never vote; quorum is 4,000 SPT (4% of supply); proposal duration is bounded
  (72 hours – 14 days).

**Why:** tying weight to *current, chain-local* balances makes double-voting structurally
impossible — the same token cannot back two live votes anywhere, because moving it releases its
vote at the source before it exists at the destination. Permissionless, complete-gated aggregation
means nobody (including the operator) can cherry-pick partial results.

## 4. Founder vesting

- The founder allocation sits in a contract-controlled reserve that cannot vote and does not
  accrue distributions.
- Allocations vest via on-chain cliff releases: the operator creates an allocation with a fixed
  release date; after that date, release is **permissionless** — anyone can trigger it, nobody can
  accelerate or revoke it. Only released tokens enter the float.

**Why:** vesting enforced by the contract, visible to everyone, rather than by policy documents.

## 5. Gas station (gas-free participation)

- A dedicated module sponsors network gas for exactly two actions: **casting a vote** and
  **claiming distributions**. Buying in the sale is deliberately self-paid.
- Drain defenses are on-chain: the station only sponsors a transaction whose envelope contains
  exactly one allow-listed call, within strict gas ceilings (limit ≤ 1,500, price ≤ 1e-6), under a
  per-epoch spending cap. If the daily cap is exhausted, the same actions still work self-paid.

**Why:** holders should not need to hold KDA to exercise their rights — but a subsidy without
hard on-chain limits would be a faucet for attackers. The envelope allow-list plus epoch cap bounds
the worst case to a known, small daily amount.

## 6. Upgrade & freeze policy

- Modules are governed by a multi-signature-capable admin keyset. Every module carries a
  **one-way freeze switch**: a redeploy that sets `FROZEN-MODULE` to `true` permanently disables
  all future upgrades.
- The deployed testnet surface is **frozen for the duration of the community event** — what the
  event tests is exactly what was reviewed.
- The mainnet path: community advisory vote → external legal review → source freeze → fresh
  independent audit of the frozen source → deployment.

**Why:** upgradability is needed until the design is proven; the one-way freeze exists so that,
once proven, the contracts can be made immutable and the trust assumption removed entirely.

## 7. Chain topology

- SPT lives on **all 20 Kadena chains**; chain 0 is the governance hub (proposal aggregation) and
  the sale chain. Cross-chain transfers use the standard `fungible-xchain-v1` defpact with SPV
  proofs.

**Why:** following the platform's horizontal-scaling model keeps SPT usable wherever its holders
are, while hub aggregation keeps final governance results in one verifiable place.
