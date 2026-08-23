# Independent review — SPT / SPT-launch, 2026-08

**Reviewed:** `SPT` `cg8sInne-rg-JM2L1H2rcppXqBGE8NUIyBdB275RTP0` and
`SPT-launch` `RMn_SApRndMLn4b0MGIm-CE2zWRsU3m5t4e-EnHpyTY` — the exact hashes this repository
publishes. Read `audits/README.md` first: this is an **internal cold-context review, not a
third-party engagement**, and it is a **delta** over a longer preceding programme.

## Verdict

**GO-WITH-CONDITIONS. No CRITICAL. No HIGH in either module's logic.**

The single HIGH finding (A, below) was in the **deploy tooling**, not the contracts: no finding in
this review required a module byte to change, which is why the hashes above are the same ones the
review read. Twenty-one findings were raised. **All are now closed**, and each fix is named below.

## Redactions

This document is redacted for publication. Removed: internal issue and epic identifiers, internal
filesystem paths, references to documents not published here, and reproduction recipes. Findings
are renumbered **A–O**, local to this document.

**Six findings are withheld.** Five concern operator runbooks and internal records that this
repository does not publish, so their text would reference files you cannot open. One concerns a
gas-sponsorship module that is **not part of this artifact** and is not published here; withholding
it is a disclosure decision about unpublished code, not about SPT. Their subject matter is: an
internal checklist count, an internal index attribution, two stale internal tables, and two
enumeration gaps in operator documents. None touch the modules.

What is kept for every finding: **what was wrong, why it matters, why nothing caught it, and the
fix with its named test.** What is cut: the reproduction.

## Findings

| | severity | finding | closed by |
|---|---|---|---|
| **A** | 🔴 HIGH | **The deploy engine could not emit a whole-number launch price.** The price went through a float, and JavaScript renders `200.0` as `200`. Pact typechecks arguments before the body, so `init` with an integer aborts the transaction rather than reporting a bad input. No whole-number price could have opened the sale. Nothing caught it: the offline build test never built that transaction, and the devnet rehearsal happened to run at a fractional price — the one shape that hides it. | Price is now a validated decimal **string** passed through untouched. `npm run smoke` refuses a malformed one offline, and is mutation-tested. |
| **B** | MEDIUM | **The in-process namespace gate went blind to a seventh literal** because its pattern listed module names and the modules were renamed. It saw 6 of 7; a one-sided repatch would have read clean. | The anchor now names no module, so it cannot go blind on the next rename. A module contributing zero literals is a failure rather than being cleared by its sibling. |
| **C** | MEDIUM | **The hash-baseline gate's coupling check read one file, first match, comments included** — 1 of 7 namespace literals. It could not see a split repatch. | Now scans every artifact module, comment-stripped, and refuses anything but exactly one namespace. |
| **D** | MEDIUM | **Recorded deployment decisions were wired to nothing.** The recorded identity file was read by one CI step and nothing else, so a mistyped parameter was checked against the variable that set it — a tautology. | The engine now compares the environment to the recorded identity and refuses a disagreement. |
| **E** | MEDIUM | **A rename pass bypassed the tool built to protect records from renames**, whose skip-list already named, by name, both files that were corrupted. | A gate now checks the protected records themselves for the vocabulary they exist to preserve — it does not care what did the editing. It found a fifth corruption on its first run. |
| **F** | LOW | **A runbook and the engine contradicted each other about a verification step, in the same commit.** Failed safe (an extra human check). | Runbook corrected; the engine's check documented. |
| **G** | LOW | **Three orphaned pre-rename test fixtures survived**, carrying old module bodies. The runner enumerates fixtures by name, so it structurally could not see them. | Deleted. |
| **H** | LOW | **The artifact-identity file paired the current module names with hashes those modules never had** — a rename had rewritten a sentence recording what a past review examined. | Historical names restored; see also E. |
| **I** | LOW | **A previously fixed defect had no regression test** — reverting it reddened zero gates. | The offline build test now exercises the fixed path; mutation-tested. |
| **J** | LOW | **A budget gate has a narrow blind window, and the file claiming to catch a raise is not the file that does.** Concerns a module outside this artifact. | Recorded; the enforcing check is identified. |
| **K** | LOW | **Two negative-control pins lost their discriminator.** One module name is now a strict prefix of the other, and the assertion matcher is a substring test — so one module's error satisfied a pin meant for the other. Latent, not live. | The fixable pin now includes a terminating character. The other cannot be disambiguated by text; the hazard is recorded at the pin. |
| **L** | LOW | **A supply-check comment was false for one of the four tranches.** The check was right; the comment was not. | Comment corrected to state the real scope. |
| **M** | LOW | **Engine comments described a deploy-day mechanism as a rehearsal convenience.** | Corrected. |
| **N** | LOW | **A test comment credited the wrong assertion.** Measured across mutations: the assertion it named fired in none of them. | Comment corrected to name the assertion that actually fires. |
| **O** | LOW | **A signing-path fix had no regression test.** Unreachable on mainnet and fail-loud at the node. | Recorded, not fixed — the failure is immediate and visible. |

## 7. WHAT I COULD **NOT** VERIFY

1. **No node, no devnet, in this session — so nothing here is node evidence.** Every measurement
   above is REPL (5.4ce) or static.
2. **Deploy gas at these exact bytes is UNMEASURED.** `.github/scripts/deploy-budget.py` compares *bytes*
   (77,648 ≤ 77,721 measured) and then reports the **an earlier measurement** gas figures. The `as_of` field says
   so itself. This estate's own measurement says **bytes → gas is the wrong model, not an imprecise
   one** — `SPT-launch` once paid **+16.9 %** deploy gas with not one byte of its own source
   changed. Both modules *shrank*, so the direction is favourable and 71.2 % of the ceiling leaves
   room, but *"the artifact still fits 150k"* at these hashes is an **inference, not a reading**.
   Re-measure on the target node in the deploy session.
3. **Hard Rule 13** — `Chainweb32 ≥ 1` on the target chain. Out of scope by the prompt, and
   dischargeable only in the deploy session.
4. **The devnet rehearsal (20 chains, 42 txs, 122 PASS / 0 FAIL)** — I did not re-run it and cannot
   confirm it. I *can* say it ran at a **non-integral price** and so could not have caught finding A, and
   that `as_of`'s claim *"namespace repatched to `free`, which is the only difference"* is
   incomplete — the price and the network-id also differed.
5. **First funding permanently fixes `SPT-funding` and `SPT-launch-proceeds`**, and neither has ever
   been exercised on a node. Unchanged from an earlier internal review.
6. **13 of the 21 BUILT-UNPINNED promise rows** were not individually checked (8 were sampled and all
   but one had substantive named coverage elsewhere). `P-063` *"Unclaimed awards never expire"* has
   no named assertion anywhere; structurally it looks true, but that is unproven.
7. **Whether `check-namespace.sh` is *always* run before a real deploy.** It is in CI and CI is green
   on these bytes; it is **not** in `pact/test/run-tests.sh` and **not** in the operator checklist. A local repatch that is
   never pushed would not meet it. That gap is the load-bearing assumption under finding B and finding C.

---

## A note on the limitations above

They are published unsoftened and unedited except for redaction, because they are the most useful
part of this document. In particular: **the deploy-gas figure the review could not verify has
since been measured on a node**, with a same-session control, and is recorded in
`.github/scripts/deploy-budget.py`. The remaining limitations stand as written.
