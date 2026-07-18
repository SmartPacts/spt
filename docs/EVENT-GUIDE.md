# Smart Pacts — testnet06 Community Event Guide

**Hold Smart Pacts test-shares on Kadena testnet06.** Buy test-shares in the simulated sale, transfer
them (even across chains), receive test dividend rounds, and **vote — with zero KDA** — on whether
Smart Pacts should go to mainnet. Everything below is on a public test network with **valueless test
KDA/SPT**; nothing here is a real security, a real offer, or a real payment.

- **Network:** testnet06 · **API:** `https://api.testnet.chainweb-community.org`
- **Explorer:** https://explorer.chainweb-community.org/testnet
- **Namespace:** `n_d97ffd2ca290429b5dc85ce551a8d07d038e9641`
- **Modules:** `…​.smartpacts-shares` (the share + governance + dividends), `…​.smartpacts-ipo`
  (the sale), `…​.smartpacts-gas-station` (pays your gas so voting/claiming is free).
- **Portal (same journey in the browser):** https://smartpacts.io/event/
- **Browser-first guide (recommended for most people):** https://smartpacts.io/event/guide/ —
  this document is the CLI/tooling reference for the same journey.
- **Deployment verification** (module hashes + deploy request keys):
  [VERIFICATION.md](VERIFICATION.md).
- **Integration templates** — the full signable transaction (code, signers, capabilities,
  sender, gas) for every governance operation: [tx-templates/](tx-templates/README.md).

> **The one rule that makes voting free:** when you vote or claim dividends, submit the transaction with
> the **gas station as the payer** and set **gas limit ≤ 1500, gas price ≤ 1e-6**. Those are the
> station's drain-protection ceilings; a vote that exceeds them is refused. Wallets that support a
> "gas payer / gas station" field make this one setting.

---

## 0. What you'll need

- A Kadena testnet key / account (a `k:` account). **Chainweaver** (add testnet06 as a custom network:
  the API base above, network id `testnet06`) or any @kadena/client tooling works.
- Some **test KDA** — only to *buy* shares; voting and claiming are gasless. Get it from the community
  faucet (`free.coin-faucet` / `faucet.coin-faucet-v1` on testnet06, ~100 KDA per request):
  https://tools.chainweb-community.org/faucet/new

All share actions happen through the three modules above. Replace `NS` with the namespace and `YOU`
with your `k:` account in the snippets.

---

## 1. Create your on-chain account (chain 0)

Your `k:` account is created automatically the first time you receive KDA (faucet) or SPT. To hold SPT
you just need to have bought or received some — there's no separate registration.

## 2. Buy shares in the IPO — **chain 0**

The 20,000-SPT sale reserve lives on **chain 0**, so buys happen there. Price is **0.5 KDA per SPT**
*(test price — carries no implication for any future sale)*.

```pact
(NS.smartpacts-ipo.buy-shares "YOU" (read-keyset 'ks) 40.0)   ; buy 40 SPT for 20 KDA
```
- Sign with your key; authorize `coin.GAS` **and** `coin.TRANSFER YOU <sale-income> <cost>` (cost =
  amount × 0.5). Provide `ks` = your keyset in the tx data. Normal (self-paid) gas is fine here.
- Verify: `(NS.smartpacts-shares.get-balance "YOU")` on chain 0.
- *(tested: buying 40 SPT cost exactly 20 KDA, gas 541.)*

## 3. Move shares around (optional, and fun)

- **Same chain:** `(NS.smartpacts-shares.transfer "YOU" "FRIEND" 5.0)` (authorize
  `TRANSFER YOU FRIEND 5.0`).
- **Across chains** (e.g. move some shares to chain 5 so you can vote there):
  `(NS.smartpacts-shares.transfer-crosschain "YOU" "YOU" (read-keyset 'ks) "5" 10.0)` — a 2-step
  cross-chain transfer (step 0 on your chain, step 1 on the target with the SPV proof). Your shares,
  and their voting power, live wherever you move them.

## 4. Vote — **GASLESS** — on the MAINNET-GO proposal

You vote on **the chain where your shares live**, weighing your current shares. You can change your vote
while the proposal is open; if you transfer shares away, exactly that many leave your vote.

```pact
(NS.smartpacts-shares.cast-vote "YOU" "MAINNET-GO" true)      ; true = YES (approve mainnet), false = NO
```
- **Gasless setup:** tx `sender` = the gas-station account (`NS.smartpacts-gas-station.GAS_STATION`);
  add the `GAS_PAYER` capability for the station key; **you sign only `NS.smartpacts-shares.VOTE YOU`**;
  set **gasLimit 1500, gasPrice 0.000001**. You spend **zero KDA**.
- Verify your vote: `(NS.smartpacts-shares.vote-weight "YOU" "<your-chain>" "MAINNET-GO")`.
- *(tested end-to-end: a buyer with ~0.02 KDA voted, the station paid the 356 gas, the buyer's KDA was
  unchanged.)*

## 4b. Optional: register a dedicated VOTING key (hot key that can only vote)

You can register a second key that is valid **only for `cast-vote`** — keep your main key cold and
vote with the hot one. A stolen voting key cannot transfer, cannot claim to another account, and
cannot replace itself; your main key always keeps working and can override, replace, or clear it.

