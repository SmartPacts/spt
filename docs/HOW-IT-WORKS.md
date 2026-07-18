# How SPT works — the whole system, in plain language

This is the long-form tour of the Smart Pacts token system: every module, every account, every
mechanism, and — most importantly — *why* each one is built the way it is. No Pact fluency is
assumed. When you want to check any claim against the live network,
[VERIFICATION.md](VERIFICATION.md) has the exact queries; when you want the terse engineering
summary instead, read [ARCHITECTURE.md](ARCHITECTURE.md).

> **Status: public testnet.** Everything here runs on Kadena **testnet06** and every token involved
> is a test token with **no monetary value**. The governance vote is **advisory only**. Nothing in
> this document is investment, legal, accounting, or tax advice, or an offer of any instrument.

---

## 1. The one-paragraph version

**Smart Pacts** is an on-chain company experiment: a fixed supply of 100,000 **SPT** test-shares
whose ownership, governance voting, and revenue distributions are enforced entirely by three smart
contracts — not by a spreadsheet, a promise, or an administrator's goodwill. Holders buy shares in
a fixed-price sale, vote on proposals with their shares (for free — the system pays the network
fees), and claim their share of distributed revenue (also free). The company's own reserves are
locked by the contracts themselves: nobody, including the founder, can move them outside the
pre-published rules.

Three modules divide the work:

| Module | Job |
|---|---|
| `smartpacts-shares` | The share token itself, plus governance (proposals, votes, tallies, results), dividends, the revenue account, and the reserve time-locks |
| `smartpacts-ipo` | The fixed-price initial sale |
| `smartpacts-gas-station` | Pays the network fees for holders' votes and dividend claims |

They live on all 20 chains of the Kadena network. Chain 0 is the "hub": the sale happens there,
the supply was created there, and final vote results are assembled there.

---

## 2. The token

SPT implements Kadena's standard token interfaces (`fungible-v2` and `fungible-xchain-v1`), so it
behaves exactly like any other Kadena fungible: it can be held in ordinary accounts, transferred,
and moved between chains. Amounts have 12 decimal places, the same precision as KDA itself.

The full supply — 100,000 SPT — was created **exactly once**, in a single initialization
transaction on chain 0, and the module has **no mint function** on its surface. You can read the
contract and confirm that the only place tokens are ever created is inside that one-time
`init-supply` function, which is permanently disabled after it runs once. Nobody can print more.

**Why:** a share register is only meaningful if the share count is fixed and the ledger is the
single source of truth. Making "no further minting" a property of the code (rather than a policy)
removes the need to trust anyone on the most basic question: how many shares exist?

## 3. The cap table, and accounts that have no key

At initialization the 100,000 SPT were split four ways, on-chain, in one atomic transaction:

| Reserve | Amount | Purpose |
|---|---|---|
| Sale (IPO) reserve | 20,000 | Sold to the public in the fixed-price sale |
| Founder reserve | 10,000 | The founder's allocation — time-locked (§4) |
| Liquidity reserve | 15,000 | Future market/liquidity operations — time-locked (§4) |
| Treasury | 55,000 | The company's long-term reserve — time-locked (§4) |

The initialization enforces, in code, that these four numbers sum to exactly the total supply — a
transaction with a different split would have refused to run.

Every one of these reserves — and the KDA-holding revenue and dividend-pool accounts — is a
**capability-guarded principal account**. That deserves unpacking, because it is the foundation
of the whole design: a normal blockchain account is controlled by whoever holds a private key.
These accounts are different — their "key" is a rule inside the module, and the rule can only be
exercised by the specific contract functions written for it. There is no private key that moves
the treasury. The founder cannot transfer it; a thief who compromised every laptop in the company
could not transfer it; the *only* paths out are the ones in the published source.

The reserves are also **economically inert**: they cannot vote, they do not accrue dividends,
and they are excluded from the dividend denominator (§5). They sit outside the circulating economy
until the time-locks release them into it.

**Why:** "trust the operator" is the failure mode of most token projects. Key-less reserves turn
the cap table from a promise into a mechanism — the interesting question stops being "will they
move the treasury?" and becomes "what does the code permit?", which anyone can answer by reading it.

## 4. The time-locks: a release calendar frozen in code

The founder, treasury, and liquidity reserves are each held by a **pre-committed time-lock** with
a cliff-and-vesting schedule:

| Tranche | Cliff (nothing before) | Fully released by |
|---|---|---|
| Founder — 10,000 | 12 months | 4 years |
| Treasury — 55,000 | 12 months | 5 years |
| Liquidity — 15,000 | 3 months | 2 years |

