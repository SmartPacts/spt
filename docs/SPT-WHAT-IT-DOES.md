# SPT — what it does, in plain language

SPT is a token on Kadena Community Edition (kda-chain.org). Two contracts ship: **the token**
(holding, moving, voting, awards, locked tokens, company money) and **the sale** (buying tokens
with KDA).

> **Two different people appear on this page, and the difference matters.**
>
> - **The administrator** is whoever holds the signing devices. They set the sale price, send
>   locked company tokens, announce awards and proposals, and can publish new code or freeze it.
>   There are three devices; some actions need two of them and some need one.
> - **A holder** is anyone who owns SPT. They can move it, vote with it, claim awards, and send it
>   to another chain. A holder needs no permission from the administrator to do any of that.
>
> **So "you" on this page always means a holder — the reader.** The administrator is never
> "you"; they are always named. If a sentence does not say "the administrator", it is describing
> something any holder can do or rely on.


<!-- promise-gate:legend -->
> **How to read the marks.** Every mark on this page is DERIVED from the promise manifest in
> `.github/scripts/promise-gate.py` and re-checked on every test run. None is written by hand,
> and the test suite FAILS if the page and the manifest disagree.
>
> ✅ a named test breaks if this stops being true · 🟡 built and believed true, but no test would
> catch it breaking · 📋 kept by a person following a process, not by the contract · ⛔ not built.
>
> A mark sits at the START of the sentence it judges, and each sentence carries at most one. The
> 🟢/🔵/🔴/⚙️ symbols in the tables below mean something else entirely — they say WHO MAY CALL a
> function — and never sit next to a status mark.
>
> A sentence with no mark is checked the same way but not rendered, so this page stays readable.
> **Only a ✅ promise is allowed to go unmarked** — an unmarked sentence is never bad news being
> hidden. **This page gets shorter as tests land.**
<!-- /promise-gate:legend -->

---

## In one minute

**What SPT can do**

- ✅ Hold and move tokens, on any of the 20 chains, and between them.
- ✅ Let holders vote yes/no on proposals, weighted by the tokens they hold.
- ✅ Pay awards in KDA, which accumulate until claimed and never expire.
- ✅ Sell tokens for KDA at a fixed price. **The administrator set that price at 200 KDA per SPT.** The sale
  opens on deploy day as a *separate, deliberate step* — deploying does not open it. Once open,
  changing the price needs the sale paused and **two** devices, so a wrong price is a public
  wrong price until the administrator takes it down. The floor is set to whatever price the sale
  opens at, so the
  sale can only ever be repriced **upward** without a second two-device act.
- ✅ Unlock the founder, treasury and liquidity tokens slowly, on a schedule nobody can speed up.
- ✅ Let the company receive and withdraw its own KDA.

**What SPT cannot do**

- 🟡 **Mint more than 100,000 tokens**, or burn any. The Kadena platform fix this depended on
  **went live on mainnet in August 2026** — so this is now true on the network SPT deploys to.
  The rule that produced it does not go away: the fix is re-measured on the target chain at
  deploy time, in the same session, never assumed from this page.
- 📋 **Decide a vote.** Each chain counts its own votes; the winner is added up outside the contract.
- 🟡 **Force an award.** The company is never obliged to declare one.
- ✅ **Stop the admin from changing the rules — until the contract is frozen.** Everything on this
  page is "how it behaves today"; only freezing makes it permanent. ✅ **It is not frozen yet.**
- 🟡 **Recover a lost key**, or reverse a transfer sent to the wrong address.
- 📋 **Prove who owns what beyond one account.** One person can hold several accounts.

---

## The tokens — who gets what

✅ 100,000 tokens, fixed. Nothing creates more after setup.

| Tokens | Who | When they unlock |
|---|---|---|
| **20,000** (20%) | For sale to the public | No unlock schedule — but **the sale ships CLOSED and only the administrator can open it.** Nobody can buy until they do |
| **10,000** (10%) | The founders — **one to any number of them**, each a plain address with its own amount, all fixed at setup and summing to exactly 10,000 (the contract refuses any other total) | Nothing for 1 year, then a little each day until year 4 — the same calendar for every founder |
| **55,000** (55%) | Treasury | Nothing for 1 year, then a little each day until year 5 |
| **15,000** (15%) | Market making / liquidity | Nothing for 3 months, then a little each day until year 2 |

🟡 The clock starts the moment the contract is set up, and the schedule cannot be changed afterwards.
✅ Each founder's tokens unlock independently — one founder claiming does not touch the others.
✅ **A founder can use any address they control, including a multi-signature account.** Restricting
founders to one-key addresses would not help: a one-key address whose key nobody holds strands the
tokens exactly as a broken multi-signature account would, so the restriction would close one of two
identical doors while banning every multi-signature founder.

🔴 **What protects a recipient now is not a stricter address check — it is that a wrong address no longer
loses anything.** ✅ **Each founder creates their own SPT account first, and the payment goes to an
account that already exists.** If it does not exist yet, the payment is simply refused and the
tokens stay in the reserve, waiting, earning nothing for anybody. The founder creates the account
and the payment goes through. Nothing is lost and there is no deadline — the first unlock is a
year away.

🔴 **The address is still final.** A founder allocation is sent to the address given at setup; it is fixed at
setup and can never be changed, and if the recipient cannot control that address nobody can recover
the tokens. How the address is made — one key, several keys, whatever the wallet does — is
yours to decide and yours to get right. A multi-signature founder can spend the tokens they
receive, not merely hold them — proven with a real 2-of-3 account, because "it arrived" and
"the holder can move it" are different claims and only the second one matters.

> 🔴 **Founder tokens and company tokens behave differently.**
>
> ✅ **The founders' 10,000** are locked to the addresses fixed at setup. ✅ They can only ever go
> there, anyone can trigger the payment once it has vested, and nobody can redirect them.
>
> ✅ **The treasury's 55,000 and market-making's 15,000 stay with the contract itself.** They are
> not paid to any account fixed at setup — there is no such account any more. As they vest,
> they become *available*, and **the administrator sends them where and when they decide**, in as many
> payments as they like. ✅ No more than has vested can ever be sent. ✅ Once sent, they are ordinary
> tokens: they vote and they earn awards, exactly like anyone else's.
>
> ✅ This means **the administrator controls where up to 70,000 tokens end up** — worth restating
> plainly because it is the single biggest discretion in the design. Two consequences follow:
> a lawyer should look at this before it is used on the real network, and tokens the
> administrator sends to a voting account **do vote** — only the reserves themselves are excluded.

