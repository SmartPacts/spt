#!/usr/bin/env python3
"""Every promise on the founder page must carry a TRUE status, and a PROVEN one must be pinned.

🔴 THE CLASS THIS CLOSES
------------------------
The founder-facing page already has a coverage gate: every public function must be NAMED there.
That makes a missing function impossible and a false SENTENCE trivial — the gate reads names, not
meaning. Audit #14's a finding lived in exactly that gap: `VISION-SPEC` rated the vote-release
STRONG/PROVEN while quoting an expression the module had DELETED, and the rating was hand-written,
so nothing could contradict it. A CRITICAL sat behind a green rating for eleven audits.

Rule 14(c): a vision property is only real when a NAMED test goes RED if it is violated.
This gate is the mechanical half of that rule. It cannot judge whether a test is STRONG enough —
that needs mutation testing, which does not exist here and is declined deliberately (see LIMITS).
What it CAN do is make these six things impossible:

  1. A promise whose status is written by hand and drifts.       (status is DERIVED from here)
  2. A PROVEN promise whose pinning test does not exist.
  3. A PROVEN promise whose pinning test EXISTS BUT IS NEVER RUN. (all four manifests)
  4. A PROVEN promise whose named assertion is not in that test.
  5. A WEAK promise hidden by demoting it out of sight.           (TIER, below)
  6. A promise silently dropped from this manifest.               (EXPECTED_TOTAL + mark counts)

🔴 TIER — why a row may be tracked without being rendered (founder, 2026-08)
-------------------------------------------------------------------------------
145 promises in a 338-line page is not a page a product manager can read, and Rule 15 makes
readability the whole point of the founder tier. So each row declares a TIER:

  OWNER   — renders a status mark beside the sentence on the page. Every gate check applies.
  TRACKED — renders nothing. EVERY OTHER CHECK STILL APPLIES: the sentence must be on the page,
            the pin must exist, the pin must be named in a runner manifest so it actually runs,
            and the pin must contain its assertion.

🔴 **TRACKED IS LEGAL ONLY WHEN status == PROVEN.** That single rule is what stops TIER from
becoming a way to hide bad news. BUILT-UNPINNED, PROCEDURE and NOT-BUILT are *forced visible*,
so demoting a weak promise cannot make it quieter — it is rejected. PROCEDURE is forced hardest
because it is the one genuinely hand-written class: no pin exists for it by definition.
The consequence is a page whose length is a PROGRESS BAR — it shrinks as pins land.

TIER is a RECORDED PER-ROW JUDGEMENT, never derived from the text. Deriving it by keyword was
tested and rejected: matching CAN/CANNOT/ONLY/NEVER/ALWAYS marks 91 rows rather than ~45, and it
misses 3 of the 7 promises that were false at HEAD — including "20,000 available immediately",
which contains no guarantee word and was flatly wrong about the product.

DISCIPLINE (each has been paid for in this repo)
------------------------------------------------
* NAMED MANIFEST, never a count or a glob — a count cannot notice a renamed promise.
* The doc text is re-verified, so the manifest cannot outlive the sentence it cites.
* ZERO promises inspected is a FAILURE, never a pass.
* Fails closed on a missing file, an unreadable doc, or a promise naming an unknown status/tier.
* SELF-TESTS RUN BEFORE EVERY SCAN. A gate whose failure branch has never been observed is a
  gate that may not have one. `--self-test` proves the two branches the founder asked for:
  a demoted unpinned promise, and a silently dropped row.

🔴 MARKS — the status set is disjoint from the page's CALLER legend, and that is load-bearing
---------------------------------------------------------------------------------------------
The page marks WHO MAY CALL a function with 🟢 anyone · 🔵 the holder · 🔴 admin · ⚙️ contract.
NOT-BUILT used 🔴 until 2026-08, which collided with `admin only` on 14 table rows: the mark is
accepted anywhere in a ±220-character window, so a NOT-BUILT row sitting near any admin function
found an unrelated 🔴 and PASSED. A check that cannot fail is the defect Hard Rule 2 names, so
NOT-BUILT is ⛔ and no status mark may ever be drawn from the caller set.

🔴 LIMITS — printed on every run, because a gate that oversells itself is worse than none
-----------------------------------------------------------------------------------------
* It does NOT prove a test is strong enough to catch every violation. It proves the test exists,
  runs, and contains the named assertion. Strength is established once, by hand, by MUTATING the
  module and watching that assertion go RED — and recorded in the report that did it.
* It CANNOT demand a promise nobody wrote. Silent omission — the PCO failure, where hub-only
  voting was never a false sentence but an ABSENT one — is closed by the founder walkthrough and
  by the boundary column, not by this script. EXPECTED_TOTAL closes the narrower case of a
  promise dropped from a manifest that once held it; it says nothing about one never written.
* PROCEDURE promises are kept by a human following a process. No test can pin them and this gate
  does not pretend otherwise; it only checks the page says so plainly, and forces them visible.
* 🔴 **IT VERIFIES THE ANCHOR IS ON THE PAGE — NEVER THAT THE PROMISE STILL REFLECTS IT.** A promise
  whose sentence was REWRITTEN survives here silently: the manifest keeps the old wording, the
  anchor still resolves to some sentence, and every other check passes. Measured 2026-08 — four
  rows carried text the page had already corrected, including one asserting the public could buy
  "as soon as the contract is set up" while PROVEN-pinned to `"inactive until resumed"`, a test
  proving the OPPOSITE. A deliberate re-derivation of eight such rows had missed all four, because
  it re-derived their STATUS against the new page and never re-read their TEXT.
  **Check 4 at a real floor is the only mechanical detector of this class** — a rewritten sentence
  drags the promise and the anchor apart, and nothing else notices. That is why the floor is a
  floor: at 0.20 not one row could fail, and the class was invisible.
* 🔴 **CHECK 4'S CEILING: it catches GROSS mismatches, never PLAUSIBLE-BUT-WRONG assignments.**
  It found an anchor sitting inside the caller legend and a "SPT *can* be moved between chains"
  promise on the "**What SPT cannot do**" label. It does NOT find a promise parked on a sentence
  from the same subject area, because the metric — shared tokens over the ANCHOR's tokens —
  rewards a short, generic anchor: a founder-vesting promise scored 50% on "Sell tokens for KDA at
  a fixed price" via {fixed, token}, and a 10,000-KDA-cap promise scored 67% on "Pay awards in
  KDA" via {award, kda}. Both render a ✅ on a sentence making a different claim, which is the
  precise thing this gate exists to prevent, and both pass.
  Raising the floor, Jaccard, IDF-weighting and top-3-distinctive were each measured and NONE
  separates these from legitimate anchors. **So the remedy is not a better score — it is not
  leaving the choice to a score.** The generator assigns by STABLE MATCHING rather than greedily
  maximising a noisy number, and the "In one minute" bullets — the page's own promise list — are
  HAND-ASSIGNED 1:1 and never scored at all. Check 4 is the backstop for gross errors; correct
  ASSIGNMENT is what makes an anchor right, and no threshold here can be read as proving one.

EXIT: 0 all promises consistent · 1 a promise is false/unpinned/unrun/hidden · 2 tooling failure.
"""
import os
import re
import sys

# Paths resolve from the REPO ROOT, derived from this file's own location — the suite's other
# gates are invoked from pact/test, so a cwd-relative path here would fail for the wrong reason.
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOC = os.path.join(ROOT, 'docs/SPT-WHAT-IT-DOES.md')
SUITE_RUNNER = os.path.join(ROOT, 'pact/test/run-tests.sh')
TEST_DIR = os.path.join(ROOT, 'pact/test')
DEVNET_DIR = os.path.join(ROOT, 'test/harness/src')

# 🔴 DEVNET-TIER PINS. A few properties cannot be pinned by a .repl at all, and pretending
# otherwise is how a promise ends up ✅ against a test that asserts nothing. The clearest case is
# a CROSS-CHAIN ARRIVAL: `resume` needs an SPV proof that a node produced from a mined block on
# the source chain, and the REPL has one database and no SPV — a REPL version would either fail
# to compile or silently assert only the departure.
#
# Such a promise may be pinned to a NAMED DEVNET DRIVER instead. It gets the same two checks a
# .repl pin gets — the file must exist, and it must contain the named assertion — but it cannot be
# in a REPL runner manifest, so the registry below replaces that check: only a driver listed here
# may pin, so a stray .ts cannot. These do NOT run in `run-tests.sh`; they run against a node.
DEVNET_DRIVERS = {
    'spt-xchain-devnet.ts',
}

# The legend on the page necessarily contains every mark. Counting marks would double-count it,
# so it is delimited and excluded — explicitly, rather than by a magic offset nobody can audit.
LEGEND_OPEN = '<!-- promise-gate:legend -->'
LEGEND_CLOSE = '<!-- /promise-gate:legend -->'

# 🔴 THE CALLER LEGEND IS TWO LINES, AND THAT COST A ROUND. It explains 🟢/🔵/🔴/⚙️ — who may CALL
# a function — and makes no promise, so a status mark inside it is a status nobody derived. The
# first fix excluded it by matching the line containing "🟢 anyone"; the legend's SECOND line
# ("⚙️ the contract itself only …") was still eligible and a 🟡 landed there immediately. Matching
# CONTENT excludes what you remembered to name. Delimiting a REGION excludes what you did not.
CALLER_OPEN = '<!-- promise-gate:caller-legend -->'
CALLER_CLOSE = '<!-- /promise-gate:caller-legend -->'

# 🔴 PROPOSAL REGIONS — "approved, not yet built" sections. a later change.
#
# THE MARKER EXISTED AND NOTHING READ IT. A `<!-- promise-gate:proposal -->` region wrapped an
# 80-line the design record section reading "🔴 It is not built yet … the 150% shortfall is still what the
# code does" — while the design record was BUILT AND MERGED, and the page's own BODY described it correctly
# with derived ✅ marks. So the founder-facing page gave TWO answers about how award money is
# funded, and the stale one sat at the end where a reader stops.
#
# It was invisible on purpose and by accident at once. The section says: "No status marks appear
# here, deliberately — a mark means a test guards it, and there is nothing to guard until this is
# built." True when written. But that also exempts it from the ONLY mechanism that could notice it
# going false, and the marker meant to delimit it was consumed by no code at all.
#
# 🔴 SO A PROPOSAL REGION IS NOW A DECLARED, SHRINK-ONLY THING, like every other quarantine in
# this repo. An undeclared region FAILS. That does not prove the proposal has not shipped — no
# check can — but it forces the section to be NAMED by someone who had to write down why it is
# still unbuilt, which is the step that did not happen here.
PROPOSAL_OPEN = '<!-- promise-gate:proposal -->'
PROPOSAL_CLOSE = '<!-- /promise-gate:proposal -->'
PROPOSAL_REGIONS = {}   # title-substring -> why it is still unbuilt. EMPTY is the correct state.

# Who-may-call marks. A status mark may never touch one: side by side they read as a single
# compound symbol, and the reader cannot tell which vocabulary either belongs to.
CALLER_MARKS = '🟢🔵🔴⚙️'

# 🔴 CHECK 4's threshold. An anchor must token vocabulary with the promise it carries. This is the
# ONLY check that catches an anchor pointing at the wrong sentence — placement checks all passed
# while P-034 sat in the caller legend and P-038 (a CAN promise) sat on the "What SPT cannot do"
# LABEL. Both are well-formed sentence starts; both were about something else entirely.
# 🔴 THE FLOOR IS A REAL FLOOR. At 0.20 ZERO rows could fail — a check that cannot fail is the
# defect Hard Rule 2 names, and it was measured here: median correspondence is 75%, so 20% sat far
# below the entire distribution and asserted nothing. 0.40 surfaces the rows worth reading.
# NEVER RAISE THIS TO ABSORB A ROW. A row below the floor is a wrong anchor, a promise whose
# sentence was rewritten, or a paraphrase needing a closer anchor. If it is genuinely none of
# those, add a NAMED EXEMPTION with a reason — one row, visible, argued — never a wider floor,
# which silently re-exempts every future row too.
MIN_ANCHOR_MATCH = 0.40
# NAMED EXEMPTIONS from check 4 — id -> the reason, which is the whole point. A row lands here
# only when its promise is genuinely stated on the page in words that token little vocabulary with
# it, and no closer anchor exists. Each is an argument someone can read and overturn; a wider floor
# would be the same concession made silently, forever, to every future row as well.
# An exemption for a row that PASSES is itself an error — stale exemptions rot into blanket ones.
ANCHOR_EXEMPT = {
    # Each of these is a RECORDED assignment — a human read the page and chose the sentence — that
    # check 4 scores below the floor because the page states the promise in different words. That
    # is the documented ceiling of the metric, not a defect in the anchor, and the fix for it is
    # one argued row here rather than a lower floor for everything.
    'P-022': "the page carries this inside the CLOCK sentence — 'The clock starts the moment the "
             "contract is set up, and the schedule cannot be changed afterwards' — so it tokens "
             "only {schedule, changed} with a promise phrased 'after setup'. No other sentence "
             "states the schedule's immutability at all.",
    'P-118': "the page describes award-liability as 'What this chain owes its holders in KDA right "
             "now'; the promise states the EQUALITY property (the reported number equals the sum "
             "every holder can actually claim). Same referent, and the property is the part no "
             "sentence on the page words the same way.",
}