```pact
(NS.smartpacts-shares.set-vote-key "YOU" (read-keyset 'vk))   ; register/replace (vk = the hot keyset)
(NS.smartpacts-shares.get-vote-key "YOU")                     ; read: {guard, active}
(NS.smartpacts-shares.clear-vote-key "YOU")                   ; deactivate (main key only)
```
- `set-vote-key`/`clear-vote-key` are signed by your **MAIN** key — scope the signature to
  `NS.smartpacts-shares.VOTE-KEY-ADMIN "YOU"` (a scoped signature, so a malicious dapp can't
  sneak a registration onto an unrelated transaction). Self-paid gas; registration is per-chain.
- To vote with the hot key afterwards: identical gasless setup as §4, but the **voting key** signs
  the `VOTE` cap (the contract accepts the main guard OR the active voting key — main guard first,
  so a registration can never lock you out).

## 5. Receive & claim dividends — also GASLESS

Dividend rounds are **declared on-chain in advance**: a round is a rate per test-share plus an
effective timestamp, announced identically on all 20 chains (watch for the `ROUND-DECLARED`
event), and immutable once declared. At the effective moment, every circulating test-share accrues
exactly `rate × shares` — wherever it sits, no matter how it moved between chains before or after
(treasury and unsold reserve get nothing). Claiming is **permissionless and gasless** — anyone can
even trigger *your* claim, and it always pays *your* account.

```pact
(NS.smartpacts-shares.get-round-count)                       ; read: rounds declared so far
(read NS.smartpacts-shares.dividend-rounds "1")              ; read: round 1's rate + effective time
(NS.smartpacts-shares.pending-dividends-of "YOU")            ; read: what you're owed (KDA)
(NS.smartpacts-shares.claim-dividends "YOU")                 ; pay it to your account
```
- Gasless setup identical to voting (station sender, `claim-dividends` is the other allowlisted call).
- Rounds accrue to shares held at the round's **effective moment**; later buyers do not receive
  earlier rounds. Claims pay the exact 12-decimal amount; any finer remainder stays credited and
  rides into your next claim.
- One tip: shares mid-flight between chains at the exact effective moment are on no chain and skip
  that round — don't cross-chain right around an announced effective time.
- Planned test rounds: round 1 is planned for **July 11, 2026**; a second round after the event
  ends (after July 22, 2026). Dates are operator actions and may shift until declared on-chain.

## 6. Verify everything yourself (no keys needed)

Any of these as a read-only `/local` call on the API, or by searching accounts/request keys in the
explorer:

```pact
(NS.smartpacts-shares.get-circulating)                       ; community float on a chain
(NS.smartpacts-ipo.is-active)                                ; sale open?  -> true
(NS.smartpacts-shares.get-results "MAINNET-GO")              ; this chain's running tally
(NS.smartpacts-shares.get-final-results "MAINNET-GO")        ; chain 0: the COMBINED 20-chain result
```

---

## The MAINNET-GO vote — what it decides

One proposal, announced identically on all 20 chains: **"Approve the Smart Pacts contracts to be
deployed to mainnet."** It runs until **2026-07-18 05:56 UTC** (the close time is on-chain:
`proposal-details` shows it on every chain).
After it closes, the result is aggregated **on-chain across all 20 chains** and anyone can read
`get-final-results` — it "passes" only if participation reaches the **4,000 SPT quorum** and YES
outweighs NO.

**This vote is advisory:** it decides nothing on mainnet by itself (there is deliberately no mainnet
contract yet — that's the whole question). Smart Pacts will treat the result as **strong advisory
input** to its mainnet decision; the vote is not binding and creates no obligation. Show up and your
test-shares are counted.

## 7. Test it yourself — try to break it

The contracts make exact promises; every one is checkable with the reads above (the portal's
"Test it yourself" section wraps these same experiments in buttons and a live readout):

1. **Vote, then move across chains.** Vote on chain A, `transfer-crosschain` part of your holding
   to chain B: `vote-weight` on A drops by exactly the moved amount (and A's `get-results` with
   it); the arrivals are unvoted and can vote on B. The same test-share can never back two live
   votes.
2. **Vote, then transfer to another account.** Same-chain `transfer` releases exactly the sent
   amount from your vote at the moment of the debit; the receiver's test-shares arrive unvoted.
3. **Re-vote and partial release.** `cast-vote` again flips your full current weight in place,
   once — check the tally moves by exactly your weight. Transfer 1 test-share away: your recorded
   vote drops by exactly 1.
4. **A voting key can only vote.** After §4b, sign a `transfer` with the voting key instead of the
   main key — the module rejects it (the `TRANSFER`/`DEBIT` guard only accepts the account's main
   guard). The same key signs a `cast-vote` fine.

If any number disagrees with the promise, that's a finding — report it (see
[SECURITY.md](../SECURITY.md)).

## Fair-play notes

- Test KDA/SPT only; no real value; the sale/treasury/dividends are all testnet.
- The gas station sponsors a bounded number of free votes/claims per chain per day (drain protection);
  if it's momentarily "epoch cap reached", wait for the next epoch or pay your own gas.
- The operators hold no voting shares in the float (the reserves are excluded from voting by the
  contract). Your votes are the vote.