---

## Who can call what

<!-- promise-gate:caller-legend -->
🟢 anyone · 🔵 the account holder, with their signature · 🔴 admin only ·
⚙️ the contract itself only — no transaction can call these
🔴 admin rows also say **(2 keys)** or **(1 key)** — see "Two admin keys, not one" below
<!-- /promise-gate:caller-legend -->

---

## Two admin keys, not one

Administrative authority has **two levels**, and the difference is how many of the three signing
devices have to agree.

| | what it takes | what it covers |
|---|---|---|
| **(2 keys)** | ✅ **Two of the three devices** must both sign the same transaction. | Anything that **moves money out**, or that **cannot be undone** |
| **(1 key)** | ✅ **Any one** of the three devices is enough. | Everyday running of the system, where a mistake can be undone |

**The (2 keys) list — money out, or no going back:**
setting up the token · setting up a chain · setting up the sale · sending company KDA out of the
funding account · taking back unowed money from the award pot · moving locked company tokens ·
taking the sale proceeds out · **putting money into the award pot** · **announcing an award
round** · **setting the sale price** · **changing the award notice period** · **changing the price
floor** · **and publishing a new version of the contract, or locking it forever**.

✅ **Anything that moves money out of the company's control, or creates a promise the contract must
honour, takes two devices** — even when it is routine work done on a schedule. The dividing line
is whether it can be taken back, not how often it is done.

**The (1 key) list — everyday running, and every item on it can be undone:**
putting a proposal on the ballot and withdrawing it · naming an award record date and cancelling
it · **retracting** an award round before it takes effect · pausing and resuming the sale.

> 🔴 **Why funding the award pot, announcing a round and setting the sale price all take two devices.**
> Each is individually reversible, but one device holding all three could chain them: cut the price
> to the floor, buy the sale reserve cheaply, then route company funding through the award pot and
> claim it back. The floor is also set from the price the sale opens at, rather than a fixed low
> number, so it bounds what it is supposed to bound.
>
> 🔴 **Retracting a round deliberately stayed at one device.** It *reduces* what the contract owes.
> A brake must never be harder to reach than the thing it stops.

### Why it is split this way

**Two keys is not "more secure", it is slower.** It is spent only where being wrong is
unrecoverable.

✅ **A lost or stolen device cannot publish new code**, and cannot move company tokens, take KDA
out of the funding account, touch the award pot, or sell the sale reserve. Whoever holds it can
cause **delay** — withdraw a proposal, cancel a record date, retract an award round, pause the
sale.

> 🔴 **This is enforced by the contract, not by procedure.** Three operations require two devices
> and the price floor is seeded from the opening price, so a single device cannot reach the award
> pot or, through the sale price, the reserve.

> **Why both halves matter.** Setting the price takes **two devices**, and creating the sale seeds
> the floor to **the price it is given**. Either alone would be insufficient: a one-device price
> change with a low floor lets a single stolen device pause the sale, cut the price to the floor,
> resume and buy the whole 20,000-token reserve in one transaction. Because the floor equals the
> opening price, the sale can only ever be repriced **upward** until someone deliberately lowers
> the floor — and lowering it needs two devices. An external review measured the one-device
> attempt being refused outright. The floor needs no manual step at launch; it is already correct.
>
> 🔴 **AND THE HONEST LIMIT OF THAT PROTECTION: the floor stops ONE device, not TWO.** An
> offensive review measured it (August 2026): with both governance devices, the floor and the price
> can each be lowered to the hard minimum and the whole 20,000-token reserve sells for **0.2 KDA**.
> That is not a hole — pricing the sale is exactly what two devices are *for*, and the hard minimum
> is a **fat-finger guard, not a value guarantee**. But it means the floor is protection against a
> stolen device and against a typo; **it is not protection against the two devices themselves.**
> Nothing in the contract can be, and no code change would improve it — what protects the operator there is
> keeping the two devices apart.

✅ **Whichever device can create one of those delays can also clear it, alone.** No second device is
needed to undo anything in the (1 key) list.

🔴 **Two things to know that the code cannot fix.**

📋 **Using the backup device last is a habit, not something the contract enforces.** Any one of
the three devices has full (1 key) authority the moment it is used, and no code can express an
ordering.

✅ **Which operations need two devices and which need one is fixed forever once the contract is
locked.** After that neither level can be widened or narrowed. If an operation is in the wrong
list, it stays in the wrong list.

### What an administrator's device actually shows

When an administrator approves a transaction, the signing device shows a list of **permissions** the signature grants.
These are the ones that can appear there — everything else in the contracts is either just a
record of something that happened, or internal machinery no transaction can ask for. The last
three rows are **holder-side**: they never appear on an administrator's devices, and they matter because
**a holder can scope a signature to just one of them** instead of signing unscoped.

| permission | what signing it allows | who signs it |
|---|---|---|
| `ADMIN-GOV` | Any of the **(2 keys)** operations above **that does not move money out** | the administrator, two devices |
| `ADMIN-OPS` | Any of the **(1 key)** operations above | the administrator, one device |
| `FUND-AWARDS` | Putting KDA **into** the award pot — money in, never out | the administrator, two devices |
| `GOVERNANCE` | Publishing a new version of the contract, or locking it forever | the administrator, two devices |
| `DISBURSE` | Sending locked company tokens from a **named** tranche to a **named** destination, up to a **stated amount** which is a real spending limit — and nothing else | the administrator, two devices, **scoped** |
| `WITHDRAW-FUNDING` | Sending a **stated amount** of company funding to a **named** destination — and nothing else | the administrator, two devices — **they must scope it themselves** |
| `WITHDRAW-PROCEEDS` | Sending a **stated amount** of token-sale proceeds to a **named** destination — and nothing else | the administrator, two devices — **they must scope it themselves** |
| `RECOVER-SURPLUS` | Taking back a **stated amount** of award-pot KDA that is owed to nobody — and nothing else | the administrator, two devices — **they must scope it themselves** |
| `TRANSFER` | Moving a stated number of tokens from one account to another | any holder |
| `TRANSFER_XCHAIN` | The same, but to another chain | any holder |
| `VOTE` | Casting or changing a vote — and nothing else. Satisfied by the account's own key, or by a registered voting key | any holder, **scopable** |
| `ROTATE` | Changing the key that controls an account — and nothing else | any holder, **scopable** |
| `VOTE-KEY-ADMIN` | Registering or clearing a dedicated voting key, so the key that votes is not the key that holds | any holder, **scopable** |