_STOP = set("the a an and or of to in on is are be it its that this for with as at by from can "
            "cannot not no any all one each every their they you your we our must may do does "
            "which what when who how so if then than but also only just still yet".split())


# 🔴 IRREGULAR PASTS THE SUFFIX RULES CANNOT REACH. Measured: "SPT can be HELD and MOVED on any
# of Kadena's 20 chains" scored 0% against the bullet that restates it ("HOLD and MOVE tokens, on
# any of the 20 chains") because held/hold and moved/move never unified — so the VOTING promise
# won that bullet on {hold, token} and the page told the founder a proven vote-weight test backed
# a sentence about moving tokens. A stemmer that splits a word from its own past tense does not
# measure meaning, it measures spelling.
_IRREGULAR = {
    'held': 'hold', 'sent': 'send', 'paid': 'pay', 'made': 'make', 'sold': 'sell',
    'told': 'tell', 'kept': 'keep', 'left': 'leave', 'lost': 'lose', 'meant': 'mean',
    'spent': 'spend', 'built': 'build', 'ran': 'run', 'went': 'go', 'gone': 'go',
    'took': 'take', 'taken': 'take', 'gave': 'give', 'given': 'give', 'wrote': 'write',
    'written': 'write', 'chose': 'choose', 'chosen': 'choose', 'froze': 'freeze',
    'frozen': 'freeze', 'shown': 'show', 'known': 'know', 'knew': 'know', 'began': 'begin',
    'begun': 'begin', 'became': 'become', 'bought': 'buy', 'brought': 'bring',
    'caught': 'catch', 'found': 'find', 'got': 'get', 'read': 'read', 'set': 'set',
    'put': 'put', 'cut': 'cut', 'cost': 'cost', 'let': 'let', 'lay': 'lie',
}


def _stem(w):
    """Crude but symmetric: a word and its inflections must land on the same string."""
    w = _IRREGULAR.get(w, w)
    for suf in ('ings', 'ing', 'ed', 'es', 's'):
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            w = w[:-len(suf)]
            break
    if len(w) > 3 and w.endswith('e'):
        w = w[:-1]                      # move/moved -> mov, freeze/frozen -> freez
    if len(w) > 4 and w[-1] == w[-2]:
        w = w[:-1]                      # stopped -> stopp -> stop
    return w


def _tokens(text):
    """Content words, stemmed so inflections unify.

    🔴 Without this the check FALSE-POSITIVES, which is fatal for it: "founder amounts must sum to
    10,000" scored 0% against "The founders — each a plain address with its own amount", which
    states exactly that promise. A correspondence check that cries wolf gets tuned to nothing.
    """
    out = set()
    for w in re.findall(r"[a-z0-9]+", text.lower()):
        if w in _STOP or len(w) < 3:
            continue
        out.add(_stem(w))
    return out


# Status vocabulary shown to the founder. The MARK is what appears on the page.
# 🔴 IS DELIBERATELY ABSENT — see MARKS above. Never reuse a caller-legend mark here.
STATUS = {
    'PROVEN':         ('✅', 'a named test breaks if this stops being true'),
    'BUILT-UNPINNED': ('🟡', 'built and believed true — but no test would catch it breaking'),
    'PROCEDURE':      ('📋', 'kept by a person following a process, not by the contract'),
    'NOT-BUILT':      ('⛔', 'not built'),
}

# The four status glyphs, as one string — used for the adjacency and placement scans.
_SM = ''.join(v[0] for v in STATUS.values())

TIERS = ('OWNER', 'TRACKED')

# 🔴 The rule that makes TIER safe. Only a PROVEN row may be hidden from the page.
TRACKABLE = {'PROVEN'}

# The mapping pass (workflow `promise-test-mapping`, 6 agents + adversarial verify, 2026-08)
# found 145 founder-falsifiable promises on this page; 9 were duplicates returned by more than
# one section agent and are merged in the manifest below, by name. Anchoring to the EXTERNAL number
# rather than to len(PROMISES) is the point: a manifest compared against itself always agrees,
# and a TRACKED row can be dropped without any mark going missing to betray it.
EXPECTED_TOTAL = 153   # 154 -> 153: P-160b RETIRED (a later change). It described three money-movers the
                       # contract did NOT enforce; the founder made them @managed, so the absence it
                       # named is gone and the row goes with it. P-160 now covers all four.