The schedule's origin point is the timestamp of the initialization transaction itself, and the
cliff/vesting durations are **constants in the module source** — not parameters, not rows an
administrator can edit. After the cliff, tokens release linearly until the end date. Each lock
names a fixed beneficiary account, set once at initialization.

The properties worth dwelling on:

- **Releasing is permissionless.** Anyone — a holder, a stranger, a script — can call
  `release-tranche` and the accrued portion moves to the beneficiary. There is nothing to withhold
  and no one to ask.
- **Nothing can be accelerated.** There is no function that releases early, no override, no
  "admin unlock". The contract cannot be talked into it, because the capability to move the
  reserve exists only inside the release function, and the release function only pays out what the
  calendar has accrued.
- **Nothing can be redirected, revoked, or delayed** — the beneficiary and the schedule are fixed
  at initialization and there is no function that changes either.
- **Everything is disclosed.** At initialization the contract emitted an on-chain event per
  tranche carrying its full schedule, so the calendar is part of the permanent public record.

Released tokens enter circulation like any other credit: they start earning dividends only from
that moment (no retroactive accrual), and they arrive carrying no votes.

**Why:** insider allocations are where token holders usually get hurt — quiet unlocks, revised
schedules, "strategic" early releases. Pre-committing the calendar in the source and stripping
every override answers the question "when can the insiders sell?" with a proof instead of a
promise. Locking the *treasury* as well goes a step further than most projects: even the company's
own war chest enters circulation on a published curve.

## 5. Dividends: revenue in, pro-rata out

The intended economics: Smart Pacts products earn revenue in KDA; that revenue is distributed to
shareholders pro-rata; claims are free and never expire. On testnet, the "revenue" is test KDA
used to exercise exactly the same pipeline.

The mechanism, end to end:

1. **Revenue arrives on-chain.** Anyone can pay KDA into the contract's per-chain **revenue
   account** (`receive-revenue`). This account is capability-guarded like everything else — the
   operator can route it, but only through public, on-chain functions.
2. **The operator declares a round — in advance, on every chain, immutably.** A round is a
   **rate per share plus an effective timestamp** (`declare-round`), submitted identically to all
   20 chains and announced by an on-chain event. Once declared it cannot be moved or cancelled,
   and rounds must be declared in time order — the round list is append-only public record.
   Declaring moves no money; it fixes *who will be owed what*: at the effective moment, every
   circulating share accrues exactly the rate, wherever it sits.
3. **Accrual is global and movement-proof.** The dividends-per-share number every account
   checkpoints against is computed from the declared-round list plus consensus time — the same
   value on every chain, by construction. Move shares between chains before, during, or after a
   round: your lifetime entitlement is always `Σ rate × shares held at each round's effective
   moment`. (An earlier design kept this number per chain and synced it at funding time, which
   could double- or under-pay shares that moved mid-round — a defect surfaced during the public
   test event and closed by this design.) Whenever a balance changes, the contract first settles
   the account's accrued entitlement at the old balance, then updates the checkpoint — so
   entitlements stay exact as shares change hands.
4. **Funding is logistics, never fairness.** `fund-dividends` moves cash from the revenue account
   into the chain's **dividend pool** — that is all it does. The contract refuses the deposit
   unless the pool then covers the chain's **entire outstanding liability**, computed exactly
   on-chain — including dividends already earned by shares that have since left the chain. So
   "funded" is a hard on-chain guarantee that every claim is payable, and *when* the operator
   funds can never change *what* anyone is owed. (Routing revenue to operations instead is
   equally public: `withdraw-revenue` emits an event, so holders see every KDA that goes either
   way.)
5. **The float is the base.** Only circulating shares — shares in holders' hands — count.
   The treasury, the unsold sale reserve, and the locked tranches neither accrue dividends nor
   appear in the denominator, so 100% of every round reaches actual holders.
6. **Claims are permissionless, exact, and durable.** `claim-dividends` pays the accrued KDA out
   at the exact 12-decimal precision the KDA ledger supports; any finer remainder stays credited
   to the account and rides into the next round — nothing is ever rounded away. Anyone can
   trigger a claim for any account — but the payout **always** goes to an account bound to the
   holder's own keys, so triggering someone else's claim just does them a favor. Unclaimed
   dividends accumulate indefinitely; there is no expiry, no sweep-back.

One subtle protection: payouts go to a *principal* account derived from the holder's own key
material, not to a raw account name. This closes an attack where someone pre-creates a KDA account
with your name but their keys, which would otherwise make your claims bounce forever.

One practical note: shares that are mid-flight between chains at the exact moment a round becomes
effective are on no chain, and do not accrue that round. A cross-chain move takes minutes;
avoid moving right around an announced effective time.