🔴 **`ADMIN-GOV` and `ADMIN-OPS` name a LEVEL, not a single job.** A signature granting `ADMIN-GOV`
so the award notice period can be changed **also authorizes every other (2 keys) setting in that
same transaction** — the device shows the level, not the errand. This is why the two levels
exist. 🔴 **So be precise about what that one signature covers.** Extracted from the contract, a
single `ADMIN-GOV` signature authorizes **seven** operations:

| | |
|---|---|
| **announcing an award round** | the one that **creates a payment obligation the contract must honour** |
| **setting the sale price** | |
| the price floor · the award notice period | the two settings |
| the three one-time setup steps | token supply, token per-chain, sale |

The two in bold are the ones that catch people out: the same signature that changes a setting can
also declare an award round and reprice the sale, in that same transaction. The **(2 keys)** list
further up this page is the full inventory of what one gov signature can reach.

✅ **Every operation that moves money out now names its own amount and destination.** That is all
four of them — locked company tokens, company funding, sale proceeds, and unowed award-pot KDA.
Locked company tokens came first because they are the largest single power in the design (up to
70,000 tokens); the other three followed in the same change, so no money-moving operation travels
under a general permission any more.

🔴 **The four money-out operations do not all behave the same way, and the difference matters to
whoever is holding the device:**

✅ **Every operation that moves money out now refuses a signature that does not name the
operation, its destination and its amount.** A
signature for one of these cannot be used for another, for a different amount, or for a different
destination — and an attempt to sign in the general way, without naming the operation, means **the
transaction will not run at all.** It cannot be got wrong by forgetting.

**All four are enforced by the contract.** Locked company tokens, funding, sale proceeds and unowed
award-pot KDA each refuse a signature that does not name the operation, its destination and its
amount. This is enforced in code, not left to the operator to remember — the sentence above is
true because of what the contract does, not because of what anyone remembers to do.

The approved amount is a **ceiling**: approving 100 KDA to an address means at most 100 can leave
for that address in that transaction.

🔴 **One payment per destination per transaction, though.** The ceiling holds across a split for
**locked company tokens**
(`DISBURSE`), which move on our own ledger. It is **false** for the three that move KDA: the second
payment to the same address in one transaction is refused by Kadena's own KDA contract before our
limit is even consulted, and **the error names the KDA contract rather than the operation the signer
signed**, which is confusing at exactly the wrong moment. Send one payment per destination, or split
across transactions. Measured on a real node.

🔴 **THE AMOUNT ON THE DEVICE IS A TOTAL.** When an administrator approves sending company
tokens, the number shown is the most that can leave for that destination in that transaction —
not the size of one payment. If the transaction makes several payments to the same place, they all
come out of the one approved number, and it stops when that number is used up.

This was **not** true until August 2026, and the difference mattered: approving 100 tokens once
allowed the same approval to be used again and again, and the whole 15,000-token pot could leave
on a signature that displayed 100. A security review found it, and the contract now keeps a
running total. Nothing about who may approve changed — it is still the administrator, two devices.

🔴 **AND IT IS A LIMIT ON ONE APPROVAL, NOT A LIFETIME CAP — read this before relying on it.**
"Spending limit" can be read as "this is all that can ever leave", and that is **not** what it
means. Each signed approval limits **that one transaction**. If a second approval is signed for
the same tranche and destination later, that second one starts from its own fresh number.

Measured on a real test network in August 2026, not argued: the same approval naming 100 tokens was
submitted twice as two separate transactions, and each time the contract reported the same figure
remaining — `of 100.0 managed`. A lifetime cap would have reported less the second time.

So the honest sentence is: **each approval limits one transaction.** What stops an unlimited total
is not this number — it is that every transaction needs the two devices again, plus the vesting
calendar, which no signature can move.

⚠️ **One practical consequence: a company-token disbursement must now be approved with the details
attached.** A blanket approval that just says "I am the admin" no longer works for this one
operation — it is refused. That is deliberate: a blanket approval is exactly the thing that could
not carry a limit. The operator runbook covers how this is signed; nothing else changed.

`TRANSFER` is a holder's permission, not an administrator's; what it does and does not protect a holder
from on today's engine is covered under *Holding and moving tokens*, and that caveat rests on a platform
fix, not on ours — and that fix went live on mainnet in August 2026.

---

## The token

### Holding and moving tokens

| | What you give it | What it does |
|---|---|---|
| 🟢 `create-account` | An account name and a key | Opens an SPT account. **No signature needed** — anyone can open an account under any unused name and attach their own key to it. Names derived from a key cannot be taken this way, which is why we tell holders to use those. |
| 🔵 `transfer` | Who from, who to, how much | 📋 Sends tokens to an account that already exists on this chain. |
| 🔵 `transfer-create` | Who from, who to, the receiver's key, how much | Sends tokens and opens the receiver's account if they don't have one. |
| 🔵 `transfer-crosschain` | 📋 Who from, who to, the receiver's key, which chain, how much | 🟡 Sends tokens to another chain. 🟡 **Two transactions**: they leave here, then a second one lands them there. |
| 🔵 `rotate` | An account and a new key | Changes the key controlling an account — **only if the account name is a plain nickname**. If the name was derived from the key (what wallets normally create), only a key producing the same name is accepted, so in practice that account's key cannot be changed. 🟡 A lost key has no recovery path. Same rule KDA itself follows. |
| ⚙️ `debit` / `credit` | — | The only two places tokens leave or enter an account. No transaction can call them; they run inside the transfers above. |
| 🟢 `get-balance` · `details` · `get-guard` | An account name | What an account holds, and which key controls it. |
| 🟢 `get-circulating` | — | Tokens counted for awards **on this chain only**. 🟡 There is no read that totals all 20 chains. |
| 🟢 `excluded?` | An account name | Whether an account is one the contract keeps out of voting and awards — the four reserves it owns itself, and nothing else. |
| 🟢 `get-launch-reserve` | — | The sale reserve's account name. Fixed in the contract itself, so it is the same on every chain and cannot be entered wrong at setup. |
| 🟢 `precision` | — | How many decimal places a token amount can have: 12. |

