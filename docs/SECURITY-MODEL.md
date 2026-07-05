# SPT — Security model

What the contracts enforce, what an operator can and cannot do, which attacks were designed
against, and the honest status of security review. For how to report a vulnerability, see
[SECURITY.md](../SECURITY.md).

## Invariants the code enforces

These hold by construction — there is no function whose success violates them:

1. **Fixed supply.** 100,000 SPT minted exactly once (`init-supply`, chain 0, one-shot); no mint
   surface exists after initialization. The four reserve allocations are summed and enforced
   on-chain at mint.
2. **Key-less reserves.** Treasury, founder, liquidity, sale reserve, revenue, and the dividend
   pool are capability-guarded principals — movable only through the module's published
   functions, never by any private key.
3. **Pre-committed release calendar.** The three time-locks derive their schedule from source
   constants and the initialization timestamp. Release is permissionless, linear from the cliff,
   caps at the total, pays only the fixed beneficiary. No accelerate/delay/revoke/redirect
   function exists.
4. **One share, one live vote.** Vote weight = current chain-local balance; any debit (including
   cross-chain step 0) releases the moved shares' weight from the tally in the same transaction;
   credited shares arrive unvoted. No transfer/re-vote/chain-hop sequence double-counts.
5. **Tallies freeze at close.** After a proposal's close time (identical on every chain), nothing
   moves its tally — not transfers, not votes.
6. **Complete-gated results.** The aggregated outcome can only read as *passed* when all 20
   chains' frozen tallies are reported. Reports are permissionless but carry no caller-supplied
   numbers (module-read, duplicate-rejected, proof-carried across chains).
7. **Reserves don't participate.** Excluded reserves cannot vote and neither accrue nor dilute
   dividends (out of both the accrual and the denominator).
8. **Dividend solvency.** Funding a round is rejected unless the pool transfer covers the
   round's total accrual to circulating holders; claims pay only to an account bound to the
   holder's own guard (name-squatting cannot block or divert a claim).

## Threats designed against

Each of these is exercised by the [red-team suites](../tests/README.md) — the attack is run and
shown to fail:

| Threat | Defense |
|---|---|
| Vote double-counting (transfer, re-vote, cross-chain move) | Live-vote release on every debit; re-vote updates in place; votes never cross chains |
| Dust-transfer vote suppression | Receiving never touches the receiver's recorded vote |
| Tally/report injection | Tally writes gated behind internal capabilities acquired only inside vote/transfer/report paths; report payloads are module-read |
| Result cherry-picking (partial aggregates) | `passed` requires all 20 chains reported; a missing replica fails closed |
| Voting-key abuse (stealth registration, owner lockout, stale delegate after key compromise) | Registration needs the main guard with a scopable signature; the main guard always retains vote power; rotation auto-revokes the delegate; registration/revocation emit key-fingerprint events |
| Claim blocking via account squatting | Payouts go to a principal derived from the holder's own guard |
| Gas-station drain (spam, oversized txs, arbitrary continuations) | Envelope-bound single-call allowlist, gas limit ≤ 1,500 and price ≤ 10⁻⁶, per-epoch aggregate cap with time-only reset, fail-closed everywhere |
| Reserve extraction | No key controls a reserve; the only outbound paths are the published, event-emitting functions |

## Operator powers and limits

Without an upgrade, the operator **can**: create/close/cancel proposals; declare dividend rounds (immutable once declared) and fund them;
route revenue (publicly, with events); set the sale price; pause/resume the sale; top up the gas
station. The operator **cannot**: mint; move any reserve outside the release calendar; vote
reserves; alter a tally or declare an outcome; change a time-lock's schedule or beneficiary;
claw back distributed dividends; block a holder's transfer, vote, or claim.

**Upgrades** are the residual trust assumption: the modules are upgradeable under the admin
keyset (on testnet, a single hardware-wallet key) until the one-way `FROZEN-MODULE` switch is
flipped, which permanently disables upgrades. An upgrade cannot retroactively break rows already
written (state survives), but it can change future behavior — which is why the mainnet plan ends
with a source freeze and an immutable deployment. Every deployment and upgrade is public and
dated in [DEPLOYMENTS.md](DEPLOYMENTS.md).

## Known limitations (accepted, bounded)

- **Sponsored continuations:** a defpact continuation carries no code to allowlist, so the gas
  station bounds (rather than eliminates) continuation sponsorship via the per-epoch cap. Worst
  case: the day's subsidy budget is consumed; voting/claiming continue self-paid.
- **Cross-chain SPV paths** (transfer step 2, tally reports to the hub) cannot be tested in the
  REPL; they are validated on a multi-chain devnet before deployment.
- **Testnet admin is a single key.** Acceptable for a valueless test deployment; a mainnet
  deployment would harden governance before launch and freeze after proving.

## Review status — stated plainly

The contracts went through the project's internal structured security review before deployment:
fresh-context adversarial review passes over the full sources, a capability-by-capability audit,
and attack simulation. Findings were fixed before going live, and the regressions for them are
part of the public test suites in [`tests/`](../tests/).

**No external, third-party audit has been performed yet.** One is planned on the frozen source
before any mainnet deployment — that ordering (freeze first, then audit exactly what will run
forever) is deliberate. Until then, the strongest guarantees available are the ones you can check
yourself: the invariants above against the [verbatim deployed source](VERIFICATION.md), and the
red-team suites you can run offline.