**Why:** the per-share-accumulator design (familiar from DeFi staking systems) is what makes
dividends scale — a round costs the same whether there are ten holders or ten thousand. Declaring
rounds in advance with a public, immutable record makes the *fairness* of a distribution checkable
before any money moves; the exact solvency check makes the *payability* checkable after. Excluding
the reserves is a fairness statement with teeth: the company cannot pay dividends to itself. And
permissionless, non-expiring claims mean a holder who goes quiet for a year loses nothing.

## 6. Governance: live votes that move with the shares

Holders vote on proposals — currently the advisory **MAINNET-GO** question — and the design goal
is one property above all: **one share, one live vote, everywhere, always.**

How it works:

- **Your weight is your current balance.** When you vote, your vote is recorded at the full size
  of your holdings on that chain. Vote again and the record simply updates — changing your mind is
  always allowed while the proposal is open.
- **Shares that move take their votes with them.** The moment any of your shares leave your
  account — a transfer, a sale, even the first step of a cross-chain move — the contract releases
  exactly that many shares' worth of weight from your recorded vote, automatically, in the same
  transaction. The receiver's shares arrive *unvoted*; the receiver may then vote them.
  Consequence: it is structurally impossible for the same share to back two live votes. Not
  "against the rules" — impossible. There is no sequence of transfers, chain-hops, and re-votes
  that double-counts, because weight is released at the source before it can exist anywhere else.
- **Receiving shares never touches your vote.** Someone spamming you with dust cannot shrink or
  distort what you voted.
- **Voting is chain-local.** A proposal is replicated to every chain with an identical creation
  time and duration, so all 20 replicas share a single closing timestamp. You vote on the chain
  where your shares live; votes never cross chains. Each chain's tally freezes at the shared
  close time.
- **The final result is assembled on-chain, by anyone.** After close, each chain's frozen tally is
  reported to chain 0 — a permissionless action; the reporting transaction carries no
  user-supplied numbers, it reads the frozen tally straight from the source chain and moves it
  under a cryptographic proof. Duplicates are rejected. The combined result only counts as
  **complete** when *all 20 chains* have reported — a partial aggregate can never "pass".
- **Guardrails:** the reserves cannot vote (the contract refuses them); quorum is 4,000 SPT (4% of
  supply); proposal duration is bounded between 72 hours and 14 days; a cancelled proposal has no
  result; and once the close time passes, nothing — not even a transfer — changes a tally again.

**Why:** most token-voting failures are double-count failures (vote, move, vote again) or
operator-discretion failures (partial results read at a convenient moment). Live chain-local
voting kills the first class by construction, and complete-gated on-chain aggregation kills the
second: nobody, including the operator, can present a "result" the contract didn't compute from
all 20 frozen tallies.

## 7. The voting key: vote hot, hold cold

Serious holders keep their main key in cold storage — which makes frequent voting painful. SPT
lets an account register a **dedicated voting key**:

- Only the account's **main key** can register, replace, or deactivate a voting key, and wallets
  can scope the signature to exactly that action.
- The voting key can do **one thing: vote**. It cannot transfer shares, cannot rotate keys,
  cannot redirect dividends, cannot re-register itself.
- The main key always keeps the right to vote directly — registering a voting key can never lock
  the owner out.
- Rotating the account's main key **automatically revokes** any registered voting key — so
  recovering from a compromised key leaves no stale delegate with voting power. Registration and
  revocation both emit events carrying the key's fingerprint, so any observer can audit which key
  gained or lost the power to vote.

**Why:** governance participation should not require warming up the vault. A single-purpose hot
key bounds the damage of its own compromise to "someone voted my shares my way or the other way,
until I notice" — never "someone took my shares."

## 8. The gas station: participation costs nothing

Voting and claiming dividends are **free for holders**: a dedicated module, the gas station, pays
the network fee. Its entire design is about paying for those two things and *nothing else*:

- It sponsors a transaction only when the transaction's actual executed code — read from the
  signed envelope the node itself parsed, not from anything the sender claims — is **exactly one
  call** to `cast-vote` or `claim-dividends`.
- Sponsored transactions must stay within tight ceilings (gas limit ≤ 1,500, gas price ≤ 10⁻⁶ KDA)
  — two orders of magnitude below the block ceiling, but comfortable for a vote.
- A **per-epoch spending cap** bounds the total subsidy per 24-hour window. Every sponsored
  transaction pre-charges its worst-case cost against the cap; when the cap is spent, sponsorship
  pauses until the epoch rolls over — and the rollover is time-based only, so an attacker cannot
  buy, trigger, or hurry a reset.