# 🔴 a later change / the design record REMOVED TWO ROWS: P-065 ("an award round can never promise more than
# 0.5 KDA per token") and P-072 ("a round's effective date can be at most 1 year in the future").
# Both named page promises that are DELETED from SPT-WHAT-IT-DOES.md in the same commit, because
# the constants behind them are gone — a later amendment attempted the harm the rate cap named
# and it did not reproduce (`pact/test/zz-probe-maxrate.repl`). A manifest row whose promise the
# page no longer makes, or whose pin names a refusal that can no longer happen, is a check that
# cannot fail. P-066 ("one round can never commit more than 10,000 KDA") went with them.
# 🔴 AND ONE ROW WAS ADDED, P-143: the promise that REPLACED the caps — a mistyped rate is
# refused because the money is not there — pinned by the refusal that actually fires. Deleting
# a guarantee from the founder page without stating what stands in its place is how a page
# quietly gets weaker. EXPECTED_TOTAL 138 -> 136 (three removed, one added).
# --- THE MANIFEST -------------------------------------------------------------------
# (id, doc-phrase that must appear VERBATIM on the page, status, tier, pin file, assertion)
#
# `pin` is a BARE FILENAME inside pact/test — no directory, no ":12-34" line range. The mapping
# pass recorded both, and both silently break os.path.join; the gate rejects them by shape so the
# old format cannot come back.
# `pin` and `assertion` are required for PROVEN and must be empty for every other status.
# A promise is added here when it is a statement the FOUNDER could judge true or false.
PROMISES = [
    # 🔴 145 -> 132. The mapping's six section agents worked OVERLAPPING ranges and returned the
    # same promise more than once; 13 rows are duplicates, merged here and named so the delta from
    # EXPECTED_TOTAL is auditable rather than quiet. Two carried CONFLICTING statuses from
    # different agents and the WEAKER was kept, because a promise is only as strong as its
    # weakest honest reading:
    #   "No SPT can ever be burned"            -> folded into the 100,000-supply row (the corrected
    #                                             page states mint-and-burn in ONE sentence)
    #   "The one real way to lose tokens"      -> folded into the cross-chain stranding row
    #   "There is no undo" (x2, identical)     -> BUILT-UNPINNED vs NOT-BUILT; kept NOT-BUILT
    #   "The contract never decides a vote"    -> PROCEDURE vs BUILT-UNPINNED; kept PROCEDURE
    #   "Withdrawing company funding/money"    -> identical promise, identical status
    #   "Nobody can redirect a founder's lock" -> folded into the founder-address row
    #   "SPT is sold at a price that cannot change while open" -> folded into the price row
    #   "A disbursement can never go to a protocol account"    -> folded into the superset row
#   "Awards accumulate ... selling does not forfeit them"  -> folded into the never-expire row
    #
    # 🔴 STATUS RE-DERIVED for 8 rows the mapping rated against the PRE-CORRECTION page. The
    # mapping finished 15:39; commit d7740cc rewrote those sentences at 15:40. A status computed
    # against text that no longer exists is exactly the drift this gate exists to stop, so each
    # was re-read against the CURRENT sentence — including the two supply "cannot"s, which are
    # BUILT-UNPINNED because the page now states them as conditional on the platform fork and no
    # suite can assert a post-fork property on a pre-fork engine.
    #
    # TIER follows the founder's rule (2026-08): function-table rows are TRACKED and keep only
    # their caller legend; guarantee prose and the red callouts are OWNER. Weak statuses are
    # forced OWNER by the gate itself, so this choice only ever applies to PROVEN rows.
    #
    # 🔴 EIGHT ROWS WERE PINNED ON ENGINE STRINGS, AND THAT WAS NOT MERELY WEAK — IT BOUND THE
    # WRONG TESTS. "Keyset failure" is emitted by the engine, not this module: it appears in many
    # files, so the resolver matched the FIRST occurrence and P-027 ("value exits are admin-only")
    # ended up pinned to a resume-sale test, P-056 ("only the admin can announce a proposal") to a
    # funding test. A non-unique assertion does not just risk a vacuous pin; it silently binds an
    # unrelated one, and the gate cannot tell the difference because the string IS present.
    #
    # There is NO SPT-prefixed message for admin authority — the modules gate admin with
    # `enforce-keyset ADMIN-KS` (token :665/:667), whose failure text belongs to the engine. So the
    # choice per row was: re-pin on something unique to the TEST, or downgrade.
    #   P-085 / P-098 (the 70,000-token admin discretion) and P-131 keep PROVEN, re-pinned on their
    #     expect-failure LABEL, which is unique to the file and names the right behaviour. The
    #     labels' own expected text is still the engine string, so the TEST is no stronger than it
    #     was — what changed is that the gate now goes red if that test is deleted or renamed,
    #     instead of staying green on any other keyset failure anywhere in the tree.
    #   P-027, P-034, P-039, P-056, P-100 are DOWNGRADED to BUILT-UNPINNED: their pins named tests
    #     that do not test them, so there was never a pin to keep.
    #
    # 🔴 OWNER ROWS ANCHOR TO A DISTINCT PROSE SENTENCE, never a table cell. P-034 previously
    # anchored to the CALLER LEGEND ("signature · 🔴 admin only ·") and drew a ✅ inside it; the
    # legend is not a promise, and a mark there is a status nobody derived. Marks now land at the
    # START of the sentence they qualify, one per sentence, so a mark can never sit mid-clause or
    # pair up with another. TRACKED rows still anchor anywhere, including table rows, because they
    # render nothing.
    # (id, the PROMISE, doc-phrase VERBATIM on the page, status, tier, pin, assertion)
    # 🔴 PINNED AT THE DEVNET TIER, because the arrival leg has no REPL expression: `resume` needs
    # an SPV proof from a mined block on the source chain, and the REPL has one database and no SPV.
    # The driver mines BOTH legs against a node and reads BOTH ledgers. Measured 0 -> 1: holder
    # 10 -> 6 on the source, 0 -> 4 on the target, circulating -4/+4 netting to zero, and the two
    # balances summing to what they summed to before. Deployment to all 20 chains is proven
    # separately by the full deploy rehearsal.
    ('P-001', "SPT can be held and moved on any of the 20 chains, and moved between them.",              'Hold and move tokens, on any of the 20 chains',                                                 'PROVEN',   'OWNER',   'spt-xchain-devnet.ts',        'TARGET ledger credited exactly'),
    ('P-003', 'Holders vote yes or no on a proposal, and a vote counts for exactly the number of tokens the holder holds.', 'Let holders vote yes/no on proposals',                                                          'PROVEN',         'OWNER',   'smartpacts-governance.repl',  'yes 2500'),
    ('P-004', 'Awards are paid in KDA, build up across rounds until claimed, and anyone can trigger a claim.', 'Pay awards in KDA, which accumulate until claimed',                                             'PROVEN',         'OWNER',   'smartpacts-award-fairness.repl', 'dave now earns R3+R4 = 1000*(0.01+0.03) = 40'),
    ('P-099', 'A buyer pays KDA and receives tokens at the price the sale is currently set to.',           'Sell tokens for KDA at a fixed price.',                                                         'PROVEN',         'OWNER',   'SPT-launch.repl',      'buyer got 1000 SPT'),
    ('P-005', 'Founder, treasury and liquidity tokens unlock only on the schedule fixed at setup, and nobody — including the admin — can release them early.', 'Unlock the founder, treasury and liquidity tokens slowly',                                      'PROVEN',         'OWNER',   'smartpacts-tranches.repl',    'SPT disbursement exceeds the vested available amount'),
    ('P-006', 'The company can receive KDA into the contract and withdraw it, and only the admin can withdraw.', 'Let the company receive and withdraw its own KDA.',                                             'PROVEN',         'OWNER',   'SPT.repl',       'funding drained after withdrawal'),
    ('P-007', 'No more than 100,000 SPT can ever exist.',                                                  '**Mint more than 100,000 tokens**, or burn any',                                                'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-008', 'The contract never decides a vote — each chain counts only its own, and the winner is added up outside the contract from all 20 vote-record reads.', '**Decide a vote.**',                                                                            'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-009', 'The company is never obliged to declare an award.',                                         '**Force an award.**',                                                                           'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-010', 'Until the contract is frozen the admin can still change the rules — and it is not frozen today.', '**Stop the admin from changing the rules — until the contract is frozen.**',                    'PROVEN',         'OWNER',   'smartpacts-upgrade-emergency.repl', '../modules/SPT.pact'),
    ('P-137', 'A record date is announced with no rate attached, and the count it takes is then frozen.', '**A record date is announced with no rate attached, and the count it takes is then frozen.**', 'PROVEN', 'OWNER', 'smartpacts-record-date.repl', 'the sealed float is the float at the instant'),
    ('P-138', 'A round pays out exactly the rate times the frozen count.',                                 '**A round pays out exactly the rate times that frozen count**',                                 'PROVEN', 'OWNER', 'smartpacts-record-date.repl', 'TOTAL PAID == rate x SEALED FLOAT, exactly'),
    ('P-139', 'Anyone can take the count once the record date has passed.',                                '**Anyone can take the count once the date has passed**',                                        'PROVEN', 'OWNER', 'smartpacts-record-date.repl', 'advance-snapshot seals'),
    ('P-140', 'Someone who buys after the record date is not in that round.',                              '**Someone who buys after the date is simply not in that round.**',                              'PROVEN', 'OWNER', 'smartpacts-record-date.repl', 'carol bought inside the window and is owed nothing'),
    ('P-141', 'A wrong record date is fixable: it can be cancelled until six hours before it lands.',                 '**A wrong date is fixable.**',                                                                  'PROVEN', 'OWNER', 'smartpacts-record-date.repl', 'record date cancelled'),
    ('P-142', 'A repeated announcement against the same record date is refused, not doubled.',             '**A repeated announcement against the same date is refused, not silently doubled.**',           'PROVEN', 'OWNER', 'smartpacts-record-date.repl', 'a second round on the same record date is REFUSED, not doubled'),
    ('P-143', 'A mistyped award rate is refused outright, because the money for it is not there.', '**A mistyped rate is refused outright, because the money for it is not there.**', 'PROVEN', 'OWNER', 'smartpacts-award-safety.repl', 'one admin tx can no longer destroy the award subsystem — refused on the MONEY'),
    ('P-144', 'An award round must take effect at least 12 hours after it is announced.', '**The effective date must be at least 12 hours away.**', 'PROVEN', 'OWNER', 'smartpacts-promises.repl', 'page: the 12h effective-at floor is twice the retract lead'),
    # ---- the design record, the two admin keyset tiers (a later change) --------------------------------------
    # Every one of these is pinned to smartpacts-admin-tiers.repl, which is the ONLY suite that
    # can see a tier downgrade: signing with more keys always satisfies a weaker predicate, so
    # the other 61 suites stay green when an operation moves from gov to ops.
    ('P-145', 'Anything that moves money out of the contract, or that cannot be undone, needs two of the three signing devices.', '**Two of the three devices** must both sign the same transaction.', 'PROVEN', 'OWNER', 'smartpacts-admin-tiers.repl', 'GOV REFUSES one device'),
    # 🔴 a later change RE-ANCHORED. The old anchor was 'ONE device is enough for ADMIN-OPS' on set-price
    # — an operation that is no longer one-device, and whose assertion is now a COMMENT explaining
    # the inversion. The gate refused a comment-only anchor, exactly as a later change intended. The
    # PROMISE is unchanged and is now MORE accurate than when it was written: what stays at one
    # device is precisely the set that can be undone. Anchored to `cancel-snapshot`, where a single
    # device clears a stall the same single device can create.
    ('P-146', 'Everyday operations that can be undone need only one of the three devices.', '**Any one** of the three devices is enough.', 'PROVEN', 'OWNER', 'smartpacts-admin-tiers.repl', 'the SAME one-device tier clears the stall it can create'),
    # 🔴 CORRECTED 2026-08. This row read "cannot take money out" and that was FALSE, measured:
    # one ops device, one transaction — pause, cut the price to the floor, resume, buy — took the
    # entire 20,000-SPT sale reserve for 200 KDA (worth 10,000 at a 0.5 price). Reproduced
    # independently before the page was touched.
    # 🔴 AND THE PIN PROVED LESS THAN THE PROMISE CLAIMED, which is why nothing caught it: the
    # anchor was 'GOV REFUSES one device on withdraw-funding', which tests KDA leaving the funding
    # account and says NOTHING about the sale reserve. A promise about all money, certified by an
    # assertion about one account. Fourth instance of this class (P-160, P-076, D-2, now P-147).
    # The promise is narrowed to what the gov tier actually refuses, and re-anchored to the
    # LARGEST of those refusals — disburse-tranche, which guards 70,000 SPT.
    # The sale-reserve residual is NOT covered by this row: it is G-1/G-2 in the same suite, and
    # the page states it in full rather than promising it away.
    ('P-147', 'A single lost or stolen device can cause delay and cannot publish new code, and cannot move company tokens, take KDA out of the funding account, or touch the award pot.', '**A lost or stolen device cannot publish new code**, and cannot move company tokens, take KDA', 'PROVEN', 'OWNER', 'smartpacts-admin-tiers.repl', 'A-5 GOV REFUSES one device on disburse-tranche'),
    ('P-148', 'Whichever device can create a delay can also clear it, alone.', '**Whichever device can create one of those delays can also clear it, alone.**', 'PROVEN', 'OWNER', 'smartpacts-admin-tiers.repl', 'the SAME one-device tier clears the stall it can create'),
    # 🔴 RE-ANCHORED 2026-08. The claim is that the OPERATION-TO-TIER MAPPING is fixed at
    # freeze, and the mechanism for that is simply that the mapping lives in code and frozen
    # code cannot change — so the honest pin is the upgrade REFUSAL, not a string sitting in a
    # comment in the frozen-invariant suite (which proves operations still WORK when frozen, a
    # different property). Same fixture as P-127 because it is the same mechanism.
    # 🔴 BOUNDARY, stated because a reader will assume more: this fixes WHICH OPERATIONS need
    # two devices. It does NOT fix WHICH DEVICES are in each tier — `define-keyset` is a
    # standalone transaction, not module-gated, so keyset rotation survives the freeze.
    ('P-149', 'Which operations need two devices and which need one is fixed forever once the contract is locked.', '**Which operations need two devices and which need one is fixed forever once the contract is', 'PROVEN', 'OWNER', 'frozen-upgrade-token.repl-must-fail', 'Module is frozen'),
    ('P-150', 'Using the backup device last is a habit, not something the contract enforces.', '**Using the backup device last is a habit, not something the contract enforces.**', 'PROCEDURE', 'OWNER', '', ''),
    # ---- the design record part 2, the two settable limits (a later change) ----------------------------------
    ('P-151', 'You can make the notice period longer, and you can never make it shorter than 12 hours.', '**The notice period can be made LONGER, and can never be made shorter than 12 hours.**', 'PROVEN', 'OWNER', 'smartpacts-admin-tiers.repl', 'even TWO devices cannot lower the runway past MIN-RUNWAY'),
    # 🔴 a later change REWRITTEN — A PRODUCT CHANGE, NOT A WORDING FIX. The promise read "Using a limit
    # takes one device; moving a limit takes two." That framing described the tiers exactly until
    # 2026-08, when `set-price` — the archetypal "use a limit" operation — moved to two devices
    # after a review chained it into taking the whole sale reserve. The operate-vs-move pair no
    # longer describes the split, and asserting a pair that no longer exists would be worse than
    # asserting none (the same call recorded at a finding in the tier suite). The line that DOES describe
    # it now is whether the action can be taken back. Anchor unchanged: `set-min-price` is still a
    # one-device refusal and still the sharpest single case.
    ('P-152', 'Anything that moves money out of the company\'s control, or creates a promise the contract must honour, takes two devices — even when it is routine work.', '**Anything that moves money out of the company\'s control, or creates a promise the contract must', 'PROVEN', 'OWNER', 'smartpacts-admin-tiers.repl', 'GOV REFUSES one device on set-min-price'),
    # 🔴 The value moved 1e-6 -> 1e-5 on the founder's call (2026-08, a later amendment). The ANCHOR
    # moved with it deliberately: a manifest row that kept the old number would have gone on
    # matching nothing while the page said something else, and this gate's whole job is that the
    # page and the pin agree. The pin is now C-4b, which refuses 1e-6 BY NAME — the previous
    # floor — because a finding's other probes (1e-7, 1e-12) sit below both values and cannot tell them
    # apart, and its control reads the constant symbolically and adapts silently.
    ('P-153', 'The price floor can never be set below 0.00001 KDA per token, by any key, before or after the freeze.', 'Never below 0.00001 KDA per token', 'PROVEN', 'TRACKED', 'smartpacts-admin-tiers.repl', 'the OLD 1e-6 floor is now REFUSED'),
    ('P-154', 'Both settable limits still move after the contract is frozen, so a limit adjustable today stays adjustable forever.', 'Both settable limits still move after the contract is frozen', 'PROVEN', 'TRACKED', 'smartpacts-frozen-invariant.repl', 'set-runway works frozen'),
    # ---- an internal review a finding (a later change): a tier is not a disbursement scope -------------------
    ('P-158', 'Moving locked company tokens names its own tranche, amount and destination, so a signature for anything else cannot move them.', '**Every operation that moves money out now names its own amount and destination.**', 'PROVEN', 'OWNER', 'smartpacts-admin-tiers.repl', 'an (ADMIN-GOV) clist is REFUSED on disburse-tranche'),
    # ---- an internal review a finding's RESIDUAL (a later change): the other three value-movers -------------
    # 🔴 THE PIN IS THE *REFUSAL*, NOT THE ACCEPTANCE. §E's brick checks (E-2/E-5/E-8) prove the
    # scoped signature still works, but a page claiming a signature "cannot be used for another"
    # is only falsified by an (ADMIN-GOV) clist being turned away. Named separately from P-158
    # because the two closed in different change sets and a single row would let either half
    # regress under the other's evidence.
    # 🔴 RE-ANCHORED (a later change). This row was PROVEN against 'E-1 an (ADMIN-GOV) clist is REFUSED
    # on withdraw-funding' — a DIFFERENT function, and an assertion with nothing to do with the
    # AMOUNT clause this promise makes. Measured: strip `@managed` from DISBURSE, and this gate
    # exited 0 with the promise still certified PROVEN while the property was broken. The suite
    # did catch it (12 failures from the §F pins); the MANIFEST did not, which is the half that
    # renders the ✅ on the founder page.
    # That is an internal review's a finding class — a status derived from a pin that cannot fail — reproduced
    # in the row created for the very change that was meant to make this promise true, one
    # session after the identical defect was repaired for P-076. The anchor now names the §F
    # assertion that reproduces an internal review's 150-call abuse, so removing @managed reddens the
    # gate and the page mark disappears with the property.
    # 🔴 CAUGHT A THIRD TIME, 2026-08, BY THE FIRST EXTERNAL AUDIT — and the two notes above are
    # the record of the first two. The row was PROVEN and the PROMISE ITSELF WAS FALSE: it claimed
    # the property for FOUR money-movers while its anchor (§F a finding) exercises only DISBURSE, the one
    # of the four that is @managed. The other three enforce GOV-KS directly and are NOT managed, so
    # an UNSCOPED gov signature drives any of them for any amount to any destination — MEASURED ON
    # A NODE, MINED, both clists empty on the wire, tx Kw8h9FdI4ESaYB4fwMum6o1Wfn602CvDdvsgpFpjvQI.
    # No re-anchoring could have fixed this: every candidate pin in §E asserts a REFUSAL of a
    # WRONGLY-scoped signature, and not one of them asks what an UNSCOPED signature does. The pin
    # was not weak — the SENTENCE covered more than the code did.
    # Split rather than re-anchored: P-160 keeps the enforced half (DISBURSE), P-160b states the
    # unenforced half honestly. A single row would let the true half certify the false one, which
    # is exactly how this survived three rounds.
    # 🔴 P-160b RETIRED (a later change, founder 2026-08) — A PRODUCT CHANGE, NOT A TIDY-UP. It existed
    # for a few hours to state honestly that three of the four money-movers were NOT enforced by the
    # contract. The founder chose to fix the contract instead of the wording, so WITHDRAW-FUNDING,
    # RECOVER-SURPLUS and WITHDRAW-PROCEEDS are now @managed like DISBURSE and the property it
    # described no longer exists. That is why it is deleted rather than downgraded: a promise about
    # an absence must not outlive the absence.
    # P-160 now covers ALL FOUR, and its anchor moved to the sentence that says so. The pin is still
    # the DISBURSE reproduction, which is honest about what it proves — §F a finding reddens if @managed is
    # stripped from DISBURSE. The three new managers get their own pins in the tiers suite.
    ('P-160', 'For every operation that moves money out, the contract itself refuses a signature that does not name the operation, its destination and its amount — so a signature for one cannot be used for another, a different amount, or a different destination, and an unscoped signature cannot drive any of them.', '**Every operation that moves money out now refuses a signature that does not name the\noperation, its destination and its amount.**', 'PROVEN', 'OWNER', 'smartpacts-admin-tiers.repl', 'a finding the 150-call loop under ONE 100.0 clist entry is REFUSED'),
    # ---- an internal review a finding (a later change): closed by DISCLOSURE, a later amendment ------------------
    ('P-159', 'A proposal can only be withdrawn before its voting opens, never once it has started.', '**A proposal can only be withdrawn before its voting opens — never once it has started**', 'PROVEN', 'OWNER', 'smartpacts-proposal-lifecycle.repl', 'cancel at the instant voting opens is refused'),
    ('P-126', 'The contract is not frozen yet.',                                                           '**It is not frozen yet.**',                                                                     'PROVEN',         'OWNER',   'smartpacts-upgrade-emergency.repl', '../modules/SPT.pact'),
    ('P-011', 'A transfer sent to the wrong address cannot be reversed.',                                  '**Recover a lost key**, or reverse a transfer sent to the wrong address.',                      'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-012', 'The contract cannot prove who owns what beyond a single account, because one person can hold several accounts.', '**Prove who owns what beyond one account.**',                                                   'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-109', 'All 100,000 tokens are issued once, at setup on chain 0, to the four reserves — and never again.', '100,000 tokens, fixed',                                                                         'PROVEN',         'OWNER',   'SPT-init.repl',  'treasury 55k'),
    ('P-014', 'The 20,000 public tokens carry no unlock schedule — they are not time-locked like the other three buckets.', 'For sale to the public',                                                                        'PROVEN',         'TRACKED', 'smartpacts-founder-allocations.repl',     '"five TRANCHE-LOCKED events: one per founder row + the two fixed rows"'),
    ('P-015', 'The sale ships closed and only the admin can open it, so nobody can buy until they do.',    'No unlock schedule — but **the sale ships',                                                     'PROVEN',         'TRACKED', 'SPT-launch.repl',      '"inactive until resumed" false'),
    ('P-073', 'A declared round pays nobody until its effective date arrives.',                            'Nobody can buy until',                                                                          'PROVEN',         'TRACKED', 'smartpacts-award-fairness.repl', 'rpt UNCHANGED at 0.05 (future round not yet effective)'),
    ('P-016', 'Founder tokens release nothing for the first year, then a little each day until year 4, on the same calendar for every founder.', 'Nothing for 1 year, then a little each day until year 4',                                       'PROVEN',         'TRACKED', 'smartpacts-tranches.repl',    'founder cliff-end T+365d'),
    ('P-018', 'The founder amounts must add up to exactly 10,000 — the contract refuses setup on any other total.', 'The founders — **one',                                                                          'PROVEN',         'TRACKED', 'smartpacts-founder-allocations.repl',     'SPT founder allocations must sum to FOUNDER-TRANCHE'),
    ('P-019', 'Treasury tokens unlock nothing for the first year, then a little each day until year 5.',   'Nothing for 1 year, then a little each day until year 5',                                       'PROVEN',         'TRACKED', 'smartpacts-tranches.repl',    'treasury cliff-end T+365d'),
    ('P-020', 'Market-making/liquidity tokens unlock nothing for 3 months, then a little each day until year 2.', 'Nothing for 3 months',                                                                          'PROVEN',         'TRACKED', 'smartpacts-tranches.repl',    'liquidity cliff-end T+90d'),
    ('P-022', 'The unlock schedule can never be changed after setup.',                                     'The clock starts the moment the contract is set up, and the schedule cannot be changed',        'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-023', "Each founder's tokens unlock independently — one founder taking their tokens does not touch anyone else's.", "Each founder's tokens",                                                                         'PROVEN',         'OWNER',   'smartpacts-founder-allocations.repl',     "f2's row is untouched: released still 0"),
    # 🔴 P-024 REVERSED at the design record (a later change). It promised the opposite — "a multi-signature
    # founder account can never be set up" — and that is now false. Rewritten rather than
    # deleted, because the founder was told the old thing and the page has to say it changed.
    ('P-024', 'A founder can use any address they control, including a multi-signature account.', '**A founder can use any address they control, including a multi-signature account.**', 'PROVEN', 'OWNER', 'smartpacts-founder-address.repl', 'a multisig founder address is ACCEPTED by the ceremony'),
    ('P-155', 'Each founder creates their own SPT account first, and the payment goes to an account that already exists.', '**Each founder creates their own SPT account first, and the payment goes to an\naccount that already exists.**', 'PROVEN', 'OWNER', 'smartpacts-founder-address.repl', 'a release to a not-yet-created account is REFUSED, retryably'),
    # 🔴 a later change RE-ANCHORED. The promise has two clauses — the payment is REFUSED, and the tokens
    # WAIT in the reserve — and the old anchor named the success-after-creation case, which proves
    # NEITHER. It would have stayed green if the refusal became a silent no-op or, worse, if the
    # tokens were consumed on the failed release. Both clauses are asserted in the same file
    # ('a release to a not-yet-created account is REFUSED, retryably' and 'the waiting tokens are
    # still in the founder reserve'); the manifest takes one, so it names the refusal, whose
    # "retryably" is the half a founder is relying on. The success case remains its control.
    ('P-156', 'If the account does not exist yet, the payment is refused and the tokens wait in the reserve.', 'If it does not exist yet, the payment is simply refused and the', 'PROVEN', 'TRACKED', 'smartpacts-founder-address.repl', 'a release to a not-yet-created account is REFUSED, retryably'),
    ('P-157', 'A multi-signature founder can spend the tokens it receives, not merely hold them.', 'A multi-signature founder can spend the tokens it', 'PROVEN', 'TRACKED', 'smartpacts-founder-address.repl', 'SPENDS its tranche with 2 of 3 keys'),
    ('P-017', 'There can be one founder or many; each is a plain address with its own fixed amount, chosen once at setup.', "**The founders' 10,000",                                                                        'PROVEN',         'OWNER',   'smartpacts-founder-allocations.repl',     'n=3 init-supply ok'),
    ('P-025', 'Founder tokens can only ever land on the address fixed at setup — nobody, not even the admin, can redirect them.', 'They can only ever go',                                                                         'PROVEN',         'OWNER',   'smartpacts-tranches.repl',    'SPT only the treasury and liquidity tranches are disbursed'),
    ('P-028', 'The 55,000 treasury and 15,000 liquidity tokens stay inside the contract itself — there is no beneficiary account fixed at setup any more.', "**The treasury's 55,",                                                                          'PROVEN',         'OWNER',   'smartpacts-tranches.repl',    'Am.2: the target is NOT excluded — there is no stored beneficiary any more'),
    ('P-033', "Treasury and liquidity tokens, once sent out, vote exactly like anyone else's tokens.",     'Once sent, they are ordinary',                                                                  'PROVEN',         'OWNER',   'smartpacts-tranches.repl',    'Am.2: a disbursement target votes like any holder'),
    ('P-029', 'The admin can never send more than has already vested.',                                    'No more than has vested can ever be sent',                                                                       'PROVEN',         'OWNER',   'smartpacts-tranches.repl',    'SPT disbursement exceeds the vested available amount'),
    ('P-031', 'Between treasury and liquidity, the admin decides where 70,000 tokens — 70% of everything — end up.', 'This means **the administrator controls where up to 70,000',                                                   'PROVEN',         'OWNER',   'smartpacts-tranches.repl',    'disbursed bookkeeping = total'),
    ('P-035', 'Anyone can open an SPT account under any unused name and attach their own key, with no signature needed.', '**No signature needed',                                                                         'PROVEN',         'TRACKED', 'smartpacts-promises.repl',    'the account exists and holds nothing'),
    ('P-071', 'An account name derived from a key (k:/w:) cannot be opened by anyone except the holder of that key.', 'An account name and a',                                                                         'PROVEN',         'TRACKED', 'SPT-ext.repl',   'SPT reserved protocol guard violation: k:2222222222222222222222222222222222222222222222222222222222222222'),
    ('P-047', 'If the second transaction of a cross-chain transfer never completes — because you never send it, or because a stranger squats the receiver name after you sent — the tokens are off one chain and not on the other, held rather than destroyed, until that name carries your key.', 'Sends tokens to an account',                                                                    'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-090', 'The admin can never send out more treasury or market-making tokens than have vested on the fixed calendar.', 'Sends tokens and opens',                                                                        'PROVEN',         'TRACKED', 'smartpacts-tranches.repl',    'SPT disbursement exceeds the vested available amount'),
    ('P-037', 'Sending tokens to another chain always takes two transactions: they leave here, then a second one lands them there.', '**Two transactions**',                                                                          'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-038', 'SPT can be moved from one chain to another.',                                               'Sends tokens to another chain',                                                                 'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-117', "The deploy checklist's chain-by-chain comparison against chain 0 is still required, because the contract cannot catch an address that is wrong but valid and correctly keyed.", "Who from, who to, the receiver's key, which",                                                   'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-039', "Only the account's own key can change that account's key — there is no admin override and no recovery for a lost key.", 'A lost key has no recovery',                                                                    'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-040', "A key-derived account's key can never be changed; only a plain-nickname account can rotate its key.", 'Changes the key controlling',                                                                   'PROVEN',         'TRACKED', 'SPT-ext.repl',   'SPT: it is unsafe for principal'),
    ('P-042', 'No transaction can call debit or credit directly — they only run inside the transfers.',    'No transaction can call',                                                                       'PROVEN',         'TRACKED', 'smartpacts-attacks.repl',     'direct debit() blocked by require-capability'),
    ('P-043', "get-circulating reports only this chain's tokens, and no read totals all 20 chains.",       'There is no read that totals all 20 chains.',                                                   'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-044', 'The accounts the contract keeps out of voting and awards are exactly the four reserves it owns itself, and nothing else.', 'Whether an account is',                                                                         'PROVEN',         'TRACKED', 'smartpacts-tranches.repl',    'CONTROL: the treasury RESERVE itself is still excluded (defconst, all 20 chains)'),
    # 🔴 RESTATED after an external review, and the promise got STRONGER. It used to
    # read "a mistyped or wrong sale-reserve address FAILS the setup transaction", pinned by a
    # negative that passed a wrong address. The address is no longer a PARAMETER — it is the
    # module's own LAUNCH-RESERVE-PIN defconst — so a wrong one cannot be supplied at all.
    # The pin now points at the half that REMAINS falsifiable: the guard must derive that pin.
    ('P-115', 'The sale-reserve address cannot be set wrong at setup: it is fixed in the contract, and the key supplied with it must be the one that produces it.', "The sale reserve's account",                     'PROVEN',         'TRACKED', 'SPT-init.repl',  'launch reserve guard does not derive the pinned'),
    ('P-045', 'A token amount can have at most 12 decimal places.',                                        'How many decimal places',                                                                       'PROVEN',         'TRACKED', 'SPT.repl',       'precision 12'),
    ('P-046', 'After the platform fix, tokens cannot be destroyed by any function here and every debit is matched by a credit.', '**After the fix**, tokens',                                                                     'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-048', 'A vote is always yes or no — never multiple choice.',                                       'Votes are **yes or no',                                                                         'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-049', 'A vote must run for between 3 and 14 days, and those limits can never be changed after the contract is frozen.', 'Voting must open **at',                                                                         'PROVEN',         'TRACKED', 'smartpacts-promises.repl',    'duration below 72h minimum'),
    ('P-050', 'One cancelled copy voids the whole result — a total must not be published if any of the 20 chains cancelled.', 'One cancelled copy voids',                                                                      'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-051', 'Only the admin can void a proposal, and only before voting opens — never after.',           'Voids a proposal — *',                                                                          'PROVEN',         'TRACKED', 'smartpacts-governance.repl',  'SPT cannot cancel once voting has opened for this proposal'),
    ('P-052', 'A vote is refused before voting opens and after it closes.',                                'Refused before voting',                                                                         'PROVEN',         'TRACKED', 'smartpacts-governance.repl',  'voting closed'),
    ('P-053', 'A holder votes on the chain where their tokens are, and that vote is recorded only on that chain — it does not travel.', 'Votes on the chain where',                                                                      'PROVEN',         'TRACKED', 'smartpacts-governance.repl',  'vote recorded under chain-5 scope'),
    ('P-062', 'Voting again replaces your previous vote — it is never counted twice.',                     'Who is voting, the proposal',                                                                   'PROVEN',         'TRACKED', 'smartpacts-governance.repl',  'yes now 0 (alice flipped)'),
    ('P-055', 'Every vote left open makes all transfers on that chain more expensive until it is closed.', 'It does not change the result, but **every vote left',                                          'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    # 🔴 a later change RE-ANCHORED. The old anchor, 'a non-admin closes the proposal', pinned the EASY
    # half (closing is permissionless) and said nothing about the half the product rests on — that
    # the result freezes at the deadline whether or not anyone ever closes it. That second clause is
    # what makes the 20-chain `vote-record` sum legitimate, and a regression in it would have left
    # this row PROVEN. The assertion below already existed; it simply was not the one named.
    ('P-054', 'Anyone can close a finished vote, and closing does not change the result — the result freezes at the deadline whether or not anyone ever closes it.', 'Marks a finished vote',                                                                         'PROVEN',         'TRACKED', 'smartpacts-governance.repl',  'tally frozen at close-at'),
    ('P-056', 'Only the admin can announce a proposal, on every chain.',                                   'Voter, chain, proposal',                                                                        'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-057', 'A holder can register a lower-risk key to vote for them, and an empty or non-keyset one is refused.', 'Registers a lower-risk',                                                                        'PROVEN',         'TRACKED', 'smartpacts-votekey.repl',     'SPT vote key must not be an empty keyset'),
    # 🔴 a later change: P-076's PIN WAS THE WRONG ASSERTION, and it had been PROVEN on it for months.
    # It named `"neither account guard nor registered vote key satisfied"` — the VOTE GUARD's
    # message, which fires four checks before the exclusion enforce this promise is about. Cold
    # an internal review found it; MEASURED here: with `"excluded reserve cannot vote"` deleted from the
    # module, the old assertion stayed GREEN and a foreign-composed unsigned caller cast the
    # treasury's 55,000 SPT into a live tally. Re-pointed at §EXCL in the same file, which
    # satisfies the VOTE guard FIRST and then proves the exclusion check refuses. Audit #14's
    # a finding class exactly: a status derived from a pin that could not fail.
    ('P-076', 'The reserve accounts the contract owns can never vote.',                                    'Your account and a voting',                                                                     'PROVEN',         'TRACKED', 'smartpacts-governance.repl',  'excluded reserve cannot vote'),
    ('P-058', 'Voting can never open less than 48 hours after the announcement actually lands on that chain.', 'Whether voting on it',                                                                          'PROVEN',         'TRACKED', 'smartpacts-proposal-lifecycle.repl',      'SPT voting must open at least the minimum review gap after this announcement'),
    ('P-036', 'transfer only reaches an account that already exists on this chain.',                       'Every open one makes transfers on that chain',                                                  'PROVEN',         'TRACKED', 'smartpacts-promises.repl',    'SPT_accounts for key: no-such-account'),
    ('P-021', 'The unlock clock starts at the moment the contract is set up.',                             "The contract's counter",                                                                        'PROVEN',         'TRACKED', 'smartpacts-tranches.repl',    '2027-06-01T00:00:00Z'),
    ('P-059', 'Moving tokens reduces your vote only by what you no longer hold — if you still hold enough to back your whole vote, your vote is untouched.', '**Moving tokens only',                                                                          'PROVEN',         'OWNER',   'smartpacts-attacks-vgrief.repl', "🔴 V4b: returning an unwanted gift destroyed NONE of alice's vote"),
    ('P-060', 'Announcing a vote is 20 transactions, one per chain, and each must land at least 48 hours before voting opens or that chain is refused.', '**Announcing a vote is',                                                                        'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-061', 'Your voting weight is your balance at the moment you vote; receiving more tokens does not increase it unless you vote again.', '**Your weight is your',                                                                         'PROVEN',         'OWNER',   'smartpacts-governance.repl',  "dave's recorded vote unchanged by the dust he received"),
    ('P-134', 'Treasury tokens the admin sends to someone become ordinary tokens that vote.',              'Sending tokens away shrinks',                                                                   'PROVEN',         'OWNER',   'smartpacts-tranches.repl',    'Am.2: a disbursement target votes like any holder'),
    ('P-064', "An award round is refused unless this chain's pool already holds the money it promises — you must fund first, then declare.", 'A round is refused unless',                                                                     'PROVEN',         'OWNER',   'smartpacts-solvency-at-declaration.repl',      'SPT award pool does not cover the liability this round declares'),
    ('P-067', 'The same round must be declared on all 20 chains with identical values.',                   'Must be repeated on all 20 chains with identical values.',                                      'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-074', 'Only the most recently declared round can ever be cancelled, and only once.',               'Cancels the newest round',                                                                      'PROVEN',         'OWNER',   'smartpacts-account-and-round-safety.repl',     'the last declared award round is already retracted'),
    ('P-070', "Holders are owed and can be paid as soon as a round's date passes — nobody has to call apply-round first.", '**Not required for holders',                                                                    'PROVEN',         'TRACKED', 'smartpacts-award-fairness.repl', 'rpt now 0.08 (future round R4 became effective)'),
    ('P-132', "Anyone can trigger a claim, and the KDA always lands on the holder's own address — a squatter cannot intercept or block it.", 'Anyone can trigger it; the KDA always goes to the holder.',                                     'PROVEN',         'OWNER',   'smartpacts-attacks.repl',     'bob claim succeeds despite squatted coin name'),
    ('P-068', "A round's effective date must be at least 12 hours in the future.",                         "One round's rate and",                                                                          'PROVEN',         'TRACKED', 'smartpacts-record-date.repl',      'must leave at least two retraction leads of runway'),
    ('P-118', 'The number the contract reports as owed to holders equals the sum of what every holder can actually claim.', 'What this chain owes its holders in KDA',                                                       'PROVEN',         'OWNER',   'smartpacts-award-fairness.repl', 'award-liability == Σ pending-of (before dump)'),
    ('P-069', 'A declared round can be cancelled only while more than 6 hours remain before it takes effect.', 'Rounds already in effect',                                                                      'PROVEN',         'TRACKED', 'smartpacts-account-and-round-safety.repl',     'too close to taking effect'),
    ('P-075', 'Only run recover-pool-surplus after a round is declared — before that, money you just deposited reads as surplus and sweeping it kills the declaration.', '**Only run this after a round is declared**',                                                   'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-063', 'Unclaimed awards never expire.',                                                            '**Awards accumulate and',                                                                       'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    # 🔴 a later change: THE PROMISE NAMES FOUR ACCOUNTS AND ONLY TWO WERE ASSERTED ANYWHERE. Treasury and
    # the launch reserve had lines; FOUNDER-ACCOUNT and LIQUIDITY-ACCOUNT had none in ANY suite
    # (grepped for `pending-awards-of` across every .repl). `excluded?` covers all four in code, so
    # the property held — only the EVIDENCE was short, and dropping either account from `excluded?`
    # would have left this row PROVEN and green. Fifth instance of the class (P-160, P-076, D-2,
    # P-147, now P-111). Both missing lines added to SPT.repl beside the other two.
    # 🔴 NON-VACUITY MEASURED, because "expect 0.0" is exactly the shape that passes for free: at
    # that point in the suite rpt = 0.02 with founder holding 10,000.0 and liquidity 15,000.0, so an
    # un-excluded account would read 200.0 and 300.0 — not 0.0. The anchor below still names ONE
    # account because the manifest takes one assertion; it is the largest reserve, and the other
    # three now have their own lines in the same file.
    ('P-111', "The contract's own accounts (treasury, market-making, founder, sale reserves) always earn zero awards.", 'Reserve accounts always',                                                                       'PROVEN',         'OWNER',   'SPT.repl',       'treasury accrues 0 (excluded)'),
    ('P-013', 'There are exactly 100,000 SPT and setup is the only event that ever creates them.',         '**There is no obligation',                                                                      'PROVEN',         'OWNER',   'SPT-init.repl',  'module already initialized'),
    ('P-077', 'There is no obligation to ever declare an award — the company may reinvest everything for years without breaking any rule in the contract.', 'The company may reinvest',                                                                      'NOT-BUILT',      'OWNER',   '',                            ''),
    # 🔴 REWRITTEN 2026-08 — this promise was FALSE, not merely mis-anchored. It described
    # the design record's FLOOR, which the design record replaced with an EXACT bar against a SEALED float. 'Tokens
    # in circulation can still grow before it takes effect' stopped being true when the record
    # date landed, and the row stayed ✅ PROVEN for weeks against an assertion the suite had
    # DELETED — surviving only in the comment that explains the deletion, which is exactly what
    # the new non-comment check catches. Re-anchored to the assertion that DISPROVES the old
    # wording, so a regression to floor-semantics reddens this row.
    ('P-078', 'The money a round needs is measured against a count of tokens frozen at the record date, so someone buying after that instant does not change what the round owes.', '**The money a round needs is measured against a count of tokens frozen at the record date**',                                                                          'PROVEN',         'OWNER',   'smartpacts-record-date.repl', 'the bar is rate x SEALED float (6000), not rate x current float (9000)'),
    ('P-079', 'A partial retraction does not fail safe — retracting on 19 chains and being refused on the 20th locks the difference in permanently.', 'Retracting on 19 chains',                                                                       'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-080', "Anyone can trigger a founder's vested payment, and the tokens can only ever land on that founder's address fixed at setup.", 'Anyone can trigger it; the tokens',                                                             'PROVEN',         'TRACKED', 'smartpacts-founder-address.repl', 'the multisig founder is paid its full tranche'),
    ('P-026', 'Anyone at all can trigger a founder payment once it has vested — no signature and no permission needed.', 'Pays a founder whatever has',                                                                   'PROVEN',         'TRACKED', 'smartpacts-founder-allocations.repl',     'f1 mid-vest release pays out, keyless'),
    ('P-085', 'Only the admin can send treasury or market-making tokens.',                                 '**The administrator sends treasury or',                                                                        'PROVEN',         'OWNER',   'smartpacts-tranches.repl',    'a non-admin cannot disburse'),
    # 🔴 a later change RE-ANCHORED. Two clauses: the destination must EXIST, and it must never be one of
    # the contract's own accounts. The old anchor pinned only the first. The second is the one that
    # protects 70,000 SPT from being disbursed into a reserve nobody can spend from — and it is the
    # line a later change let-bound out of an `enforce` condition, so it is live code under active change.
    # The assertion already existed in the same file; naming it is the whole fix.
    ('P-081', "A disbursement destination must already be a real SPT account and can never be one of the contract's own accounts, including the sale's reserve.", 'The destination must',                                                                          'PROVEN',         'TRACKED', 'smartpacts-tranches.repl',    'SPT disbursement target must not be an excluded account'),
    ('P-098', 'Only the admin can move treasury or liquidity tokens out.',                                 '`treasury` or `liquidity`,',                                                                    'PROVEN',         'TRACKED', 'smartpacts-tranches.repl',    'a non-admin cannot disburse'),
    ('P-086', 'The admin sends vested treasury and liquidity tokens wherever they choose, whenever they choose, in as many separate payments as they like.', '**the administrator sends vested treasury and liquidity tokens wherever they choose',                                                                       'PROVEN',         'TRACKED', 'smartpacts-tranches.repl',    'part one, back to the market maker'),
    ('P-087', 'Every release, payment and availability read uses the one vesting formula.',                'Every release, payment',                                                                        'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-088', 'At the cliff you get zero; it accrues after.',                                              'At the cliff you get',                                                                          'PROVEN',         'OWNER',   'smartpacts-promises.repl',    'at the cliff exactly, still zero'),
    ('P-089', "Nobody, including the admin, can redirect or cancel a founder's allocation.",               '**Founder tokens:** nobody',                                                                    'PROVEN',         'OWNER',   'smartpacts-tranches.repl',    'SPT only the treasury and liquidity tranches are disbursed'),
    ('P-083', 'Treasury and market-making tokens can be sent only to accounts you choose, only in amounts already vested and not yet sent, split across as many payments and accounts as you like.', '**Treasury and market-making tokens',                                                           'PROVEN',         'OWNER',   'smartpacts-tranches.repl',    'SPT disbursement exceeds the vested available amount'),
    ('P-091', 'Every treasury or market-making payment is published on-chain with its destination and amount.', 'Every such payment is',                                                                         'PROVEN',         'OWNER',   'smartpacts-tranches.repl',    'TRANCHE-DISBURSED carries tranche, target, amount and the running total'),
    ('P-092', 'There is no undo — a payment sent to the wrong address cannot be reversed by anyone.',      'A payment to a wrong',                                                                          'NOT-BUILT',      'OWNER',   '',                            ''),
    ('P-093', 'Anyone can pay KDA funding into the company account — no admin permission needed.',         'Anyone can pay KDA funding',                                                                    'PROVEN',         'TRACKED', 'smartpacts-capability-guard-class.repl',     "C-1c: an ordinary payer's funding deposit still succeeds"),
    ('P-125', 'Nobody, including the admin, can pay a founder faster than the calendar.',                  'Who is paying, how much',                                                                       'PROVEN',         'TRACKED', 'smartpacts-founder-allocations.repl',     'nothing releasable'),
    ('P-131', 'Only the admin can move company KDA out.',                                                  'Moves company KDA out',                                                                         'PROVEN',         'TRACKED', 'smartpacts-attacks.repl',     'funding KDA cannot be moved without SPT module admin'),
    ('P-094', 'Withdrawing company money has no allowlist of destinations and no cap on the amount.',      'No allowlist, no cap',                                                                          'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-082', 'A funding payment must be a positive amount — zero and negative are refused.',              'Refuses any amount with',                                                                       'PROVEN',         'TRACKED', 'smartpacts-mutation-survivors.repl',  'SPT funding amount must be positive'),
    ('P-135', 'The gasless contract will get its own audit before it ships.',                              "The contract's own lookup",                                                                     'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-095', "Money can never be pulled OUT of one of the contract's own five protected accounts by calling the funding deposit.", "Answers whether a name is one of the contract's own",                                           'PROVEN',         'TRACKED', 'smartpacts-capability-guard-class.repl',     'SPT protocol accounts cannot be the source of a funding deposit'),
    ('P-096', 'Setup can never run twice on the same chain, for either contract.',                         'The one-shot lock: setup refuses to ever run twice',                                            'PROVEN',         'TRACKED', 'SPT-init.repl',  'module already initialized'),
    ('P-097', 'The sale is installed on chain 0 only; the token, voting and awards run on all 20 chains.', 'Tokens, voting and awards',                                                                     'PROCEDURE',      'OWNER',   '',                            ''),
    # 🔴 a later change REWRITTEN, and it was FALSE on BOTH bounds. It read "between 0.01 and 1,000 KDA
    # per token": the upper bound came from MAX-PRICE, which the design record DELETED after measuring that
    # the harm did not reproduce, and the lower bound was the constant floor that a later change replaced
    # with the launch price. Neither number had been true for some time. Caught by the gate only
    # because the floor moved; the dead upper bound would have survived otherwise.
    ('P-103', "The price can never go below the sale's floor, which starts equal to the price the sale opened at, and there is no upper limit.", 'never below the floor', 'PROVEN', 'TRACKED', 'smartpacts-promises.repl', 'the floor equals the launch price, not a constant'),
    ('P-101', "The sale's own two accounts can never be the buyer.",                                       "The sale's own accounts",                                                                       'PROVEN',         'TRACKED', 'smartpacts-capability-guard-class.repl',     'SPT sale accounts cannot buy tokens'),
    ('P-100', 'A lost key cannot be recovered — nobody, not even the admin, can reassign an account or move its tokens.', 'Your account, your key',                                                                        'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-104', 'The price cannot be changed while the sale is open.',                                       'The price per token · whether the sale',                                                        'PROVEN',         'TRACKED', 'SPT-launch.repl',      'SPT price is locked while the sale is active'),
    ('P-034', 'The sale price can only be changed by the admin, and only while the sale is paused.',       'Changes the price — *',                                                                         'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-105', 'The sale starts closed and stays closed until someone opens it.',                           '**It starts closed**',                                                                          'PROVEN',         'TRACKED', 'SPT-launch.repl',      'inactive until resumed'),
    ('P-102', 'Only the admin can open the sale, change the price, or move the proceeds out.',             "Moves the sale's KDA",                                                                          'PROVEN',         'TRACKED', 'SPT-launch.repl',      'intruder-key'),
    ('P-106', 'There is no per-buyer cap — one buyer can buy as many times and as much as they like.',     '**No per-buyer cap**',                                                                          'PROVEN',         'OWNER',   'smartpacts-promises.repl',    'both purchases landed on one account'),
    ('P-107', 'Unsold tokens sitting in the sale reserve are outside voting and awards, and nothing retires them.', 'They are outside voting',                                                                       'PROVEN',         'OWNER',   'SPT-launch-reserve.repl', 'the recorded launch reserve is excluded from float/voting/awards'),
    ('P-130', 'Treasury and market-making need no account supplied at setup.',                             '**Treasury and market-making need',                                                             'PROVEN',         'TRACKED', 'smartpacts-founder-allocations.repl',     'five TRANCHE-LOCKED events: one per founder row + the two fixed rows'),
    ('P-110', 'The founder amounts must sum to exactly 10,000 or setup is refused.',                       'The founder list (each',                                                                        'PROVEN',         'TRACKED', 'SPT-init.repl',  'founder 10k'),
    ('P-108', 'Supply setup can only run on chain 0, and the other-19-chains setup is refused on chain 0.', '**The other 19 chains',                                                                         'PROVEN',         'TRACKED', 'SPT-init.repl',  'Supply init only on chain 0'),
    ('P-084', 'A disbursement destination must already exist as an SPT account — the contract never creates one for you.', 'Creates the accounts.',                                                                         'PROVEN',         'TRACKED', 'smartpacts-tranches.repl',    'SPT_accounts for key: k:b2b2'),
    ('P-112', 'Setting up the other 19 chains issues no tokens.',                                          'No tokens are issued',                                                                          'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-120', 'The four buckets — 20,000 sale, 10,000 founders, 55,000 treasury, 15,000 liquidity — add up to the whole supply, with nothing left over.', 'The sale reserve, with',                                                                        'PROVEN',         'TRACKED', 'smartpacts-tranches.repl',    'reserves sum to full 100k with launch 20k'),
    ('P-113', 'The token must be set up on a chain before the sale is — the sale cannot go first.',        '**Order matters:** the token must be set',                                                      'PROVEN',         'OWNER',   'SPT-launch-reserve.repl', 'the sale cannot initialize on a chain the token refused to initialize'),
    ('P-114', 'A configured address is checked to be a real address of a supported kind, and nothing else.', '**A configured address is checked to be a real address of a supported kind, and nothing else**', 'PROVEN', 'OWNER', 'smartpacts-init-beneficiary-bounds.repl', 'a non-principal (vanity) founder is refused'),
    ('P-116', 'Setup writes the configured values to the public event log at the moment they are fixed.',  'The value is written',                                                                          'PROVEN',         'OWNER',   'smartpacts-founder-allocations.repl',     'five TRANCHE-LOCKED events: one per founder row + the two fixed rows'),
    ('P-119', 'The gasless helper contract is not part of the first deployment — everything in this product ships with the caller paying their own gas.', '**It is not part of the first',                                                                 'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-121', 'The contract has been reviewed at exactly the version that would deploy, with no CRITICAL, no HIGH and nothing in the contract logic.', '**The contract has been reviewed at exactly the version that would deploy',                        'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-032', 'A lawyer should review the 70,000-token admin discretion before it is used on the real network.', '**A lawyer should review',                                                                      'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-122', 'No contract code is deployed anywhere, but the namespace and both admin keysets are live on mainnet on all 20 chains and that part is permanent.', '**No contract code is deployed anywhere**',                        'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-123', 'Nothing deploys until the Kadena platform fix is live on the chain being deployed to, measured there at the time.', '**Nothing deploys until',                                                                       'PROCEDURE',      'OWNER',   '',                            ''),
    ('P-124', 'Until the contract is frozen, whoever holds the admin key can upgrade it in place and change how it behaves.', 'Until then, whoever holds',                                                                     'PROVEN',         'OWNER',   'smartpacts-upgrade-emergency.repl', 'balances survived'),
    ('P-127', 'Once frozen, the contract can never be upgraded, changed or repaired again.',               'After freezing, no function can ever be changed',                                               'PROVEN',         'OWNER',   'frozen-upgrade-token.repl-must-fail', 'Module is frozen'),
    ('P-128', 'Once frozen, value can still leave the contract, and this page lists every way that survives the freeze.', '**Once frozen, value',                                                                          'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-133', 'Money already owed under a declared round can never be taken back out of the pool by the admin.', 'Money leaving the pool',                                                                        'PROVEN',         'OWNER',   'smartpacts-pool-surplus.repl', "amount exceeds the award pool's unowed surplus"),
    ('P-030', "Treasury and liquidity tokens, once sent out, earn awards exactly like anyone else's tokens.", 'Treasury tokens sent to someone become ordinary tokens that vote',                                                              'BUILT-UNPINNED', 'OWNER',   '',                            ''),
    ('P-136', 'The contract keeps named ACCOUNTS out of voting, never the tokens behind them — one person can hold both an excluded account and an ordinary one, and no contract can tell them apart.', 'The contract only keeps *named',                                                      'PROCEDURE',      'OWNER',   '',                            ''),
]


class Tooling(Exception):
    """A structural problem with the gate or the tree it runs in — exit 2, never exit 1."""


def die(msg):
    raise Tooling(msg)


def read(path):
    try:
        with open(path, encoding='utf-8') as fh:
            return fh.read()
    except OSError as e:
        die(f"cannot read {path}: {e}")


def runner_manifests(src):
    """What the runner ACTUALLY executes — all four manifests, not just SUITES.

    🔴 SUITES alone is not "the tests that run". run-tests.sh drives four named sets, and a pin
    living in any of them is genuinely run. Checking only SUITES would have rejected legitimate
    pins in `xx-ind-*` and `zz-audit-*` — and the natural repair for that failure is to weaken the
    check or to move the assertion into a suite it does not belong in. Both are worse than parsing
    all four. Each is a NAMED manifest in the runner, so this reads names, never a glob.
    """
    stems, mustfail = set(), set()
    for var in ('SUITES',):   # [public build] probe families are not published
        m = re.search(rf'^{var}=\(\s*(.*?)\)\s*$', src, re.S | re.M)
        if not m:
            die(f"no {var}=( ... ) block found in {SUITE_RUNNER} — the runner's shape changed; "
                f"fix this gate deliberately rather than dropping the check")
        stems |= set(m.group(1).split())
    m = re.search(r'declare -A MUSTFAIL=\(\s*(.*?)^\)', src, re.S | re.M)
    if not m:
        die(f"no `declare -A MUSTFAIL=( ... )` block found in {SUITE_RUNNER} — the runner's shape "
            f"changed; fix this gate deliberately rather than dropping the check")
    mustfail = set(re.findall(r'\[\"([^\"]+)\"\]=', m.group(1)))
    if not stems or not mustfail:
        die(f"parsed {SUITE_RUNNER} but found {len(stems)} suite stems and {len(mustfail)} "
            f"must-fail fixtures — a manifest that parsed to nothing is a tooling failure, "
            f"never a pass")
    return {'stems': stems, 'mustfail': mustfail}


def _cut(doc, open_tag, close_tag):
    """Return (doc-without-region, span-or-None). Fails closed on an unbalanced delimiter."""
    if open_tag not in doc:
        return doc, None
    if close_tag not in doc:
        die(f"{open_tag} has no matching {close_tag} in {DOC}")
    a = doc.index(open_tag)
    b = doc.index(close_tag, a) + len(close_tag)
    return doc[:a] + doc[b:], (a, b)


def strip_legend(doc):
    """Remove BOTH delimited legends so neither's marks are counted as promise marks.

    Returns (body, had_promise_legend, caller_span). `caller_span` is the region of the ORIGINAL
    doc occupied by the caller legend, so an anchor can be rejected for living inside it.
    """
    body, _ = _cut(doc, LEGEND_OPEN, LEGEND_CLOSE)
    body, _ = _cut(body, CALLER_OPEN, CALLER_CLOSE)
    _, cspan = _cut(doc, CALLER_OPEN, CALLER_CLOSE)
    return body, (LEGEND_OPEN in doc), cspan


_LIST = re.compile(r'^(?:[-*+]\s+|\d+\.\s+)')
_TERM_END = re.compile(r'[.!?:]["»)*_`\]]*$')
_TERM_MID = re.compile(r'[.!?:]["»)*_`\]]*\s+$')


def begins_sentence(doc, pos):
    """Does the character at `pos` start a SENTENCE on the rendered page?

    🔴 NOT "starts a line" — that was the proxy that let 24 marks through. Markdown soft-wraps, so
    the second line of a wrapped paragraph starts a LINE in the middle of a SENTENCE, and a mark
    placed there reads as qualifying a clause fragment. The distinction is the whole check.
    """
    ls = doc.rfind('\n', 0, pos) + 1
    pre = doc[ls:pos]
    stripped = re.sub(r'^[>\s]*', '', pre)
    m = _LIST.match(stripped)
    rest = stripped[m.end():] if m else stripped
    if rest.strip():
        # the start of a table CELL begins a sentence just as a line does
        if re.search(r'\|\s*$', pre):
            return True
        return bool(_TERM_MID.search(pre))      # text precedes on this line: need a terminator
    if m:
        return True                             # opens a new list item = a new block
    pe = ls - 1
    if pe <= 0:
        return True
    pls = doc.rfind('\n', 0, pe) + 1
    prev = doc[pls:pe].rstrip()
    if not prev.strip() or re.fullmatch(r'>\s*', prev):
        return True                             # blank line before = new paragraph
    if prev.startswith('#') or prev.startswith('|') or prev.startswith('---'):
        return True
    return bool(_TERM_END.search(prev))          # otherwise the previous line must end a sentence


def table_column(doc, pos):
    """0-based column index if `pos` sits inside a markdown table row, else None.

    🔴 Column ZERO is where the caller glyph and the function name live — the exact cell that
    collided with the status vocabulary twice. A mark may live in a table cell, but never there.
    """
    ls = doc.rfind('\n', 0, pos) + 1
    le = doc.find('\n', pos)
    line = doc[ls: len(doc) if le < 0 else le]
    if not line.lstrip().startswith('|'):
        return None
    return doc[ls:pos].count('|') - 1


def audit(promises, doc, runs, exists, read_test):
    """The pure core. Returns (failures, counts). Raises Tooling on a structural problem.

    `exists(pin)` and `read_test(pin)` are injected so the self-test never touches the tree.
    """
    if not promises:
        return (["the manifest is EMPTY, so this gate inspected zero promises. A check that "
                 "inspects nothing is a failure, not a pass. Populate PROMISES, or delete this "
                 "gate deliberately with the reason."], {})

    if len(promises) != EXPECTED_TOTAL:
        die(f"manifest holds {len(promises)} promises but EXPECTED_TOTAL is {EXPECTED_TOTAL}. "
            f"The mapping pass found {EXPECTED_TOTAL}. If a promise was genuinely retired, say "
            f"why and change EXPECTED_TOTAL IN THE SAME COMMIT — never quietly.")

    # Both legends are excised up front: `body` is what mark COUNTS and the adjacency scan see,
    # and `cspan` lets a row be rejected for anchoring inside the caller legend.
    body, had_legend, cspan = strip_legend(doc)

    failures = []

    # 🔴 PROPOSAL REGIONS must be DECLARED (a later change). An "approved, not yet built" section carries
    # no status marks by design, so it is invisible to every other check here — which is exactly
    # how an 80-line "it is not built yet" section about the design record survived the design record shipping, on the
    # same page whose body already described it as built.
    for m in re.finditer(re.escape(PROPOSAL_OPEN) + r'(.*?)' + re.escape(PROPOSAL_CLOSE),
                         doc, re.S):
        region = m.group(1)
        title = next((ln.strip() for ln in region.split('\n') if ln.strip().startswith('#')), '')
        if not any(key in title for key in PROPOSAL_REGIONS):
            failures.append(
                'UNDECLARED PROPOSAL REGION: %r is wrapped in promise-gate:proposal but is not in '
                'PROPOSAL_REGIONS. An "approved, not yet built" section carries no status marks, so '
                'nothing else on this page can notice it going false when the work lands. Declare it '
                'with WHY it is still unbuilt, or delete it because it shipped.'
                % (title[:90] or '<untitled region>'))
    # A declared region whose marker is gone is a stale manifest entry, not a pass.
    for key in PROPOSAL_REGIONS:
        if key not in doc:
            failures.append('PROPOSAL_REGIONS names %r but no such region is on the page — the '
                            'section shipped or was renamed; remove the entry.' % key)

    counts = {k: 0 for k in STATUS}
    owner = {k: 0 for k in STATUS}
    seen_ids = set()

    for row in promises:
        if len(row) != 7:
            die(f"malformed row (want 7 fields: id, promise, phrase, status, tier, pin, "
                f"assertion): {row!r}")
        pid, promise, phrase, status, tier, pin, assertion = row

        if pid in seen_ids:
            die(f"duplicate promise id {pid}")
        seen_ids.add(pid)

        if status not in STATUS:
            die(f"{pid}: unknown status {status!r} — allowed: {', '.join(STATUS)}")
        if tier not in TIERS:
            die(f"{pid}: unknown tier {tier!r} — allowed: {', '.join(TIERS)}")

        # 🔴 THE RULE THAT MAKES TIER SAFE. A weak promise may never be hidden.
        if tier == 'TRACKED' and status not in TRACKABLE:
            failures.append(
                f"{pid}: status {status} may NOT be TRACKED. Only {'/'.join(sorted(TRACKABLE))} "
                f"may be hidden from the page — otherwise demoting a promise is a way to make bad "
                f"news quieter. Mark it OWNER and let the page carry it.")
            continue

        counts[status] += 1
        if tier == 'OWNER':
            owner[status] += 1
        mark = STATUS[status][0]

        # 1. the sentence must still be on the page
        if phrase not in doc:
            failures.append(
                f"{pid}: the page no longer contains its promise text.\n"
                f"         looked for: {phrase!r}\n"
                f"         Either the promise changed (update this manifest IN THE SAME COMMIT)\n"
                f"         or it was deleted (say why — a deleted promise is a product change).")
            continue

        # 2. an OWNER promise must show its derived status IMMEDIATELY BEFORE the sentence,
        #    and that sentence must actually start there.
        #
        # 🔴 This replaced a ±220-character WINDOW. A window is a proximity proxy: it passed when
        # ANY matching mark happened to sit nearby, which is how a NOT-BUILT row was satisfied by an
        # unrelated `🔴 admin only` in a table. Adjacency is the property actually wanted, so it is
        # the property actually checked.
        idx = doc.index(phrase)
        if cspan and cspan[0] <= idx < cspan[1]:
            failures.append(
                f"{pid}: its promise text lives INSIDE the caller legend, which explains "
                f"{CALLER_MARKS} and makes no promise. Anchor it to a sentence that makes a claim.")
            continue
        # 🔴 CHECK 4 — THE ANCHOR MUST BE ABOUT THE PROMISE.
        # Every placement check can pass on a sentence that says something else. P-034 anchored
        # inside the CALLER LEGEND and P-038 — a "SPT can be moved between chains" promise —
        # anchored to the "**What SPT cannot do**" LABEL. Both began a sentence, neither touched a
        # caller mark, and both were flatly wrong. Shared vocabulary is what notices.
        # 🔴 An anchor with NO content words cannot state anything, and treating that as a pass
        # is the "a check that inspected zero items must FAIL" hole: P-072 cited "Who from, who
        # to, how" — all stopwords — and skipped check 4 entirely.
        pt, at = _tokens(promise), _tokens(phrase)
        if not at and pid not in ANCHOR_EXEMPT:
            failures.append(
                f"{pid}: its anchor carries no content words at all ({phrase!r}), so it cannot "
                f"state this or any promise. Anchor to a sentence that says something.")
            continue
        overlap = len(pt & at) / len(at) if at else 0.0
        if pid in ANCHOR_EXEMPT and overlap >= MIN_ANCHOR_MATCH:
            failures.append(
                f"{pid}: has a named check-4 exemption but PASSES at {overlap:.0%}. Remove the "
                f"exemption — a stale one quietly becomes a blanket one.")
        if pid not in ANCHOR_EXEMPT:
            if overlap < MIN_ANCHOR_MATCH:
                failures.append(
                    f"{pid}: its anchor does not appear to state its promise "
                    f"(shared vocabulary {overlap:.0%} < {MIN_ANCHOR_MATCH:.0%}).\n"
                    f"         promise: {promise[:88]!r}\n"
                    f"         anchor : {phrase[:88]!r}\n"
                    f"         A mark on a sentence that does not make the claim tells the founder\n"
                    f"         a proof exists for something the sentence never said.\n"
                    f"         Fix the ANCHOR, restate the PROMISE, or add a named ANCHOR_EXEMPT\n"
                    f"         with a reason — never widen MIN_ANCHOR_MATCH to absorb it.")

        if tier == 'OWNER':
            col = table_column(doc, idx)
            if col == 0:
                failures.append(
                    f"{pid}: its anchor is in a table row's FIRST column, which holds the caller "
                    f"glyph and the function name. Anchor to a later column.")
                continue
            m = re.search(r'([' + ''.join(s[0] for s in STATUS.values()) + r']) $', doc[:idx])
            if not m:
                failures.append(
                    f"{pid}: no status mark immediately precedes this promise.\n"
                    f"         Expected {mark!r} then one space, directly before the sentence.\n"
                    f"         The page's status is DERIVED from this manifest — never hand-written.")
            elif m.group(1) != mark:
                failures.append(
                    f"{pid}: the page shows {m.group(1)} beside this promise, the manifest "
                    f"derives {mark} ({status}).")
            elif not begins_sentence(doc, m.start()):
                failures.append(
                    f"{pid}: its mark {mark} does not BEGIN a sentence — it sits mid-clause, most\n"
                    f"         likely on the wrapped second line of a paragraph. Re-anchor to the\n"
                    f"         start of the sentence the promise is actually made in.")

        # 3/4. PROVEN must name a real, RUN test containing the named assertion
        if status == 'PROVEN':
            if not pin or not assertion:
                die(f"{pid}: PROVEN requires both a pin file and an assertion string")
            if pin.endswith('.ts'):
                if pin not in DEVNET_DRIVERS:
                    die(f"{pid}: {pin!r} is a devnet-tier pin but is not in DEVNET_DRIVERS. "
                        f"Register it there, so a stray driver cannot pin a promise.")
                if not exists(pin):
                    failures.append(f"{pid}: devnet driver {pin} does not exist.")
                    continue
                src = read_test(pin)
                if assertion not in src:
                    failures.append(
                        f"{pid}: devnet driver {pin} does not contain its named assertion.\n"
                        f"         looked for: {assertion!r}\n"
                        f"         A pin whose assertion moved is a pin asserting nothing.")
                counts.setdefault('devnet', 0)
                counts['devnet'] += 1
                continue
            if '/' in pin or ':' in pin:
                die(f"{pid}: pin {pin!r} must be a BARE filename inside {TEST_DIR} — no directory, "
                    f"no line range. Both shapes appear in the mapping pass and both break the "
                    f"path join silently.")
            if not exists(pin):
                failures.append(f"{pid}: pinning test {pin} does not exist.")
                continue
            if pin.endswith('-must-fail'):
                if pin not in runs['mustfail']:
                    failures.append(
                        f"{pid}: {pin} exists but is NOT in the MUSTFAIL manifest — it is never\n"
                        f"         run, so it cannot pin anything. Name it in run-tests.sh.")
            elif re.sub(r'\.repl$', '', pin) not in runs['stems']:
                failures.append(
                    f"{pid}: {pin} exists but is named in NO runner manifest (SUITES, PROBES,\n"
                    f"         IND_PROBES) — it is never run, so it cannot pin anything.")
            src = read_test(pin)
            if assertion not in src:
                failures.append(
                    f"{pid}: {pin} does not contain its named assertion.\n"
                    f"         looked for: {assertion!r}\n"
                    f"         A pin whose assertion moved is a pin asserting nothing.")
            # 🔴 AND THE ASSERTION MUST BE LIVE CODE, NOT A COMMENT. The containment check above
            # is satisfied by a string sitting in a comment, which is how P-078 stayed ✅ PROVEN
            # for weeks against an assertion the suite had DELETED — the quoted string survived
            # in the comment EXPLAINING the deletion. A pin that reads its own obituary is worse
            # than no pin, because it renders a ✅ on the founder page.
            #
            # 🔴 MUST-FAIL FIXTURES ARE EXEMPT, AND THAT IS NOT A LOOPHOLE. Their expected error
            # is registered in run-tests.sh's MUSTFAIL map and asserted from OUTSIDE, on the exit
            # code AND the error text, because a failing module `load` is a compile-time abort
            # that `expect-failure` cannot catch (measured, a later change). So the string legitimately
            # appears only in the fixture's header comment, and flagging it would be a FALSE
            # POSITIVE — measured: this check flagged P-127 on exactly that basis before the
            # exemption existed, and "re-anchoring" it would have broken a correct, stronger pin.
            # A gate that cries wolf trains the reader to skip it.
            elif not pin.endswith('.repl-must-fail') and not any(
                    assertion in ln for ln in src.splitlines()
                    if not ln.lstrip().startswith(';')):
                failures.append(
                    f"{pid}: {pin} contains its assertion ONLY IN A COMMENT.\n"
                    f"         looked for: {assertion!r}\n"
                    f"         A commented-out or deleted assertion cannot fail, so this row's\n"
                    f"         PROVEN status rests on nothing. Re-anchor it to a live assertion,\n"
                    f"         or change the promise if the behaviour really moved.")
        else:
            if pin or assertion:
                die(f"{pid}: status {status} must not name a pin ({pin!r}/{assertion!r}) — "
                    f"only PROVEN is pinned, and a half-filled row reads as stronger than it is")

    # 5. THE PAGE AND THE MANIFEST MUST AGREE ON HOW MANY MARKS EXIST.
    # Asserted the way SUITES is asserted — want vs have, per status, with the difference named.
    # This is what catches a hand-written mark nobody derived, and an OWNER row silently dropped.
    if any(owner.values()) and not had_legend:
        die(f"{DOC} has OWNER promises but no {LEGEND_OPEN} … {LEGEND_CLOSE} block. The legend "
            f"explains the marks to the founder and must be delimited so its own marks are not "
            f"counted as promises.")
    if any(owner.values()) and cspan is None:
        die(f"{DOC} has OWNER promises but no {CALLER_OPEN} … {CALLER_CLOSE} block. The caller "
            f"legend spans MORE THAN ONE LINE and must be delimited as a REGION — excluding it by "
            f"matching its first line left the second line eligible, and a mark landed there.")

    # 6. NO STATUS MARK MAY TOUCH A CALLER MARK, IN EITHER ORDER.
    # `✅ 🔴 disburse-tranche` reads as one compound symbol, and the two vocabularies mean
    # unrelated things (proven vs admin-only). Both orders are checked because the previous
    # self-check only compared status marks to OTHER STATUS MARKS and saw none of these.
    for m in re.finditer(f'([{_SM}]\\s*[{CALLER_MARKS}])|([{CALLER_MARKS}]\\s*[{_SM}])', body):
        failures.append(
            f"a status mark touches a caller mark ({m.group(0)!r}) on line "
            f"{body[:m.start()].count(chr(10)) + 1} of the page body.\n"
            f"         {CALLER_MARKS} say WHO MAY CALL; {_SM} say whether a promise is proven.\n"
            f"         Side by side they read as one symbol. Separate them or re-anchor.")

    for status, (mark, _) in STATUS.items():
        want, have = owner[status], body.count(mark)
        if want != have:
            failures.append(
                f"mark count for {status} ({mark}): manifest says {want} OWNER row(s), the page "
                f"shows {have}.\n"
                f"         A page with MORE marks than the manifest has a hand-written status.\n"
                f"         A page with FEWER has a promise that was dropped without its mark.")

    return failures, {'status': counts, 'owner': owner}


# --- SELF-TEST ----------------------------------------------------------------------
# The founder asked for two branches to be PROVEN RED. A gate whose failure path has never
# been observed is a gate that may not have one — this repo has shipped exactly that twice.
_CALLER = (f"{CALLER_OPEN}\n"
           "\U0001F7E2 anyone \u00b7 \U0001F535 holder \u00b7 \U0001F534 admin \u00b7\n"
           "\u2699\ufe0f the contract itself only\n"
           f"{CALLER_CLOSE}\n")
_PLEG = (f"{LEGEND_OPEN}\n\u2705 proven \u00b7 \U0001F7E1 unpinned \u00b7 "
         "\U0001F4CB procedure \u00b7 \u26D4 not built\n"
         f"{LEGEND_CLOSE}\n")
_DOC_OK = _CALLER + _PLEG + (
    "\n- \U0001F7E1 a weak promise that is visible.\n"
    "\n- a strong promise that is tracked.\n"
)
_RUNS = {'stems': {'x'}, 'mustfail': {'y.repl-must-fail'}}
_ROWS_OK = [
    ('P-1', 'a weak promise nobody pinned', 'a weak promise', 'BUILT-UNPINNED', 'OWNER', '', ''),
    ('P-2', 'a strong promise with a pin', 'a strong promise', 'PROVEN', 'TRACKED', 'x.repl', 'ASSERT'),
]


def _harness(rows, doc, total=None):
    """Run audit() against fakes. Returns (failures, error) — never touches the tree."""
    global EXPECTED_TOTAL
    keep = EXPECTED_TOTAL
    EXPECTED_TOTAL = len(rows) if total is None else total
    try:
        return audit(rows, doc, _RUNS, lambda p: True, lambda p: 'ASSERT'), None
    except Tooling as e:
        return None, str(e)
    finally:
        EXPECTED_TOTAL = keep


def self_test():
    """Every branch here must behave as named, or the gate refuses to run at all."""
    checks = []

    # control — the shape the gate is supposed to accept must actually pass, or every
    # 'FAIL' below proves nothing (a gate that always fails is as broken as one that never does)
    (res, err) = _harness(list(_ROWS_OK), _DOC_OK)
    checks.append(('control: a valid manifest passes', res is not None and not res[0], err))

    # BRANCH 1 (founder-requested): demote an unpinned promise to TRACKED → must FAIL
    rows = [('P-1', 'a weak promise nobody pinned', 'a weak promise', 'BUILT-UNPINNED', 'TRACKED', '', ''), _ROWS_OK[1]]
    (res, err) = _harness(rows, _DOC_OK)
    hit = res is not None and any('may NOT be TRACKED' in f for f in res[0])
    checks.append(('branch 1: BUILT-UNPINNED demoted to TRACKED is rejected', hit, err))

    # the same rule must hold for the other two weak statuses, or it is a special case not a rule
    for st in ('PROCEDURE', 'NOT-BUILT'):
        rows = [('P-1', 'a weak promise nobody pinned', 'a weak promise', st, 'TRACKED', '', ''), _ROWS_OK[1]]
        (res, err) = _harness(rows, _DOC_OK)
        hit = res is not None and any('may NOT be TRACKED' in f for f in res[0])
        checks.append((f'branch 1: {st} demoted to TRACKED is rejected', hit, err))

    # BRANCH 2 (founder-requested): silently drop a row → must FAIL.
    # An OWNER drop leaves its mark orphaned on the page; a TRACKED drop leaves no mark at
    # all, which is why EXPECTED_TOTAL exists. Both are proven here.
    (res, err) = _harness([_ROWS_OK[1]], _DOC_OK, total=2)
    checks.append(('branch 2a: dropping a TRACKED row trips EXPECTED_TOTAL',
                   res is None and err is not None and 'EXPECTED_TOTAL' in err, None))

    # Dropping the OWNER row is what strands its mark. (Dropping the TRACKED row strands
    # nothing — it never rendered — which is precisely why 2a needs EXPECTED_TOTAL and why
    # the two branches are not interchangeable.)
    (res, err) = _harness([_ROWS_OK[1]], _DOC_OK, total=1)
    hit = res is not None and any('mark count for' in f for f in res[0])
    checks.append(('branch 2b: dropping an OWNER row strands its mark', hit, err))

    # a hand-written mark the manifest never derived
    (res, err) = _harness(list(_ROWS_OK), _DOC_OK + '\n- ✅ **hand-written**\n')
    hit = res is not None and any('hand-written status' in f for f in res[0])
    checks.append(('extra: a hand-written mark is caught', hit, err))

    # an empty manifest is a failure, not a pass
    (res, err) = _harness([], _DOC_OK, total=0)
    checks.append(('extra: an empty manifest fails', res is not None and bool(res[0]), err))

    # a PROVEN row whose assertion is absent
    rows = [_ROWS_OK[0], ('P-2', 'a strong promise with a pin', 'a strong promise', 'PROVEN', 'TRACKED', 'x.repl', 'MISSING')]
    (res, err) = _harness(rows, _DOC_OK)
    hit = res is not None and any('does not contain its named assertion' in f for f in res[0])
    checks.append(('extra: a moved assertion is caught', hit, err))

    # a PROVEN row whose pin is not in SUITES
    rows = [_ROWS_OK[0], ('P-2', 'a strong promise with a pin', 'a strong promise', 'PROVEN', 'TRACKED', 'unrun.repl', 'ASSERT')]
    (res, err) = _harness(rows, _DOC_OK)
    hit = res is not None and any('named in NO runner manifest' in f for f in res[0])
    checks.append(('extra: a pin that never runs is caught', hit, err))

    # the old mapping-format pin shapes must be refused by shape
    for bad in ('pact/test/x.repl', 'x.repl:12-34'):
        rows = [_ROWS_OK[0], ('P-2', 'a strong promise with a pin', 'a strong promise', 'PROVEN', 'TRACKED', bad, 'ASSERT')]
        (res, err) = _harness(rows, _DOC_OK)
        checks.append((f'extra: pin shape {bad!r} is refused',
                       res is None and err is not None and 'BARE filename' in err, None))

    # --- PLACEMENT (founder, round two). The previous self-checks tested status-vs-status
    # adjacency and line-start. Both are PROXIES for the properties actually wanted, and both
    # passed while the page carried 7 status/caller adjacencies, 24 mid-sentence marks and a
    # mark inside the caller legend. These test the real properties.

    # (1) a mark on the WRAPPED SECOND LINE of a paragraph does not begin a sentence
    doc = _CALLER + _PLEG + ("\n- a sentence that wraps across\n"
                             "  \U0001F7E1 a weak promise on the next line.\n"
                             "\n- a strong promise that is tracked.\n")
    (res, err) = _harness(list(_ROWS_OK), doc)
    hit = res is not None and any('does not BEGIN a sentence' in f for f in res[0])
    checks.append(('placement: a mark on a wrapped continuation line is rejected', hit, err))

    # the same shape at a genuine sentence start must PASS, or the check is just "reject wraps"
    doc = _CALLER + _PLEG + ("\n- a sentence that wraps across\n"
                             "  and ends here.\n"
                             "\n- \U0001F7E1 a weak promise that is visible.\n"
                             "\n- a strong promise that is tracked.\n")
    (res, err) = _harness(list(_ROWS_OK), doc)
    checks.append(('placement: control — a real sentence start passes',
                   res is not None and not res[0], err))

    # (2) a status mark touching a caller mark, IN EITHER ORDER
    for order, extra in (('status,caller', "\n> ✅ \U0001F534 unrelated.\n"),
                         ('caller,status', "\n> \U0001F534 ✅ unrelated.\n")):
        (res, err) = _harness(list(_ROWS_OK), _DOC_OK + extra)
        hit = res is not None and any('touches a caller mark' in f for f in res[0])
        checks.append((f'placement: status/caller adjacency ({order}) is rejected', hit, err))

    # (3) an anchor INSIDE the caller legend — including its SECOND line, which is the one the
    # first fix left eligible
    for where, anchor in (('line 1', 'holder'), ('line 2', 'the contract itself only')):
        rows = [('P-1', 'a weak promise about ' + anchor, anchor, 'BUILT-UNPINNED', 'OWNER', '', ''), _ROWS_OK[1]]
        (res, err) = _harness(rows, _DOC_OK)
        hit = res is not None and any('INSIDE the caller legend' in f for f in res[0])
        checks.append((f'placement: an anchor in the caller legend ({where}) is rejected', hit, err))

    # the caller legend must be DELIMITED at all
    doc = _PLEG + "\n- \U0001F7E1 a weak promise that is visible.\n\n- a strong promise that is tracked.\n"
    (res, err) = _harness(list(_ROWS_OK), doc)
    checks.append(('placement: an undelimited caller legend is a tooling failure',
                   res is None and err is not None and 'caller-legend' in err, None))

    # (4) the mark must be ADJACENT, not merely nearby — the ±220 window this replaced would
    # have passed this document
    doc = _CALLER + _PLEG + ("\n- \U0001F7E1 something else entirely on this line.\n"
                             "\n- a weak promise that is visible.\n"
                             "\n- a strong promise that is tracked.\n")
    (res, err) = _harness(list(_ROWS_OK), doc)
    hit = res is not None and any('immediately precedes' in f for f in res[0])
    checks.append(('placement: a nearby-but-not-adjacent mark is rejected', hit, err))

    # (5) CHECK 4 — an anchor that does not state its promise. This is the ONLY check that would
    # have caught P-034 (anchored in the caller legend) and P-038 (a CAN promise anchored to the
    # "cannot" label): both were well-formed sentence starts pointing at the wrong sentence.
    rows = [('P-1', 'awards are paid in KDA and never expire', 'a weak promise',
             'BUILT-UNPINNED', 'OWNER', '', ''), _ROWS_OK[1]]
    (res, err) = _harness(rows, _DOC_OK)
    hit = res is not None and any('does not appear to state its promise' in f for f in res[0])
    checks.append(('anchor: a promise anchored to an unrelated sentence is caught', hit, err))

    # control — a legitimate anchor must NOT trip it, or the check is just noise
    (res, err) = _harness(list(_ROWS_OK), _DOC_OK)
    checks.append(('anchor: control — a matching anchor passes',
                   res is not None and not res[0], err))

    # an anchor made only of stopwords must FAIL, not skip the check
    rows = [('P-1', 'awards never expire once earned', 'who from, who to, how',
             'BUILT-UNPINNED', 'OWNER', '', ''), _ROWS_OK[1]]
    (res, err) = _harness(rows, _CALLER + _PLEG +
                          "\n- \U0001F7E1 who from, who to, how many.\n"
                          "\n- a strong promise that is tracked.\n")
    hit = res is not None and any('no content words' in f for f in res[0])
    checks.append(('anchor: an anchor of only stopwords is rejected', hit, err))

    # (6) a mark in a table row's FIRST column, where the caller glyph and function name live
    doc = (_CALLER + _PLEG +
           "\n| \U0001F7E1 a weak promise | what it takes | does something. |\n"
           "\n- a strong promise that is tracked.\n")
    rows = [('P-1', 'a weak promise nobody pinned', 'a weak promise', 'BUILT-UNPINNED',
             'OWNER', '', ''), _ROWS_OK[1]]
    (res, err) = _harness(rows, doc)
    hit = res is not None and any('FIRST column' in f for f in res[0])
    checks.append(('anchor: a mark in a table\'s first column is rejected', hit, err))

    # control — the SAME promise in a later column of the same table is fine, which is what
    # makes a table-cell anchor legal at all
    doc = (_CALLER + _PLEG +
           "\n| \U0001F7E2 `fn` | what it takes | \U0001F7E1 a weak promise that is visible. |\n"
           "\n- a strong promise that is tracked.\n")
    (res, err) = _harness(rows, doc)
    checks.append(('anchor: control — a later-column table cell is allowed',
                   res is not None and not res[0], err))

    bad = [(name, err) for name, ok, err in checks if not ok]
    for name, ok, _ in checks:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if bad:
        print("  SELF-TEST FAILED — the gate's own failure branches do not behave as named.")
        for name, err in bad:
            print(f"    {name}: {err or 'did not produce the expected failure'}")
        return False
    return True


def main():
    argv = sys.argv[1:]
    if '--self-test' in argv:
        print("== promise gate: self-test ==")
        return 0 if self_test() else 2

    print("== promise gate ==")
    if not self_test():
        return 2

    if not os.path.isfile(DOC):
        die(f"{DOC} not found — the tree's shape changed")

    doc = read(DOC)
    runs = runner_manifests(read(SUITE_RUNNER))
    failures, counts = audit(
        PROMISES, doc, runs,
        lambda pin: os.path.isfile(os.path.join(
            DEVNET_DIR if pin.endswith('.ts') else TEST_DIR, pin)),
        lambda pin: read(os.path.join(
            DEVNET_DIR if pin.endswith('.ts') else TEST_DIR, pin)),
    )

    for f in failures:
        print(f"  FAILED {f}")

    if counts:
        total = sum(counts['status'].values())
        shown = sum(counts['owner'].values())
        summary = ' · '.join(f"{STATUS[k][0]} {counts['status'][k]} {k.lower()}"
                             for k in STATUS if counts['status'][k])
        print(f"  {total} promises checked — {summary}")
        print(f"  {shown} rendered on the page (OWNER) · {total - shown} verified but not "
              f"rendered (TRACKED, all PROVEN by rule)")
    print("  LIMITS: this proves a pin EXISTS, RUNS and CONTAINS its assertion. It does NOT prove")
    print("          the assertion is strong enough (that is a recorded hand mutation), and it")
    print("          cannot demand a promise nobody wrote.")
    if failures:
        print("  RESULT: FAIL — fix the page or the module, never this gate.")
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Tooling as e:
        print(f"  TOOLING FAILURE — {e}")
        sys.exit(2)