> 🔴 **SUPPLY: this section described a live platform weakness. IT WAS FIXED ON MAINNET IN
> AUGUST 2026, and the two "cannot"s above are now true on the network SPT deploys to.**
>
> There was a bug in the Pact engine itself — not in our contract — that let *another* contract
> reach into ours. While it was live that meant **tokens could be created from nothing** (our own
> test suite proves it by minting 987,654,321 SPT with no signature at all) and **tokens could be
> destroyed** (a foreign contract could burn a holder's balance). One route could even ride a
> holder's ordinary signature for a small transfer to mint a large amount, while their own balance
> was untouched.
>
> It was fixed in Pact 5.4.1 / chainweb-node 3.2 and switched on at the `Chainweb32` fork.
> **Measured on mainnet in August 2026: fork number 1, read from the chain-0 tip's own feature flags
> rather than taken from a dashboard.** Before that day this was known, deliberately accepted, and
> **measured by tests that assert the broken behaviour on purpose** so we would find out the moment
> it changed.
>
> 🔴 **THREE THINGS THAT DO NOT CHANGE NOW THAT IT IS FIXED.** The hard rule stands: the fix is
> re-measured active on the target chain in the same session as the deploy, never assumed. The
> defences built while it was live **stay in the contract** — they freeze, a frozen module outlives
> every engine version, and a later platform regression would be unfixable. And the tests that
> assert the old broken behaviour stay too: they describe the *local* test engine, not mainnet, so
> if one goes red it gets triaged, never relaxed.
>
> 🟡 **After the fix**, tokens cannot be destroyed by any function here, and every debit is matched
> by a credit. What is left is a cross-chain transfer that never finishes its second step. That can
> happen two ways: you never send it, or **somebody else blocks it** — see the warning below. Either
> way the tokens are not destroyed. They sit part-way, still owed to the receiver you named, and
> they stay there until that second step can run. KDA behaves the same way, in both respects.

> 🔴 **Always send cross-chain transfers to a wallet address — the contract will NOT stop you, and
> checking first will NOT save you.** A cross-chain transfer happens in two steps, and the first one
> takes the tokens off the sending chain immediately. Send to an address whose name is **derived
> from its key** — the `k:` addresses every wallet gives you, and equally the `m:` and `c:`
> addresses another contract uses. Nobody else can open one of those names, because the name only
> works with the matching key.
>
> 🔴 **If you send to a nickname-style account instead, someone can block the delivery on purpose,
> after you have already sent.** The name does not have to be taken beforehand. Your first
> transaction is public and shows the nickname you are sending to, and there is a gap of minutes
> before the second step can run. In that gap **anyone at all** can open that same nickname on the
> destination chain under **their own** key. It costs them only a network fee. They need no SPT, no
> permission, and no signature from anyone. When your second step arrives it finds the wrong key on
> that name and stops.
>
> 🔴 **So checking the destination first proves nothing.** A nickname being free when you look does
> not mean it will still be free when your tokens land. This is not bad luck you can avoid by
> looking — it is a choice someone else can make *after* watching you send.
>
> **And the tokens are not destroyed — they are held.** They are off the sending chain and not on
> the destination chain, and they stay that way until whoever holds that nickname points it at your
> key. They can do that at any time, or never, and they can ask you to pay them to do it. There is
> no deadline and no undo. Tell a holder **stuck, and someone else decides** — never "burned".
>
> 🔴 **This risk is accepted deliberately.** SPT behaves exactly like Kadena's own KDA contract,
> which carries the same exposure: *"if the coin contract can accept the risk of burn
> coins for using a none principal guard on the other end chain, we can do it as well."* **That
> parity is real and was re-measured in August 2026: KDA's own contract can be blocked in exactly
> this way, by the same unsigned stranger, after the sender has already been debited.** The
> trade was a narrow protection against schedule, and against locking nickname-account holders out
> of receiving cross-chain at all. **The consequence is that this warning, not the code, is now
> what protects a holder here.** It has to reach them wherever they are told how to transfer, and it
> has to say *"someone can do this to you"* — not *"that name might already be taken"*.
>
> The contract still refuses one related thing up front, before your tokens move: a destination
> whose name *looks* key-derived but is paired with the wrong key **in the same transaction**. That
> check stayed. Ordinary same-chain transfers are unaffected by any of this.

### Voting

🟡 Votes are **yes or no** — never multiple choice. A proposal is announced, waits, then opens.

| | What you give it | What it does |
|---|---|---|
| 🔴 `create-proposal` **(1 key)** | An id, title, description, the time now, when voting opens, how long it runs | Announces a vote. Voting must open **at least 48 hours after announcing**, and must run **between 3 and 14 days**. Both limits are permanent. |
| 🔴 `cancel-proposal` **(1 key)** | The proposal id | Voids a proposal — **only before voting opens**, never once it has started. 📋 One cancelled copy voids the whole result. See *What withdrawing a proposal does and does not promise* below. |
| 🔵 `cast-vote` | Who is voting, the proposal, yes or no | Votes on the chain where your tokens are (holder). Refused before voting opens and after it closes. |
| 🟢 `close-proposal` | The proposal id | Marks a finished vote closed. Anyone can. 🟡 It does not change the result, but **every vote left open makes all transfers on that chain more expensive until it is closed** — so close them. |
| 🟢 `vote-record` | The proposal id | **The audit read.** Everything about the proposal on this chain, plus a fingerprint proving it is the same proposal as elsewhere. |
| 🟢 `get-results` | The proposal id | This chain's yes/no totals. |
| 🟢 `get-vote` · `vote-weight` | 🟡 Voter, chain, proposal | The weight recorded for one voter. |
| 🟢 `proposal-details` | The proposal id | Title, description, timing, status. |
| 🔵 `set-vote-key` | Your account and a voting key | Registers a lower-risk key allowed to vote for you (holder). It must be a key or keyset — an empty one is refused. |
| 🔵 `clear-vote-key` | Your account | Turns that voting key off. |
| 🟢 `get-vote-key` | An account name | Which voting key an account registered. |
| 🟢 `proposal-active?` | The proposal id | Whether voting on it is open right now, on this chain. |
| 🟢 `get-prop-count` · `active-prop-indices` | — | The contract's counter for the open-proposal list · which proposals are open right now. Every open one makes transfers on that chain cost more, which is why closing them matters. |

> ✅ **Moving tokens only reduces your vote by what you no longer hold.** If you still hold
> enough to back your whole vote, your vote is untouched. This matters because anyone can
> send you tokens without asking, and returning an unwanted gift must not cost you part of a vote
> your remaining balance still fully backs. A test fails if that behaviour ever changes.
>
> 📋 **Announcing a vote is 20 transactions, not one** — the same proposal must be sent to each chain,
> and each must land **at least 48 hours before voting opens**, not merely before it opens: a chain
> that lands any later is refused outright. A chain that misses it cannot take part, and its holders
> are left out while the others publish a total.
>
> **The result is added up outside the contract**, from all 20 `vote-record` reads. Only count them
> when you have read **all 20**, each once, every one exists, every one is past its close time,
> every fingerprint matches, and **none** is cancelled. Do not require the 20 statuses to match —
> they legitimately differ.
>
> ✅ **Your weight is your balance at the moment you vote.** ✅ Sending tokens away shrinks your recorded
> vote automatically; **buying more does not increase it** unless you vote again. Voting again
> replaces your previous vote.

### Awards, paid in KDA

> ### 🔴 The two "at most" limits on awards are gone — and what replaced them is stronger
>
> There is no fixed ceiling on the rate or the round. A flat ceiling is a rough stand-in for the
> question that actually matters, which the contract answers directly: *can this chain actually pay
> for the award being announced?*
>
> **What the administrator does instead:** asks `funding-needed` what this chain needs, sends exactly that, and
> declares.
> ✅ **A mistyped rate is refused outright, because the money for it is not there.**
> That is better than a ceiling was: a ceiling still let a
> wrong-but-under-the-cap rate through, and only limited how bad it got. This refuses the mistake
> at the moment the administrator makes it.
>
> 🔴 **The one mistake this does NOT catch, stated plainly because it is now the only one:** a
> wrong rate that the pool *already covers* — funded generously, then announced a rate lower
> than intended. Nothing refuses that, because the money genuinely is there. **The remedy is
> that there are at least 6 hours to retract it, counted from the moment it is announced**, on
> every chain. Two different numbers are at work and it matters which is which: the award has to
> be announced at least **12 hours** before it takes effect, and a retraction is refused inside
> the **last 6 hours** before it lands. So the shortest legal award leaves a **6-hour**
> window to change course, not a 12-hour one. That 6-hour window is the only thing standing
> between a mis-typed rate and a payout, so treat it as a hard floor, never a formality.
>
> ✅ **The notice period can be made LONGER, and can never be made shorter than 12 hours.**
> The notice period is a setting rather than a fixed number, and the window to change course
> is always that notice **minus 6 hours** — a notice of two days gives 42 hours, not
> 48. Lengthening it is always safer. **Shortening
> it stops at 12 hours and no key of any kind can go below that**, before or after the contract
> is locked. Changing it needs **two devices**; using it needs one.
>
> Both settable limits still move after the contract is frozen — locking the contract freezes the
> code, not the numbers the administrator is allowed to choose, so a limit that is adjustable today stays
> adjustable forever, within its floor. The same is true of the sale's price floor.
>
> 🔴 **It is set per chain, like everything else about a round.** If the administrator lengthens the window,
> they must do it on all 20 — a chain still on the old window will accept an announcement the others
> refuse, and nothing on the blockchain will tell the administrator.
>
> **There is no maximum date.** An award has to be at least 12 hours out, and nothing caps how far
> ahead it can be set. A date typed too far ahead jams the administrator's own schedule until it is
> retracted; it cannot cost a holder anything they are owed.

**Set the date first, then fund, then declare.** This is the required order, and it is what makes
the number funded the number owed.

> ### 🔴 The record date — the part that changed
>
> ✅ **A record date is announced with no rate attached, and the count it takes is then frozen.**
>
> ✅ **A round pays out exactly the rate times that frozen count** — not a penny more, whatever
> the chain's balances do afterwards.
>
> ✅ **Anyone can take the count once the date has passed**, so a quiet chain still gets counted.
>
> **The administrator announces a DATE before announcing a rate.** On that date the contract writes down how many
> tokens are in circulation on each chain, and that number is then **frozen**. The administrator reads it, decides
> how much per token to pay, funds exactly that, and declares.
>
> **Why the order matters.** If the amount funded were measured on the day of the *declaration*,
> the number would keep growing until the award landed — anyone buying in between would be owed
> money nobody had put aside. Measured on the real contract: funded 2.0 KDA, one stranger's ordinary
> purchase took the true debt to 5.0. Because a claim pays all-or-nothing, that gap became a race an
> honest holder could lose. **With a frozen date the number cannot move.**
>
> ✅ **Someone who buys after the date is simply not in that round.** They are not short-changed;
> that round was never about them. They are in the next one.
>
> ✅ **A wrong date is fixable.** The administrator can cancel it up to 6 hours before it lands. A wrong *rate* is
> fixable too — retract it and declare the corrected rate **on the same date**, without re-running
> anything.
>
> ✅ **A repeated announcement against the same date is refused, not silently doubled.**
>
> 🔴 **One date at a time, and one award per date.** A new date cannot be set while an announced
> award is still waiting to land, and two awards cannot be announced against the same date — a
> repeated announcement is now **refused** rather than silently doubling what the chain pays.
>
> 🔴 **Fund all twenty chains before declaring on any of them.** A chain funded late is a timing
> problem, not a money problem — nobody can meet an empty pool, because paying requires a
> declaration. But a holder on a late chain sees a friend paid and themselves not, with nothing on
> screen explaining why.

| | What you give it | What it does |
|---|---|---|
| 🔴 `schedule-snapshot` **(1 key)** | The date and time the count is taken | **Step 1.** Names the record date. No rate attached. Use the same instant on all 20 chains. |
| 🔴 `cancel-snapshot` **(1 key)** | — | Cancels a record date not yet reached — up to 6 hours before it lands. |
| 🟢 `advance-snapshot` | — | Takes the count once the date has passed. **Anyone can run it**, so a quiet chain still gets counted; it does nothing if nothing is due. |
| 🟢 `funding-needed` | A rate in KDA per token | **The number to send.** What this chain needs in total — this round *and* anything still unclaimed from earlier ones — what the pool holds, and the difference. |
| 🟢 `chain-report` | — | **One call, everything about this chain**: tokens held here, circulating, funding, pool, what is owed, what is spare, the current record date and the frozen count. |
| 🟢 `snapshot-circulating` · `get-snapshot` | — · a date number | The frozen count the round is priced against · everything recorded for one record date, including whether it exists at all. |
| 🟢 `get-snapshot-gen` · `get-snapshot-at` | — | Which record date this chain is on · the next one scheduled, if any. |
| 🟢 `get-total-distributed` | — | Total KDA moved into this chain's award pool, net of anything recovered. |
| 🟢 `round-funding-bar` | A rate in KDA per token | The exact amount the contract will demand before it accepts that rate. `funding-needed` reports this same number. |
| 🟢 `snap-m` · `snap-corr-of` · `snap-open` · `plan-snap` · `gkey` | — | Internal arithmetic behind the frozen count. Readable, but nothing an operator needs to call. |

**Fund first, then declare.** ✅ A round is refused unless the money is already in the pool.

| | What you give it | What it does |
|---|---|---|
| 🔴 `fund-awards` **(2 keys)** | An amount of KDA | Puts the money into this chain's pool. **Do this first.** |
| 🔴 `declare-round` **(2 keys)** | An id, a rate in KDA per token, when it takes effect | Announces an award. **Refused unless the pool already covers it, to the last decimal.** ✅ **The effective date must be at least 12 hours away.** 📋 Must be repeated on all 20 chains with identical values. |
> ### What withdrawing a proposal does and does not promise
>
> ✅ **A proposal can only be withdrawn before its voting opens — never once it has started**, and
> during that window nobody has voted on it yet, so withdrawing it cannot be a reaction to its own
> result. That is the promise, and it holds.
>
> 🔴 **What it does NOT promise is that the administrator is uninformed.** If two proposals are running on
> different schedules — the ordinary case — one may already be collecting votes while another is
> still in its withdrawal window. So the administrator could read the first and then withdraw the second. The
> contract does not stop that, and **it was decided not to make it stop that**: the administrator controls what gets
> announced at all, so they could get the same information by simply not announcing the second
> proposal — and blocking withdrawal whenever anything else is being voted on would take away the
> only way to fix a proposal sent out by mistake, inside the 48-hour window that exists for it.
>
> 🔴 **The cost of that decision, stated plainly because it lands on holders and not on the administrator:** once
> a vote is announced, people may buy tokens or organise around it. Withdrawing it afterwards wastes
> that effort; never announcing it wastes nothing. **That is a real harm and it is not fixed** — it
> is the one thing a code change would have addressed, and the remedy for administrator mistakes was chosen
> over it. If the administrator withdraws an announced proposal, the reason is stated publicly.

| | What you give it | What it does |
|---|---|---|
| 🔴 `set-runway` **(2 keys)** | A number of seconds | Changes how much notice an award or record date must give. **Never below 12 hours**, whatever key is used and whether or not the contract is locked. Longer is always safer. **Set it on all 20 chains.** |
| 🟢 `get-runway` | — | The notice period currently in force on this chain. It is read back after any change — this is how you confirm all 20 chains agree. |
| 🔴 `retract-round` **(1 key)** | The round id | ✅ Cancels the newest round — **only up to 6 hours before it takes effect**, not right up to the moment. |
| 🟢 `apply-round` | The round id | Bookkeeping that keeps later transactions cheap. **Not required for holders to be paid** — an award is owed and claimable as soon as its date passes. |
| 🟢 `claim-awards` | An account name | Pays out. ✅ Anyone can trigger it; the KDA always goes to the holder. |
| 🟢 `pending-awards-of` | An account name | What an account can claim right now. |
| 🟢 `get-round` | A round number | One round's rate and effective date, and whether it exists at all — this is what proves all 20 chains got the same round. |
| 🟢 `get-rounds-applied` · `declared-liability` · `pool-surplus` | — | Rounds folded in so far · what this chain will owe once every declared round is in effect · pool KDA owed to nobody. |
| 🟢 `award-liability` | — | ✅ What this chain owes its holders in KDA **right now**. |
| 🟢 `get-rpt` · `max-rpt` | — | The award rate per token accumulated so far · what that rate will be once every **declared** round — including future-dated ones — has taken effect. |
| 🟢 `outstanding-rate` · `get-round-count` | — | Rounds already in effect but not yet folded into the running rate by `apply-round` · how many rounds have been declared on this chain. |
| 🔴 `recover-pool-surplus` **(2 keys)** | An amount | Takes back pool KDA owed to nobody. 📋 **Only run this after a round is declared** — before that, money just deposited counts as surplus. |

> 🟡 **Awards accumulate and never expire.** ✅ Reserve accounts always read zero.
>
> ✅ **There is no obligation to ever declare an award.** ⛔ The company may reinvest everything, for
> years, without breaking any rule in the contract.
>
> ✅ **The money a round needs is measured against a count of tokens frozen at the record date**, so
> someone buying after that instant does not change what the round owes.
>
> 🔴 **The amount owed cannot grow after the record date.** The record date freezes
> the count FIRST; the amount owed is then that frozen count times the rate, and someone buying
> after the record instant changes nothing — measured: *"the bar is rate × SEALED float (6000), not
> rate × current float (9000)"*, and a buyer inside the window *"is owed nothing"*.
> Topping up still exists as a safety path; it is no longer something the design depends on.
>
> **A partial retraction does not fail safe.** 📋 Retracting on 19 chains and being refused on the 20th
> locks the difference in permanently. Do all 20, then check all 20.

### Locked tokens

| | What you give it | What it does |
|---|---|---|
| 🟢 `release-tranche` | `founder:` plus that founder's address (one entry per founder) | Pays a founder whatever has vested. Anyone can trigger it; the tokens only ever go to that founder's address. |
| 🔴 `disburse-tranche` **(2 keys)** | `treasury` or `liquidity`, a destination account, and an amount | ✅ **The administrator sends treasury or market-making tokens to an account they choose.** Refused unless the amount is already vested and not yet sent. The destination must already exist as an SPT account, and cannot be one of the contract's own accounts — including the sale's. |
| 🟢 `tranche-available` | `treasury` or `liquidity` | **How much can be sent right now.** |
| 🟢 `tranche-releasable` · `get-tranche` | Which tranche | How much is payable now · the full terms. |
| 🟢 `tranche-vested` | A total, its two dates, and a time | The vesting curve itself, as pure math: zero before the cliff, then a straight line, then exactly the total. 🟡 Every release, payment and availability read uses this one formula. |

> ✅ At the cliff you get **zero**; it accrues after.
>
> 🔴 **Two different rules, and the difference is deliberate.**
> ✅ **Founder tokens:** nobody — not even the administrator — can speed up, redirect or cancel
> them. They go to the founder addresses fixed at setup and nowhere else, and anyone can trigger
> the payment.
> ✅ **Treasury and market-making tokens:** the *calendar* is equally fixed — no more can ever be
> paid out than has vested — but
> **the administrator sends vested treasury and liquidity tokens wherever they choose, whenever they choose, in as many separate payments as they like.**
> ✅ Every such payment is published on-chain with its destination and amount.
> **There is no undo.** ⛔ A payment to a wrong address cannot be reversed by anyone, so read the
> destination twice.

### Company money

| | What you give it | What it does |
|---|---|---|
| 🟢 `receive-funding` | Who is paying, how much | Anyone can pay KDA funding into the company account. It refuses to pull from the protocol's own accounts. |
| 🔴 `withdraw-funding` **(2 keys)** | A destination and an amount | Moves company KDA out — expenses, investment. 🟡 No allowlist, no cap. |

### Plumbing — the contract's building blocks

Everything on a public blockchain is public, so these can all be *read* by anyone — but they
exist for the contract's own use. Each one either answers a question, computes something without
writing it, or refuses a bad input. **None of them can move tokens or money on its own.** They
are listed so this page accounts for every function in the contract, with nothing invisible.

| | What it is for |
|---|---|
| `curr-time` · `this-chain` | The current block's time, and this chain's number, as the contract reads them. |
| `enforce-unit` | Refuses any amount with more than 12 decimal places. |
| `validate-account` | Refuses a malformed account name — too short, too long, bad characters. |
| `enforce-beneficiary-address` | Checks a founder address is a real address of a supported kind — one key or a keyset, never the rotatable kind, never one of the contract's own internal accounts, never an empty keyset anyone could satisfy. This is everything an address alone can be judged on. |
| `enforce-beneficiary` | The same checks plus the one that needs the key: that the address really is the address of the key controlling it. Runs when the tokens are paid, against the account's own record. |
| `enforce-reserved` | Refuses a `k:`-style name whose key does not match it. This is why nobody can squat an address derived from your key. |
| `account-guard` | 📋 The contract's own lookup of which key controls an account (same answer as `get-guard`). |
| `protocol-account?` | Answers whether a name is one of the contract's own five protected accounts. |
| `credit-plan` | Computes everything a credit *would* do — all checks plus the award checkpoint — without doing it. The one place every credit's rules live. |
| `plan-tally` · `plan-deindex` | Compute a vote's new tally, and an open-list removal, without writing. The actual writes happen only inside `cast-vote`, `debit` and `close-proposal`. |
| `results-of` | Packs a yes/no pair into the shape the vote reads return. |
| `vkey` · `pkey` · `rkey` | How the contract builds its internal record keys — votes · open-proposal slots · award rounds. |
| `TRANSFER-mgr` · `TRANSFER_XCHAIN-mgr` | Bookkeeping for signed transfer approvals. ⚠️ Until the Kadena platform fix is live on the target network, this bookkeeping is **not** a spending cap — never tell a holder it limits their exposure (see the platform note at the bottom). |
| `DISBURSE-mgr` | Keeps the running total for a company-token disbursement approval, so the number approved is the most that can leave — across every payment in that transaction, not just the first. This is what makes the amount on the administrator's device a **limit**. ⚠️ Unlike the two above, this one is **not** waiting on the platform fix: it protects the company against its own mistake, not a holder against a hostile counterparty, so it works today. |
| `WITHDRAW-FUNDING-mgr` | The same running total, for company funding. The approved amount for a destination is the most that can go there in that transaction. Unlike locked tokens, this one takes **a single payment per destination per transaction**. |
| `RECOVER-SURPLUS-mgr` | The same running total, for taking back award-pot KDA that is owed to nobody. There is no destination to approve because that money can only return to the funding account. |
| `WITHDRAW-PROCEEDS-mgr` | The same running total, for token-sale proceeds. |
| `funding-guard` · `pool-guard` | Build the ownership locks for the company's two KDA accounts. |
| `ensure-coin-account` | Opens the company's KDA accounts at setup if they are missing — and tolerates ones someone pre-created, so a squatter cannot break setup. |
| `enforce-not-initialized` | The one-shot lock: setup refuses to ever run twice. |
| `enforce-launch-reserve` | Refuses any sale-reserve identity except the exact one written into the code, with a matching key. |

---

## The sale

**The sale is installed on chain 0 only.** You buy there; to hold tokens elsewhere you move them
with a cross-chain transfer afterwards. 📋 Tokens, voting and awards work on all 20 chains.

| | What you give it | What it does |
|---|---|---|
| 🔵 `buy` | 🟡 Your account, your key, how many tokens | Pays KDA, receives tokens at the current price. The sale's own accounts are refused as buyers. |
| 🟢 `get-price` · `is-active` | — | The price per token · whether the sale is open. |
| 🔴 `set-price` **(2 keys)** | A new price | 🟡 Changes the price — **refused while the sale is open**, and **never below the floor**, which now starts equal to the price the sale opened at rather than a fixed 0.01. There is no upper limit: a price set too high simply makes no sales, and the administrator fixes it by pausing, re-pricing and reopening. |
| 🔴 `set-min-price` **(2 keys)** | A new floor | Changes the lowest price the sale will ever accept. **Never below 0.00001 KDA per token**, whatever key is used and whether or not the contract is locked, and **refused while the sale is open**. This exists so a mistyped price cannot hand someone the whole reserve — measured, a price of 0.000000000001 bought all 20,000 tokens for 0.00000002 KDA. At the floor itself the whole reserve would still cost only 0.2 KDA, so **the floor stops a mistyped price, it does not make a low one safe** — what protects the reserve is the price the administrator actually sets, and the fact that lowering the floor takes two keys. |
| 🟢 `get-min-price` | — | The price floor currently in force. |
| 🔴 `pause` / `resume-sale` **(1 key)** | — | Closes and opens the sale. **It starts closed** and stays closed until someone opens it. |
| 🔴 `withdraw-proceeds` **(2 keys)** | A destination and an amount | Moves the sale's KDA out. |
| 🟢 `reserve-account` · `proceeds-account` | — | The sale's two account names: where the unsold tokens sit, and where buyers' KDA lands. |

**Sale plumbing** — same idea as the token's plumbing table: `enforce-price` (the one price
check that setup and `set-price` share — never below the current floor, right precision),
`launch-reserve-guard` · `sales-proceeds-guard` (build the sale's ownership locks), and
`enforce-not-initialized` (the sale's own one-shot setup lock).

> ✅ **No per-buyer cap** — it was removed because anyone can use several accounts.
>
> **Changing the price forces a pause first**, so an in-flight purchase fails rather than settling at
> a price the buyer never saw. One honest gap: a signed purchase stays valid for a short window after
> signing, so the rule is to wait that window out before reopening. That rule lives in the runbook and
> depends on the operator following it.
>
> **Unsold tokens stay in the sale's reserve.** ✅ They are outside voting and awards while they sit
> there, but nothing retires them — the sale can be re-priced and reopened.

---

## Setup — once per chain

| | What you give it | What it does |
|---|---|---|
| 🔴 `init-supply` **(2 keys)** | The founder list (each founder's address and amount — the amounts must sum to exactly 10,000) and the sale reserve | **Chain 0 only.** Creates the accounts, issues all 100,000 tokens to the four reserves, and starts the vesting clocks — one locked schedule per founder, plus treasury and liquidity which the contract keeps. **Treasury and market-making need no account here at all.** |
| 🔴 `init` **(2 keys)** | The sale reserve, with its key | **The other 19 chains.** Creates the accounts. 🟡 No tokens are issued. |
| 🔴 `init` (sale) **(2 keys)** | The opening price | Sets up the sale on chain 0, closed. |

> ✅ **Order matters:** the token must be set up on a chain before the sale is.
>
> ✅ **A configured address is checked to be a real address of a supported kind, and nothing else** —
> founder addresses carry no key at all, so there is no pair that can mismatch. A
> mistyped founder address cannot be paid: the payment is refused until an account with that exact
> address exists. ✅ The value is written to the public event log at that moment. **The
> deploy checklist's comparison of every chain against chain 0 is still required** — the contract
> cannot catch an address that is wrong but valid and correctly keyed.

---

## Gasless transactions

A third contract would let holders vote and claim without owning KDA. 📋 **It is not part of the first
deployment** and ships separately after its own audit. Read everything above as: the caller pays
their own gas.

---

## Four things that are true of the whole system

0. 📋 **The contract has been reviewed at exactly the version that would deploy.** The review found
   **no CRITICAL, no HIGH, and nothing at any severity in the contract's own logic.** Every finding
   was in operator instructions, this page and its sources, or the automatic checks — not in the
   code that holds the tokens. All are closed.
   **Three things must still happen, in this order:** the Kadena platform fix is re-measured on each
   chain at deploy time (point 2); the award-round instructions are corrected before any award round
   is declared; and the freeze instructions are corrected before the contract is ever locked. The
   first is routine, the other two are corrections to *this project's paperwork*, not to the
   contract. 📋 **A lawyer should review the treasury-sending power before it is used on the real
   network** — building it now was necessary (it is impossible to add after freezing); using it is a
   separate decision.
   > ⚠️ **Do not trust this paragraph on its own.** Hand-written status lines in this project have
   > gone stale in this project before now. The internal review reports hold what each audit
   > actually measured; if this paragraph and a report disagree, the report is right.
1. 📋 **No contract code is deployed anywhere** — not mainnet, not testnet. **But the namespace and
   both admin keysets ARE live on mainnet, on all 20 chains, since August 2026, and that part is
   permanent** — it is the governance authority the three devices control, and it cannot be
   un-created. What is not yet on the network is the contract code itself.
2. 📋 **Nothing deploys until the Kadena platform fix is live on the target chain**, measured there at
   the time, never assumed. That fix stops *other people's contracts* from reaching into SPT.
   **It went live on mainnet in August 2026** — so this condition is now satisfiable, and it is still
   re-measured per chain at deploy time rather than inherited from this line.
2b. 🔴 **One permanent dependency on Kadena that cannot be removed, and it matters before
   the freeze is approved.** SPT talks to KDA through Kadena's own `coin` contract, and the
   blockchain permanently ties our frozen contract to the exact version of `coin` it was built
   against. If Kadena ever ships a `coin` update that drops that link, **everything involving KDA
   stops on a frozen SPT** — funding awards, paying awards, taking funding in or out, and the sale
   — and KDA already sitting in the company's award pot and funding account is **stuck there**.
   Tokens, voting and vesting keep working, so the contract would be half-alive.
   **Nothing in our code can prevent this** — a contract cannot vouch for someone else's contract —
   and inventing something that tried would be a mechanism defending against a third party's future
   choice. Kadena has always kept old versions working. What we do instead is procedural: **we
   re-deploy on every chain immediately before freezing**, so the link points at that day's `coin`,
   and only then freeze. This is recorded as a signed-off decision, not a hidden risk.

3. **Freezing is what makes the rules permanent, and it has not happened.** ✅ Until then, whoever holds
   the admin key can upgrade the contract and change anything on this page — including supply,
   balances and the vesting schedules. Every "cannot" above is a statement about the frozen contract.
   ✅ After freezing, no function can ever be changed or repaired.
4. 🟡 **Once frozen, value can still leave.** The complete list, all of which survive the freeze:
   - 🔴 **`disburse-tranche`** — admin-only, up to **70,000 SPT** (treasury + market-making) to any
     address the administrator chooses, as it vests. This is the largest exit by far, and this page
     describes it above.
   - 🔴 `withdraw-funding` — admin-only, company KDA out.
   - 🔴 `withdraw-proceeds` — admin-only, sale KDA out.
   - 🟢 `claim-awards` — **permissionless**: anyone can trigger it, and the KDA always lands on the
     holder it is owed to. ✅ Money leaving the pool this way is money already owed.
   - `recover-pool-surplus` is admin-only but does **not** take value out of the contract — it moves
     KDA from the pool to the company account, and `withdraw-funding` is what then removes it.

   That is the trust the design asks of holders, and it is worth stating plainly anywhere it matters.

> 🔴 **"The treasury cannot vote" is NO LONGER TRUE, and was never a guarantee the contract could
> make.** 🟡 Treasury tokens sent to someone become ordinary tokens that vote
> and earn — that is the design. 📋 The contract only keeps *named
> accounts* out of voting, never the tokens behind them: one person can hold both an excluded
> account and an ordinary one, and no contract can tell them apart. This is a disclosure and
> governance matter; never describe it to a holder as something the contract enforces.