- Everything **fails closed**: any check that cannot pass means the station simply doesn't pay.
  Voting and claiming still work self-paid, so the worst an attacker can achieve by exhausting the
  cap is to make participation cost normal gas for the rest of the day.

The station's KDA sits in — you guessed it — a capability-guarded account: it can leave only
through a sanctioned gas payment or an explicit operator top-up path.

**Why:** requiring holders to keep KDA on hand just to exercise their rights suppresses exactly
the participation governance needs. But an unlimited subsidy is a faucet for attackers, so every
dimension of the sponsorship — what, how much, how often — has a hard on-chain bound, and the
failure mode is "pay your own gas", never "lose funds."

*The above describes the station as deployed for the test event. The mainnet release candidate
keeps every bound and generalizes the fixed two-call allowlist into an on-chain registry of
budgeted operations, each with its own gas ceiling and daily budget, every policy change a
public event — documented completely in [GAS-STATION.md](GAS-STATION.md).*

## 9. The sale

The initial sale is a deliberately simple, fixed-price mechanism on chain 0: send KDA, receive SPT
from the 20,000-SPT sale reserve, at a published price (on testnet: 0.5 test-KDA per SPT — a test
parameter, carrying no implication for any future sale). The proceeds accumulate in a
capability-guarded sales-income account; withdrawals are admin functions that emit public events.
The operator can pause and resume the sale, and change the price — each action public and
event-logged.

There is **no per-buyer cap**, and that is a considered decision: an on-chain cap is theater when
anyone can create unlimited accounts. Rather than ship a control that only inconveniences honest
buyers, the design keeps the surface honest about what an open, pseudonymous sale can and cannot
enforce.

**Why fixed-price:** price discovery mechanisms (auctions, curves) add attack surface and
complexity that a first offering doesn't need. A fixed price makes the sale trivially auditable:
every purchase event shows amount and price, and the reserve's balance decreases in lockstep.

## 10. Life across 20 chains

Kadena scales by running many chains braided together. SPT embraces that:

- The token lives on **all 20 chains**; you can move shares between chains with the standard
  two-step cross-chain transfer (a debit on the source chain, a cryptographically-proven credit
  on the target chain).
- Your shares vote **where they live**. Move 10 shares from chain 0 to chain 5 and their voting
  power moves with them: released from your chain-0 vote at the debit, votable on chain 5 on
  arrival.
- Dividends accrue per chain against each chain's circulating float; the operator funds rounds
  chain by chain from the same global accounting.
- Chain 0 is the hub only in the sense that the sale runs there, supply was minted there, and
  final vote results are assembled there. No holder is required to use chain 0 for anything else.

**Why:** following the platform's native scaling model keeps SPT usable wherever its holders are,
instead of crowding everyone onto one chain — while the single aggregation point keeps the one
thing that must be global (the final vote result) in one verifiable place.

## 11. Upgrades, the freeze switch, and what the operator can and cannot do

The modules are **upgradeable under the admin keyset** — necessary while the system is being
proven on testnet — with one deliberate exception mechanism: every module carries a one-way
**freeze switch**. A redeploy that flips `FROZEN-MODULE` to `true` permanently disables all future
upgrades; operations continue, but the code can never change again. The intended mainnet path uses
it: community advisory vote → external legal review → source freeze → fresh independent audit of
the frozen source → deployment.

It's equally important to be precise about what the operator can do *today, without an upgrade*:

- **Can:** create/close/cancel proposals; fund dividend rounds; route revenue (publicly); set the
  sale price; pause/resume the sale; top up the gas station.
- **Cannot:** mint tokens; move any reserve outside the release calendar; vote reserves; change a
  tranche schedule or beneficiary; alter a tally; declare a vote "passed" (the contract computes
  results); take back distributed dividends; or block a holder's claim, vote, or transfer.

Every "can" is a public function that emits events; every "cannot" is the absence of any function
that could do it.

**Why:** the honest description of a young system is "upgradeable, working toward immutable". The
freeze switch makes the endpoint credible; the explicit can/cannot list makes the interim
trust assumption exact rather than vague.

## 12. Verify everything

None of the above asks for belief. The deployed bytecode-level truth — module hashes, the exact
deployed source, live balances, the vote, the time-lock schedules — is all queryable on the public
network, free, without an account. [VERIFICATION.md](VERIFICATION.md) lists every query.

---

> **Disclaimer.** This document describes the mechanics of experimental software on a public test
> network. All tokens are test tokens with no monetary value and confer no rights of any kind. The
> MAINNET-GO vote is advisory only — not binding, and not a commitment to deploy. Nothing here is
> investment, legal, accounting, or tax advice, or an offer or solicitation of any instrument, in
> any jurisdiction.
