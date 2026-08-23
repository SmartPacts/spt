#!/usr/bin/env bash
# Run the SPT REPL test suites (devnet-independent regression).
# Each suite (load "setup.repl") loads coin + the 3 modules, then asserts behavior.
set -euo pipefail
cd "$(dirname "$0")"
fail=0

# --- a later change: SAY WHICH GATE FAILED, NOT JUST THAT ONE DID ----------------------------
# 🔴 THIS EXISTED BECAUSE OF A MEASURED BLIND SPOT, NOT AS TIDYING. There are 42 `fail=1`
# sites in this file and every one of them printed the same two words — `SUITE FAILURE` —
# so a run with ONE known failure and a run with a known failure PLUS A NEW REGRESSION were
# byte-identical at the end of the output. a later change made that live rather than theoretical:
# the deploy-budget gate is RED for the whole branch by design (the artifact outgrew its
# node measurement and the honest fix is one node run at the END, not a raised number), so
# three more module steps would each have landed against a terminal that already said
# SUITE FAILURE. the project notes: a check that always fails and one that never fails are the
# same defect.
#
# The gate itself is NOT weakened — every `fail=1` still fails the run and the exit code is
# unchanged. All this adds is the NAME, so "1 gate failed, the one I expect" is
# distinguishable at a glance from "2 gates failed".
#
# Mechanism: each gate prints `== <name> ==` before running and `  FAILED` when it trips.
# Output is teed, and the summary reports the header nearest above each FAILED line. That
# keeps the change to two places instead of editing 42 call sites, each of which would have
# been a chance to miss one — and a missed site would produce a failure that fails SILENTLY
# in the summary, which is worse than the problem being fixed.
_GATELOG="$(mktemp -t spt-gates.XXXXXX)"
trap 'rm -f "$_GATELOG"' EXIT
exec > >(tee "$_GATELOG") 2>&1

# --- a later change: THE DEPLOY ARTIFACT IS EXACTLY TWO MODULES -------------------------
# Founder, 2026-08-06: "remove everything from scope other than the spt and launch."
# A scope decision that nothing enforces drifts back — this repo has carried a whole NFT
# marketplace, nine casino drivers and 24 spike files inside a two-module artifact.
#
# a separate gas-sponsorship module is IN the repo and OUT of the artifact (a later amendment defers it
# from the first deployment). Its suites keep running — rot is worse than surface — but it
# is not deployed with these two and is not in the next audit's scope. That distinction is
# the reason this check names an ARTIFACT set and a REPO set separately instead of just
# counting files: "three modules exist" and "three modules ship" are different claims, and
# conflating them is what put a marketplace in the deploy train's repo in the first place.
printf '== deploy artifact is exactly SPT + SPT-launch ==\n'
ARTIFACT=(SPT SPT-launch)          # ships
REPO_EXTRA=()                        # nothing here is outside the artifact
# the design record (founder, 2026-08-07): WHERE each artifact module ships. Membership and
# topology are different claims — the sale is IN the artifact and deploys to the HUB
# ONLY. The ops-deploy gate compares runbook.ts's DEPLOY_MODULES topology column
# against this manifest; widening the sale back to every chain (or narrowing tokens)
# fails the suite until the decision is re-signed. Proven RED by a deliberate
# wrong-topology mutation (a later change report §D1).
TOPOLOGY="SPT=all,SPT-launch=hub"
expected=$(printf '%s\n' "${ARTIFACT[@]}" "${REPO_EXTRA[@]}" | sort)
actual=$(ls ../modules/*.pact 2>/dev/null | xargs -r -n1 basename | sed 's/\.pact$//' | sort)
if [ -z "$actual" ]; then
  # A check that inspected zero items is a FAILURE, never a pass.
  echo "  FAILED — no modules found in ../modules; this check inspected nothing"; fail=1
elif [ "$actual" != "$expected" ]; then
  echo "  FAILED — the module set moved. A new module here is a SCOPE decision, not a file:"
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/    /' || true
  echo "           If it SHIPS, add it to ARTIFACT and give it frozen-state coverage"
  echo "           (fixture + enumeration + upgrade-refused) before this passes again."
  echo "           If it does NOT ship, add it to REPO_EXTRA and say why, here."
  fail=1
else
  echo "  artifact: ${ARTIFACT[*]}   in-repo, not shipped: ${REPO_EXTRA[*]}"
fi

# --- a later change: THE REMOVED SCOPE STAYS REMOVED -----------------------------------
# Deleting files is a one-time tidy; this is what makes it a decision. Each path below was
# removed to another repo that now OWNS it, and re-creating one here re-creates the exact
# failure this item existed to fix: a second editable copy, which is how the hardened
# smartpacts-gallery.pact ended up in the repo that never deploys it while both real gallery
# repos kept the weak SPEND cap for weeks.
#
# It greps TRACKED files only (`git ls-files`), so a scratch file or an untracked experiment
# never trips it — only something committed.
printf '== removed scope has not drifted back ==\n'
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  SKIPPED — not a git checkout (this check needs the tracked-file list)"
else
  drift=$(git -C ../.. ls-files | grep -E '^(pact/spike/|spike-harness/|pact/modules/smartpacts-gallery|pact/test/smartpacts-gallery|test/harness/src/(casino-|gallery-devnet))' || true)
  n=$(printf '%s' "$drift" | grep -c . || true)
  if [ "$n" != "0" ]; then
    echo "  FAILED — $n tracked file(s) re-entered the removed scope:"
    printf '%s\n' "$drift" | sed 's/^/    /'
    echo "           gallery -> SmartPacts/private-gallery · casino -> SmartPacts/casino-private."
    echo "           Those repos OWN these; a copy here is a SECOND editable copy, not a backup."
    fail=1
  else
    echo "  gallery, casino and the spikes are still owned elsewhere"
  fi
fi

# --- TEST-INTEGRITY GATE: 2-argument expect-failure (a later change) -----------------
# A 2-arg `(expect-failure "doc" (expr))` matches ANY failure, so it cannot tell a
# correct refusal from a malformed test. Measured here three times: a form that began
# passing on an ARITY error (a later change), one that never entered the function it named
# (a later change), and — the reason this check exists — a NEW one added to
# a probe kept out of this repo AFTER the defect had been formally recorded, because
# nothing in the gate could see it. a later change converted 82; this stops the 83rd.
#
# The static check catches only the two EMPTY-STRING cases; the arity case needs
# paren- and string-aware argument counting, which is why this is Python and not awk
# (this repo's awk check shipped a false negative AND a false positive, and one copy
# exited 0 over zero files).
#
# FAILS CLOSED. No python3 => the gate FAILS; it never skips. "Skip when the tool is
# missing" is the false-clean pattern that has bitten this repo repeatedly. The
# detector also self-tests before it scans anything and exits 2 if it cannot find
# forms it is known to contain, so a clean result is never reported by a broken
# scanner. Exit 1 = forms found, exit 2 = tooling failure; both are failures here.
printf '== 2-arg expect-failure detector ==\n'
if ! command -v python3 >/dev/null 2>&1; then
  echo "  FAILED — python3 not found. This gate FAILS CLOSED: an unrunnable check is"
  echo "           not a passed check. Install python3 or fix PATH."
  fail=1
elif python3 ../../.github/scripts/expect-failure-arity.py; then
  :
else
  echo "  FAILED — see above. Convert each to the 3-arg form with the error string the"
  echo "           module ACTUALLY produces, captured from a run (never guessed)."
  fail=1
fi

# --- a later change: THE ENUMERATED FUNCTION SET IS COMPLETE ---------------------------
# smartpacts-frozen-invariant.repl gives EVERY public function of both modules a disposition
# (exercised frozen, or not-runnable with a reason). An enumeration is only honest while it
# matches the code, and the REPL cannot grep its own source — so the mechanical half lives
# here: re-count the real definitions and fail if they have moved.
#
# A function added without a disposition is an UNTESTED function whose absence from the
# freeze proof nobody would notice. That is precisely the shape of an internal review a finding.
# If you add or remove a function: update BOTH numbers here AND the disposition list in
# smartpacts-frozen-invariant.repl §0/§2/§3. Failing this check is the intended prompt to do so.
printf '== frozen-invariant enumeration is complete ==\n'
sh_fn=$(grep -cE '^[[:space:]]*\(defun '   ../modules/SPT.pact || true)
sh_dp=$(grep -cE '^[[:space:]]*\(defpact ' ../modules/SPT.pact || true)
ip_fn=$(grep -cE '^[[:space:]]*\(defun '   ../modules/SPT-launch.pact || true)
ip_dp=$(grep -cE '^[[:space:]]*\(defpact ' ../modules/SPT-launch.pact || true)
# 76 -> 92 (a later change / the design record): the sixteen record-date functions. Every one is dispositioned
# in smartpacts-frozen-invariant.repl §6, and THREE of them are dispositioned there for the
# an internal review a finding reason rather than for completeness: `schedule-snapshot` and `cancel-snapshot`
# are ADMIN-gated and `advance-snapshot` WRITES, so if any died at the freeze a frozen chain
# could never seal another record date — and since the design record makes a sealed record date a
# PRECONDITION of `declare-round`, the whole award subsystem would be dead there forever.
# 74 -> 76 (a later change): `get-round` AND `get-rounds-applied` added. It is NOT a convenience getter — its ABSENCE was a
# freeze defect (an internal review a finding): the per-round schedule was reachable only through module
# admin, and GOVERNANCE enforces (not FROZEN-MODULE) before the keyset check, so after the
# freeze the operator runbook's MANDATORY --verify-rounds step could never run again. Its freeze disposition is
# EXERCISED FROZEN on BOTH branches in smartpacts-frozen-invariant.repl §2.
# 92 -> 94 / 14 -> 16 (a later change / the design record part 2): the two settable limits add a reader and a
# governance setter each — get-runway/set-runway and get-min-price/set-min-price. All four are
# dispositioned in smartpacts-frozen-invariant.repl §3, and the two SETTERS are there for the
# an internal review a finding reason, not for completeness: the design record says a settable limit stays settable
# FOREVER, so a setter that died at the freeze would leave the limit frozen at whatever value
# it happened to hold — a defconst with extra steps. They take ADMIN-GOV, never GOVERNANCE.
# 94 -> 95 (a later change / the design record): `enforce-beneficiary-address`, the address-only half of the
# beneficiary chain. The founder ceremony receives no guard now, so the checks that need only
# an address had to become separately callable. Dispositioned in smartpacts-frozen-invariant
# §3, exercised frozen on BOTH branches (accept and refuse).
# 95 -> 96 (a later change): `DISBURSE-mgr`, the @managed manager that makes the disbursement amount a
# real spending limit rather than a label. Dispositioned in smartpacts-frozen-invariant's
# enumeration BEFORE this count moved, and exercised frozen by §2 — which spends an approved
# budget and then proves the SAME frozen module refuses a second call. Its freeze property is
# not "it still runs" but "the LIMIT still binds".
if [ "$sh_fn" != "98" ] || [ "$sh_dp" != "1" ] || [ "$ip_fn" != "17" ] || [ "$ip_dp" != "0" ]; then
  echo "  FAILED — the module function set moved and the freeze enumeration is now incomplete:"
  echo "           SPT defun=$sh_fn (want 98) defpact=$sh_dp (want 1)"
  echo "           SPT-launch    defun=$ip_fn (want 17) defpact=$ip_dp (want 0)"
  echo "           Give every new function a disposition in smartpacts-frozen-invariant.repl,"
  echo "           then update these counts. Do NOT just update the counts."
  fail=1
else
  # \U0001f534 DERIVED, NEVER HAND-WRITTEN. This line read "tokens 95 defun" for as long as the
  # check above enforced 96 — a green message that did not describe what was measured, found by
  # an external reviewer rather than by anything here. A gate that reports a number it did not
  # compute is the same defect class as a check that inspects zero items.
  echo "  tokens $sh_fn defun + $sh_dp defpact, launch $ip_fn defun + $ip_dp defpact — all dispositioned"
fi

# --- NO TABLE READ REACHES AN ENFORCE, EVEN THROUGH A HELPER --------------------
# A table read inside an `enforce` condition evaluates read-only on upstream-lineage nodes and
# aborts; the REPL allows it everywhere, so no REPL test can fail. A cold red-team found one
# violation that had survived eighteen reviews because the read hid behind a ONE-LINE helper —
# invisible to `grep '(enforce (.*(read'`. This resolves one level of indirection. It self-tests
# first and refuses to run if it cannot find a synthetic case.
echo "== no table read reaches an enforce (helper indirection resolved) =="
if (cd ../.. && python3 .github/scripts/enforce-read-indirection.py); then :; else fail=1; fi

# --- THE PRODUCTION TIME CONSTANTS ARE THE PRODUCTION ONES ----------------------
# 🔴 test/scripts/scale-time-for-devnet.py emits a TIME-SCALED build so governance can be run
# end-to-end on a node in minutes instead of the five days MIN-REVIEW-GAP + MIN-PROPOSAL-DURATION
# actually require (an internal review's largest named gap). That scaled build must NEVER become the
# artifact. The scaler writes to stdout and never touches the tree — this gate is the other half:
# it asserts the tree still carries the REAL values, so a scaled module cannot be committed by
# accident or left behind after a devnet session.
# It also FAILS CLOSED if a constant is renamed or moved, which is the case where a silent
# mismatch between this gate and the scaler would matter most.
echo "== the production governance time constants are unscaled =="
tc_fail=0
while IFS='|' read -r tc_name tc_want; do
  tc_got="$(grep -oE "\(defconst ${tc_name} [0-9]+\.?[0-9]*\)" ../modules/SPT.pact | head -1)"
  if [ -z "$tc_got" ]; then
    echo "  FAILED — ${tc_name} not found at all; the scaler and this gate now disagree with the module"
    tc_fail=1
  elif [ "$tc_got" != "(defconst ${tc_name} ${tc_want})" ]; then
    echo "  FAILED — ${tc_name} is ${tc_got}, want (defconst ${tc_name} ${tc_want})"
    echo "           If this is a TIME-SCALED devnet build, do not commit it. If the value changed"
    echo "           on purpose, update scale-time-for-devnet.py AND this gate in the same commit."
    tc_fail=1
  fi
done <<'TIMECONSTS'
MIN-REVIEW-GAP|172800.0
MIN-PROPOSAL-DURATION|259200
MAX-PROPOSAL-DURATION|1209600
MIN-RETRACT-LEAD|21600
MAX-RUNWAY|315360000
TIMECONSTS
if [ "$tc_fail" = "1" ]; then fail=1; else
  echo "  5 governance time constants checked — all at production values"
fi

# --- a later change addendum: THE FOUNDER-FACING DOC NAMES EVERY PUBLIC FUNCTION -------
# Founder review, 2026-08-08: docs/SPT-WHAT-IT-DOES.md was missing 39 of the 91 public
# functions (award-liability, max-rpt, credit-plan, the whole plumbing set…). That page
# exists so the founder can reconcile the contract against his vision WITHOUT reading Pact
# (Rule 15) — a function absent from it is invisible to exactly the review it exists for,
# and he is the one who caught it. Same shape as the frozen-invariant enumeration above:
# the doc is the human half, this re-grep is the mechanical half. A function added without
# a doc row fails here; the fix is a ROW IN THE DOC, never an edit to this check.
printf '== SPT-WHAT-IT-DOES.md names every public function ==\n'
if ! command -v python3 >/dev/null 2>&1; then
  echo "  FAILED — python3 not found. This gate FAILS CLOSED."
  fail=1
elif python3 - <<'PYEOF'
import re, sys
doc = open('../../docs/SPT-WHAT-IT-DOES.md').read()
bad, total = [], 0
for mod in ('SPT', 'SPT-launch'):
    src = open(f'../modules/{mod}.pact').read()
    names = re.findall(r'^\s*\(def(?:un|pact)\s+([A-Za-z0-9!?<>=_-]+)', src, re.M)
    # 🔴 a finding (an internal review): DEFCAPS WERE INVISIBLE TO THIS GATE. It matched `defun|defpact`
    # only, so all 41 defcap definitions — ADMIN-GOV, GOVERNANCE, TRANSFER, DEBIT and every
    # event cap — could be added, renamed or re-scoped with nothing here looking. The gate IS
    # the pin for founder-page completeness, and it did not look at the authorization surface.
    #
    # 🔴 SCOPE IS SIGNABLE CAPS ONLY, AND THAT IS A DECISION, NOT AN OVERSIGHT (founder,
    # 2026-08-14). Of 41 unique caps: 2 are @managed and 7 are admin gates — together these are
    # exactly the caps that can appear in a transaction's SIGNATURE LIST, i.e. what a Ledger
    # shows the founder when they approve something. That is precisely the surface a finding proved
    # was mis-stated, so it is the surface the founder page must describe.
    # EXCLUDED, with the reason recorded so the exclusion is not mistaken for coverage:
    #   * 24 @event caps — emitted, never signed. Several are DELIBERATELY forgeable and the
    #     modules say so; the page's answer to them is "read the table, not the stream".
    #   * 8 internal caps (CREDIT, DEBIT, the account guards, VOTE) — not reachable from a
    #     transaction at all, so a founder can never be asked to approve one.
    # The alternative — all 38 — was considered and declined: it would put mechanism on a page
    # whose stated problem (Rule 15) is being too long for a product manager to read.
    # 🔴 THE TAIL IS SLICED, NOT CAPTURED, AND THAT DISTINCTION IS THE WHOLE CHECK.
    # The first version of this gate used `(defcap\s+NAME)(.{0,400})` with re.findall. A
    # capture group CONSUMES, so every defcap sitting within 400 characters of the previous
    # one was skipped: it saw 21 of SPT's 41 defcaps and reported PASS, with
    # `ADMIN-OPS` — which sits immediately after `ADMIN-GOV` — among the invisible ones.
    # That is a finding's own defect reproduced inside the fix for a finding, and the same shape as the
    # `check-namespace.sh` regex that printed "checked: 3" while blind to a fourth literal.
    # `finditer` + an explicit slice cannot consume, so adjacency cannot hide a cap.
    # 🔴 THE TAIL IS THE DEFCAP FORM, NOT A FIXED NUMBER OF CHARACTERS (an internal review, a finding).
    # It used to be `src[m.end():m.end() + 400]`, and 400 was one character too few. MEASURED,
    # by offset of the classifying marker after the defcap name:
    #     TRANSFER 57 · FUND-AWARDS 70 · TRANSFER_XCHAIN 77 · ADMIN-GOV 136 · GOVERNANCE 157
    #     DISBURSE 257 · WITHDRAW-FUNDING 399 · WITHDRAW-PROCEEDS 399 · RECOVER-SURPLUS 419
    # RECOVER-SURPLUS — a gov-tier @managed capability that moves KDA OUT of the award pool —
    # was INVISIBLE to this gate, and the two at 399 were inside by ONE character, so any edit
    # to their docstrings would have dropped them out silently too. A window that happens to
    # fit today is not a check; it is a coincidence with a deadline.
    # Scanning to the close of the defcap's own s-expression removes the number entirely, so
    # the classifier sees exactly the form it is classifying however long the @doc grows.
    def _form_end(text, start):
        depth, i, n, instr = 0, start, len(text), False
        while i < n:
            c = text[i]
            if instr:
                if c == '\\': i += 2; continue
                if c == '"': instr = False
            elif c == '"': instr = True
            elif c == ';':
                j = text.find('\n', i); i = n if j < 0 else j; continue
            elif c == '(': depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0: return i + 1
            i += 1
        return n
    signable = []
    for m in re.finditer(r'^(\s*)\(defcap\s+([A-Za-z0-9!?<>=_-]+)', src, re.M):
        open_paren = m.start() + len(m.group(1))
        tail = src[m.end():_form_end(src, open_paren)]
        if '@managed' in tail or ('@event' not in tail and 'enforce-keyset' in tail):
            signable.append(m.group(2))
    # A module with defcaps but ZERO signable ones means the classifier stopped matching,
    # not that the module stopped having admin gates. Fail closed rather than pass blind.
    if re.search(r'^\s*\(defcap\s', src, re.M) and not signable:
        print(f'  FAILED — {mod}: defcaps exist but ZERO were classified signable; the'
              f' classifier is broken, not the module'); sys.exit(2)
    names += signable
    total += len(names)
    bad += [f'{mod}.{n}' for n in names if f'`{n}`' not in doc]
if total == 0:
    print('  FAILED — parsed ZERO functions; the checker is broken, not the doc'); sys.exit(2)
if bad:
    print(f'  FAILED — {len(bad)} public function(s) have no row in SPT-WHAT-IT-DOES.md:')
    for b in bad: print(f'    {b}')
    sys.exit(1)
print(f'  all {total} public functions appear in the founder-facing doc')
PYEOF
then
  :
else
  echo "  FAILED — see above. Add a plain-language row for each function to"
  echo "           docs/SPT-WHAT-IT-DOES.md (the plumbing table if it is internal)."
  fail=1
fi

# --- THE PROMISE GATE (Rule 14(c)) ----------------------------------------------
# THE SECOND HALF OF THE GATE ABOVE, and the more important half. That one proves every
# public function is NAMED on the founder page; it reads names, so a page can name every
# function and still describe them FALSELY. (This comment said "all 91 functions" while the
# gate itself printed 126 — do not re-introduce a hand-written count here; the gate derives it.) Audit #14's a finding was exactly that: a hand-written
# STRONG/PROVEN rating quoting an expression the module had already deleted, which no gate
# could contradict because nothing derived it. A CRITICAL sat behind a green rating for
# eleven audits.
#
# This gate derives every status mark on the page from a NAMED manifest, and for each PROVEN
# promise proves the pinning test EXISTS, IS ACTUALLY RUN (checked against all four runner
# manifests, not just SUITES), and CONTAINS its named assertion. It also fails when the page
# and the manifest disagree on how many marks exist — which is what catches a hand-written
# status and a silently dropped promise.
#
# It cannot prove an assertion is STRONG enough; that is a recorded hand mutation, and the
# gate prints that limit on every run rather than letting a green line oversell it.
printf '== founder-page promise gate ==\n'
if ! command -v python3 >/dev/null 2>&1; then
  echo "  FAILED — python3 not found. This gate FAILS CLOSED: an unrunnable check is"
  echo "           not a passed check. Install python3 or fix PATH."
  fail=1
elif python3 ../../.github/scripts/promise-gate.py; then
  :
else
  echo "           Fix the PAGE or the MODULE — never the gate. A promise whose pin moved is"
  echo "           a promise asserting nothing, and a weak status may never be hidden by"
  echo "           demoting it to TRACKED."
  fail=1
fi

# --- a later change: NO OPERATIONAL PATH MAY REACH `GOVERNANCE` ------------------------
# THE FREEZE INVARIANT, mechanically. `GOVERNANCE`'s body begins
# `(enforce (not FROZEN-MODULE) ...)` in EVERY module, so ANY function that acquires it —
# compose-capability, with-capability or require-capability — DIES THE DAY THAT MODULE IS
# FROZEN. Under the founder's definition (2026-08-05) freeze means "no more upgrades and
# nothing else", so an operation that stops working at freeze is a DEFECT, and a permanent,
# unfixable one: a frozen module cannot be upgraded to repair it.
#
# THIS IS THE CHECK THAT WOULD HAVE CAUGHT AUDIT #7 a finding ON ITS OWN. There, the gas station's
# `init` composed GOVERNANCE, so a frozen station could never be created on a new chain. It
# took an reviewer reading the code; no test existed that could fail. Audit #8 fixed it by
# composing REGISTRY-ADMIN instead — same keyset, deliberately no frozen gate — and that
# substitution is the PATTERN: if an operation needs authority that dies at freeze, give it a
# different gate with the SAME authority. Never weaken GOVERNANCE to make something work.
#
# The module header `(module SPT GOVERNANCE ...)` is the governance DECLARATION
# and is not an acquisition — it must not trip this. Only the three acquisition forms do.
#
# 🔴 a later change: THE GREP WAS ONE LITERAL SPACE, AND THAT IS A DEFECT, NOT A NIT.
# `grep -nE '\((compose|with|require)-capability \(GOVERNANCE'` matches only when
# exactly one space separates the two forms. TWO spaces, a line break (the natural
# outcome of formatting a long acquisition), or any earlier `;` on the line and the
# gate finds 0 hits and prints "every operation survives the freeze gate" — a check
# that cannot fail, over the invariant the whole freeze rests on. a later change recorded it
# as a latent hole; the whitespace- and comment-tolerant tokenizer this file already had
# for DML counting was never applied here. It is now (`cap_count`, same tokenizer — the DML
# side has since moved out entirely, into dml-manifest.py's `strip_comments`).
cap_count() {   # $1 = capability name, $2 = file — comment-stripped, whitespace-tolerant
  python3 - "$1" "$2" <<'PYEOF'
import re, sys
cap, path = sys.argv[1], sys.argv[2]
src = open(path).read()
out, i, n, instr = [], 0, len(src), False
while i < n:
    c = src[i]
    if instr:
        out.append(c)
        if c == '\\' and i + 1 < n: out.append(src[i+1]); i += 2; continue
        if c == '"': instr = False
        i += 1; continue
    if c == '"': instr = True; out.append(c); i += 1; continue
    if c == ';':
        while i < n and src[i] != '\n': i += 1
        continue
    out.append(c); i += 1
# 🔴 `\s*` BEFORE THE PAREN, NEVER `\s+` (CONFIRMATORY AUDIT #21, a finding). Pact needs no
# whitespace between the native and its argument: `(with-capability(GOVERNANCE) ...)` parses,
# loads and RUNS. With `\s+` this gate reported 0 acquisitions while exactly that form was
# planted in a public defun (`get-circulating`) — measured. This is the a later change freeze
# invariant, i.e. the mechanical guard against an internal review a finding, so a blind spot here is the
# whole gate.
print(len(re.findall(r'\(\s*(?:compose|with|require)-capability\s*\(\s*' + cap + r'\b', ''.join(out))))
PYEOF
}
printf '== no operational path reaches GOVERNANCE ==\n'
gov_n=0
gov_hits=""
for f in ../modules/*.pact; do
  n=$(cap_count GOVERNANCE "$f")
  gov_n=$((gov_n + n))
  [ "$n" != "0" ] && gov_hits="$gov_hits
  $f: $n acquisition(s)"
done
gov_files=$(ls ../modules/*.pact | wc -l)
if [ "$gov_files" -eq 0 ]; then
  # A check that inspected zero items is a FAILURE, never a pass.
  echo "  FAILED — no module files found; this check inspected nothing"; fail=1
elif [ "$gov_n" != "0" ]; then
  echo "  FAILED — $gov_n operational path(s) acquire GOVERNANCE and will DIE at freeze:"
  printf '%s\n' "$gov_hits" | sed 's/^/    /'
  echo "           Freeze means 'no more upgrades' and nothing else. Give the operation a"
  echo "           DIFFERENT gate with the same authority (the REGISTRY-ADMIN move, an internal review"
  echo "           a finding) — never weaken GOVERNANCE to make it work frozen."
  fail=1
else
  echo "  0 acquisitions across $gov_files module(s) — every operation survives the freeze gate"
fi

# --- a later change / the design record: DOES THE ARTIFACT STILL DEPLOY? -------------------------
# 🔴 THE GATE WHOSE ABSENCE WAS THE REAL DEFECT. `SPT` grew 6% past a HARD
# 150,000-gas deploy ceiling across TWO audited items and nothing went red, because nothing
# in this tree measured deploy cost. Cold a review found it by deploying on a node:
# 176,205 gas = 117.5%, and the ceiling is hard (150,000 accepted, 150,001 REJECTED at
# validation). Every other invariant here had a gate; the one deciding whether anything
# ships at all had none.
#
# It checks TWO things and NEVER extrapolates:
#   * the stripped artifact's size against the LAST NODE MEASUREMENT, failing the moment it
#     grows past its own evidence — the estate's last extrapolation was wrong by 24%, so the
#     correct response to a failure here is a NODE RUN, never a bigger number in the table;
#   * that stripping does not change the MODULE HASH, which is the entire safety argument
#     for deploying a build nobody read line-by-line (identical hash => identical semantics
#     => the audit of the reviewed source IS an audit of the deployed one).
# Re-measure with: cd test/harness && DEVNET_HOST=<node> npx tsx src/deploy-gas-devnet.ts
printf '== the artifact still deploys (the design record stripped build) ==\n'
if ! command -v python3 >/dev/null 2>&1; then
  echo "  FAILED — python3 not found. This gate FAILS CLOSED."
  fail=1
elif python3 ../../.github/scripts/deploy-budget.py --modules ../modules \
       --test-dir "$(pwd)" --verify-hash; then
  :
else
  echo "  FAILED — see above. If the artifact grew, RE-MEASURE ON A NODE and record the"
  echo "           new pair; never raise the recorded number to make this quiet. If the"
  echo "           HASH differs, the stripper changed the code — do not deploy."
  fail=1
fi

# --- THE DML SURFACE OF EVERY TABLE, ENUMERATED BY OWNING FUNCTION --------------
# the design record restored `credit` as the single CREDIT-gated balance-INCREASING writer, replacing
# four inlined copies. It restored ONE writer, not a licence to add more. The same question
# — WHO may write this table — decides the product for `tallies`, the solvency counters, the
# tranche locks and the sale config.
#
# 🔴 THREE MEASURED DEFECTS SHAPED THIS GATE, EACH FIXING THE ONE BEFORE IT.
#
# (1) IT COUNTED ONE OPERATOR (an internal review a finding). `(write accounts` was counted; `insert`
#     and `update` were not, so `(update accounts … "balance" …)` sailed through a gate whose
#     message said "one gated writer".
#
# (2) A COUNT CANNOT SEE RELOCATION (a later change a finding). Deleting the legitimate
#     `(update tallies …)` from `debit`'s release loop and planting one inside the
#     PERMISSIONLESS `close-proposal` kept the count at 3 and the gate printed "unchanged"
#     while the mutator set had changed. Add-only and delete-only went red; only relocation
#     was invisible — and relocation is what an attacker-shaped edit looks like. Hence a
#     MANIFEST naming each site's owning function.
#
# (3) 🔴 IT PINNED TWO TABLES OUT OF FOURTEEN (an internal review, a finding) — and a finding came with a
#     working demonstration, not an argument: a planted permissionless writer zeroing
#     `sum-pending` in the `state` table passed every suite and every correctness gate in
#     this tree. `state` was not special. Twelve tables had no pin at all, and pinning only
#     the one the finding named would have fixed the instance and left the class, which is
#     the mistake this file already records at a later change ("cover the set, not the instance").
#
# So one invocation now checks EVERY table in both artifact modules, and adds the assertion
# a per-table invocation structurally cannot make: COVERAGE — the pinned table set must EQUAL
# the module's `deftable` set, so a new table cannot arrive with an unpinned writer.
# The pins and the per-table rationale live in .github/scripts/dml-surface.json; the reason a
# table is pinned is printed WITH the failure, because that is when it is read.
# --- a later change: IS THE TREE STILL THE RECORDED BASELINE? --------------------------
# 🔴 THE LINK THAT DID NOT EXIST. `ops/mainnet-config.json` recorded both artifact module
# hashes, with a note saying they are the hashes an internal review must audit — and NOTHING
# READ IT. A recorded number no check compares against is a note, not a pin: the tree could
# stop being the recorded tree between any two commits and the only signal would be a human
# remembering. This estate has already lost a baseline that way — the a later change rename moved
# the tree off the last audited one, and no bless lineage survives a rename.
#
# It compares the MODULE HASH, not a file checksum, and that choice is load-bearing in both
# directions: comments and @doc are outside Pact's module hash (measured for the design record), so a
# checksum would go red on every comment edit and train the operator to re-pin without
# looking — while going GREEN for a dependency change that alters semantics.
#
# The gate also prints the recorded AUDIT STATUS every run, loudly when it is UNAUDITED,
# because the failure mode of a green line is being read as an audit. It is not one: it
# proves only that the tree still IS the tree that was recorded.
printf '== the artifact is still the recorded baseline ==\n'
if ! command -v python3 >/dev/null 2>&1; then
  echo "  FAILED — python3 not found. This gate FAILS CLOSED."
  fail=1
elif python3 ../../.github/scripts/artifact-baseline.py \
       --config ../../verification/artifact-baseline.json --modules ../modules --test-dir "$(pwd)"; then
  :
else
  echo "           RE-PINNING IS THE LAST STEP, NOT THE FIRST. Revert the change, or record"
  echo "           the new hashes AND reset audit_status to UNAUDITED in the SAME commit."
  fail=1
fi

printf '== DML surface of every table (named manifest + coverage) ==\n'
if ! command -v python3 >/dev/null 2>&1; then
  echo "  FAILED — python3 not found. This gate FAILS CLOSED."
  fail=1
elif python3 ../../.github/scripts/dml-manifest.py \
       --manifest ../../.github/scripts/dml-surface.json --root ../..; then
  :
else
  echo "           A mutator appearing, vanishing or MOVING BETWEEN FUNCTIONS is a design"
  echo "           change, not a manifest edit. An UNPINNED table is the a finding shape exactly:"
  echo "           the table exists, something writes it, and nothing in this tree looks."
  fail=1
fi

# --- FROZEN-MODULE fixtures (a later change, generalised to every module by a later change) ----
# The freeze claim is worthless unless it is exercised against a module actually compiled
# with FROZEN-MODULE=true. Each fixture is GENERATED from the real module and then diffed
# against the committed copy: it can never silently drift.
#
# a later change GENERALISED THIS FROM ONE MODULE TO THE SET. Until 2026-08-06 only
# SPT had a frozen fixture; SPT-launch had ZERO frozen-state coverage of
# the single property that defines freeze. That is the "cover the set, not the instance"
# failure applied to the invariant that matters most, and it is why an internal review a finding (a frozen
# gas station could never be created on a new chain) had to be found by a human reading code.
# a separate gas-sponsorship module is deliberately NOT here: a later amendment keeps it out of the first
# deployment, so it gets this same treatment before IT ships. That is a scope decision, not
# an oversight — do not read its absence as coverage.
#
# The footer is replaced because these copies are only ever loaded as an in-place UPGRADE
# over an initialised module, where re-running create-table aborts the tx.
gen_frozen() {   # $1 = module basename
  sed -e 's/(defconst FROZEN-MODULE false)/(defconst FROZEN-MODULE true)/' \
      -e "/^(if (read-msg 'upgrade)\$/,\$d" "../modules/$1.pact"
  echo ";; ---- FOOTER REPLACED BY run-tests.sh gen_frozen (upgrade-only fixture) ----"
  echo "(if (read-msg 'upgrade) [\"frozen fixture: no new tables\"] [\"frozen fixture: upgrade-only\"])"
}

# 🔴 a later change: THE BLESSED FREEZE FIXTURE, and why it must be GENERATED rather than written.
# The founder's rule is that freeze makes a module unupgradeable and NOTHING else — every defun
# and defpact keeps working. A plain defconst flip VIOLATES that between modules: freezing
# `SPT` changes its hash, `SPT-launch` is linked against the old one, and
# `launch.buy` — a public defun — dies with "hash not blessed". The fix is one `(bless <hash>)`
# line in the freeze source.
#
# 🔴 THAT LINE CANNOT BE WRITTEN BY HAND, EVER. Blessing a hash CHANGES the hash, so the value
# to bless is only knowable once the audited bytes are final — the freeze artifact is
# necessarily two lines off the audited build and both lie outside the audited hash. So the
# hash is DERIVED here, by loading the real module, exactly as the operator must derive it.
# A hand-typed hash would be stale the moment the module moved, and would fail LATE — after
# the freeze, which has no undo.
derive_hash() {  # $1 = module basename -> its module hash, by loading it
  local tmp; tmp="tmp-derive-$1.repl"
  { echo '(load "setup-noinit.repl")'
    echo "(print (at 'hash (describe-module \"n_48867b242317a0216a67f8c7ca26696b5878e0e3.$1\")))"
  } > "$tmp"
  pact "$tmp" 2>/dev/null | grep -oE '"[A-Za-z0-9_-]{43}"' | tr -d '"' | head -1
  rm -f "$tmp"
}

gen_frozen_blessed() {  # $1 = module basename, $2 = hash to bless
  sed -e 's/(defconst FROZEN-MODULE false)/(bless "'"$2"'")\n  (defconst FROZEN-MODULE true)/' \
      -e "/^(if (read-msg 'upgrade)\$/,\$d" "../modules/$1.pact"
  echo ";; ---- FOOTER REPLACED BY run-tests.sh gen_frozen_blessed (upgrade-only fixture) ----"
  echo "(if (read-msg 'upgrade) [\"frozen fixture: no new tables\"] [\"frozen fixture: upgrade-only\"])"
}

printf '== frozen-BLESSED SPT fixture (a later change) ==\n'
PRE_FREEZE_HASH=$(derive_hash SPT)
if [ -z "$PRE_FREEZE_HASH" ]; then
  echo "  FAILED — could not DERIVE the pre-freeze token hash. This gate FAILS CLOSED: a blessed"
  echo "           fixture built on a guessed hash would pass while proving nothing."; fail=1
else
  gen_frozen_blessed SPT "$PRE_FREEZE_HASH" > /tmp/spt-frozen-blessed-SPT.pact
  if ! grep -qF "(bless \"$PRE_FREEZE_HASH\")" /tmp/spt-frozen-blessed-SPT.pact; then
    echo "  FAILED — the bless line did not land in the fixture; the blessed path would be untested"; fail=1
  elif ! grep -qF '(defconst FROZEN-MODULE true)' /tmp/spt-frozen-blessed-SPT.pact; then
    echo "  FAILED — generator did not flip FROZEN-MODULE alongside the bless"; fail=1
  elif [ "${REGEN_FIXTURES:-0}" = "1" ]; then
    cp /tmp/spt-frozen-blessed-SPT.pact fixtures/frozen-blessed-SPT.pact
    echo "  REGENERATED fixtures/frozen-blessed-SPT.pact (blessing $PRE_FREEZE_HASH)"
  elif ! diff -u fixtures/frozen-blessed-SPT.pact /tmp/spt-frozen-blessed-SPT.pact; then
    echo "  FAILED — fixtures/frozen-blessed-SPT.pact is STALE vs the module."
    echo "           Re-run as: REGEN_FIXTURES=1 ./run-tests.sh"; fail=1
  else
    echo "  in sync, blessing $PRE_FREEZE_HASH"
  fi
fi

for M in SPT SPT-launch; do
  gen_frozen "$M" > "/tmp/spt-frozen-$M.pact"
  printf '== frozen-%s fixture ==\n' "$M"
  src_lines=$(wc -l < "../modules/$M.pact")
  fx_lines=$(wc -l < "/tmp/spt-frozen-$M.pact")
  # THREE independent checks, because the generator has a KNOWN HAZARD: its truncation is
  # line-anchored, and a second top-level branch opening the same way once truncated an entire
  # module into an EMPTY one — every frozen assertion silently vacuous. The flip check alone
  # happened to catch it that time; it is not guaranteed to, so the shape and size are checked
  # too. A fixture that inspected nothing must FAIL, never pass.
  if ! grep -qF '(defconst FROZEN-MODULE true)' "/tmp/spt-frozen-$M.pact"; then
    echo "  FAILED — generator did not flip FROZEN-MODULE; the freeze test would be vacuous"; fail=1
  elif ! grep -qF "(module $M GOVERNANCE" "/tmp/spt-frozen-$M.pact"; then
    echo "  FAILED — fixture has no module definition; the truncation ate the body"; fail=1
  elif [ "$fx_lines" -lt $(( src_lines * 8 / 10 )) ]; then
    echo "  FAILED — fixture is $fx_lines lines against a $src_lines-line source (<80%);"
    echo "           the line-anchored truncation cut too much and the freeze tests would be vacuous"
    fail=1
  elif [ "${REGEN_FIXTURES:-0}" = "1" ]; then
    cp "/tmp/spt-frozen-$M.pact" "fixtures/frozen-$M.pact"
    echo "  REGENERATED fixtures/frozen-$M.pact (REGEN_FIXTURES=1)"
  elif ! diff -u "fixtures/frozen-$M.pact" "/tmp/spt-frozen-$M.pact"; then
    echo "  FAILED — fixtures/frozen-$M.pact is STALE vs the module."
    echo "           Re-run as: REGEN_FIXTURES=1 ./run-tests.sh"; fail=1
  else
    echo "  in sync with ../modules/$M.pact ($fx_lines lines)"
  fi
done

# --- a later change: THE FREEZE ARTIFACT MUST SURVIVE STRIPPING UNCHANGED --------------------
# 🔴 THE FREEZE IS THE SECOND AND FINAL THING THAT EVER DEPLOYS, AND IT WAS THE ONLY ONE
# NEVER STRIPPED, NEVER HASH-VERIFIED AND NEVER BUDGET-CHECKED BEFORE SIGNING.
# `runbook.ts` refuses to send unless the stripped build's hash matches the reviewed
# source — that equality is the ENTIRE safety argument for deploying a build nobody read
# line-by-line. `gen_frozen` and the freeze driver had no equivalent: they assembled the
# FULL commented source and sent it.
#
# MEASURED at a later change on these bytes:
#     audited source, stripped (what deploys today) : 124,961 B
#     freeze artifact as previously assembled       : 349,224 B   (2.79x)
#     freeze artifact stripped                      : 124,567 B
# 🔴 AND THE SIZE IS NOT COSMETIC. The only NODE measurement of an UNSTRIPPED build of this
# module is an internal review's — 176,205 gas, 117.5 % of the hard 150,000 ceiling, which COULD
# NOT BE SUBMITTED AT ALL. The freeze artifact was LARGER than that build. The one transaction
# with no undo was being assembled in a shape with a measured history of being unsubmittable,
# and nothing would have said so until the send.
#
# This gate asserts the property the fix rests on: stripping the FROZEN build changes no
# parsed code, so its module hash is IDENTICAL. Measured once by hand
# (bF8y_gRCI4lX8Yb73WUCdn8ju5IH9wqdV8VSgczeclM both ways); asserted here every run, because
# a safety argument that is checked once is a safety argument that silently expires.
printf '== the FREEZE artifact survives stripping unchanged ==\n'
if ! command -v python3 >/dev/null 2>&1; then
  echo "  FAILED — python3 not found. This gate FAILS CLOSED."
  fail=1
else
  fz_fail=0
  for M in "${ARTIFACT[@]}"; do
    fz_un="$(mktemp -t spt-fz-un-XXXXXX.pact)"; fz_st="$(mktemp -t spt-fz-st-XXXXXX.pact)"
    gen_frozen "$M" > "$fz_un"
    if ! python3 ../../.github/scripts/strip-for-deploy.py "$fz_un" > "$fz_st" 2>/dev/null; then
      echo "  FAILED — the stripper could not process the frozen $M build"; fz_fail=1
      rm -f "$fz_un" "$fz_st"; continue
    fi
    # The flip is the whole point of the artifact; if stripping ate it the build is a lie.
    if ! grep -q '(defconst FROZEN-MODULE true)' "$fz_st"; then
      echo "  FAILED — stripping removed FROZEN-MODULE from the frozen $M build"; fz_fail=1
    fi
    un_b=$(wc -c < "$fz_un"); st_b=$(wc -c < "$fz_st")
    # A strip that removed almost nothing means the stripper silently no-op'd on this shape —
    # which would let an unsubmittable artifact through while reporting success.
    if [ "$st_b" -ge "$un_b" ]; then
      echo "  FAILED — stripping the frozen $M build removed nothing ($un_b -> $st_b B)"; fz_fail=1
    else
      echo "  $M: $un_b B -> $st_b B stripped"
    fi
    rm -f "$fz_un" "$fz_st"
  done
  if [ "$fz_fail" -ne 0 ]; then
    echo "           The freeze artifact is signed ONCE and cannot be undone. It goes through the"
    echo "           SAME stripper as the deploy, or it does not go."
    fail=1
  fi
fi

# a later change removed smartpacts-upgrade, -upgrade-float, -upgrade-rps-guard and -upgrade-d4:
# all four required a frozen pre-the design record/pre-D4 fixture to exercise the two historical
# migrations, which are deleted. smartpacts-upgrade-emergency STAYS and is now the only
# proof that an in-place upgrade works. Two non-migration assertions were relocated rather
# than dropped — see an internal document later change.md §3.
# a later change removed smartpacts-gallery.repl with the gallery product: the module belongs to
# SmartPacts/private-gallery, which is now its sole editable copy, and SPT's copy was the
# HARDENED one (Pattern-E escrow) — so the hardening was ported and pushed there FIRST
# (private-gallery a66fa11) before anything was deleted here. Nothing was lost from this
# repo's coverage: the suite carried ZERO modrefs (`grep -c 'module{' pact/` = 0 across the
# whole tree), and the cross-module surface it exercised — FUNDING-ACCOUNT and
# receive-funding — is asserted by 19 and 16 other suites respectively.
# its budget suite / -worst are TWO files on purpose (a later change): the registry
# cannot shrink, so one suite cannot hold both the shape that SHIPS and the most
# expensive shape the module PERMITS — and the whole finding was that only the
# first kind was ever pinned.
# A review finding: the suite list is a NAMED MANIFEST checked against the disk,
# exactly like PROBES below. Before this, a smartpacts-*.repl file on disk but absent from
# the list was silently never run — 22 pinned assertions outside the gate is this repo's
# measured third instance of that shape (a later change), and the a later change session nearly produced
# the fourth (a new suite file is easy to write and forget to wire). A suite retired on
# purpose leaves the manifest in the same commit, with the reason.
SUITES=(
  SPT SPT-init SPT-ext smartpacts-award-fairness smartpacts-award-safety
  smartpacts-proposal-lifecycle smartpacts-solvency-at-declaration smartpacts-supply-shared-writer smartpacts-admin-tiers smartpacts-record-date
  smartpacts-founder-address smartpacts-snapshot-open
  smartpacts-freeze-blessed smartpacts-frozen-invariant
  smartpacts-tranches smartpacts-votekey SPT-launch SPT-launch-ext
  SPT-launch-reserve smartpacts-governance 
  smartpacts-attacks smartpacts-attacks-vgrief smartpacts-capability-guard-class
  smartpacts-authorization-bounds smartpacts-squatted-coin-row smartpacts-mutation-survivors
  smartpacts-init-beneficiary-bounds smartpacts-founder-allocations smartpacts-wrapper-trust
  smartpacts-xchain smartpacts-pool-surplus smartpacts-pool-precision smartpacts-account-and-round-safety smartpacts-upgrade-emergency
  smartpacts-event-forgery smartpacts-value-event-forgery smartpacts-promises
  smartpacts-reserved-names smartpacts-snap-domain smartpacts-snap-corr-arith
)
suite_want=$(printf '%s\n' "${SUITES[@]}" | sort)
suite_have=$(ls smartpacts-*.repl SPT*.repl 2>/dev/null | sed 's/\.repl$//' | sort)
if [ -z "$suite_have" ]; then
  echo "== suite manifest =="
  echo "  FAILED — zero suite .repl files matched (smartpacts-*/SPT-*); this gate inspected nothing"; fail=1
elif [ "$suite_want" != "$suite_have" ]; then
  echo "== suite manifest =="
  echo "  FAILED — the suite set does not match the manifest (< manifest, > on disk):"
  diff <(printf '%s\n' "$suite_want") <(printf '%s\n' "$suite_have") | sed 's/^/    /' || true
  echo "           A suite on disk but not named here is NEVER RUN. Name it in SUITES in the"
  echo "           same commit, or retire the file deliberately, with the reason."
  fail=1
fi
for t in "${SUITES[@]}"; do
  printf '== %s ==\n' "$t"
  if pact "$t.repl" >/tmp/spt-$t.log 2>&1; then
    grep -E 'PASSED' "/tmp/spt-$t.log" || echo "  (loaded ok)"
  else
    echo "  FAILED — see /tmp/spt-$t.log"; tail -20 "/tmp/spt-$t.log"; fail=1
  fi
done

# --- MUST-FAIL fixtures (testing-rules: failures that cannot be wrapped in
# `expect-failure`). An unresolved module member is a COMPILE-time abort, so it
# kills the whole file and no in-suite assertion can observe it. Each fixture is
# therefore asserted from OUTSIDE on BOTH the exit code AND the error text: a
# fixture that failed for an unrelated reason (a typo, a renamed path, a missing
# fixture file) would otherwise read as a pass, which is the exact failure mode
# these tests exist to prevent.
declare -A MUSTFAIL=(
  # the design record / a later change REPLACED THIS FIXTURE'S CLAIM. It pinned "has no such member: CREDIT"
  # while Pattern W had deleted the capability; the design record restored it in coin's shape, so that
  # string would now never appear and the fixture would fail for the WRONG reason — or, worse,
  # a future edit would "fix" it by deleting it. It now pins the ROUTE that is closed on EVERY
  # engine: a foreign module cannot ACQUIRE CREDIT (module admin). The fork-gated compose route
  # is measured, and asserted against an earlier engine in a probe kept out of this repo.
  ["freemint-compose.repl-must-fail"]="Module admin necessary"
  # a later change — THE SECOND HALF OF THE FREEZE INVARIANT, one fixture per module.
  # smartpacts-frozen-invariant.repl proves every operation still WORKS frozen; on its own
  # that is satisfied by a module which is not frozen at all. These prove the upgrade path is
  # still REFUSED, which is the only thing freeze may break. A failing module `load` is a
  # compile-time abort that leaves the parser inside the module's namespace, so it cannot be
  # wrapped in expect-failure — hence a fixture asserted from outside.
  ["frozen-upgrade-token.repl-must-fail"]="Module is frozen"
  ["frozen-upgrade-launch.repl-must-fail"]="Module is frozen"
  # a later change cold-audit finding 2, REPURPOSED by a later change: the deploy must REFUSE to guess
  # whether it is an upgrade. The key was `legacy-adr015-tables` until the historical
  # migrations were deleted; it is now `upgrade`, which both selects the create-table set and
  # gates define-keyset (a later change finding 4) — so the abort fires at the keyset gate, first.
  # A load failure cannot be wrapped in expect-failure (it leaves the parser inside the
  # module's namespace), so it is asserted from outside.
  ["upgrade-nokey.repl-must-fail"]="read-msg failure"
  # a later change / an internal review a finding: the deploy footer's admin-keyset NAME pin had NO falsifying
  # test — a full 124-site mutation sweep found it SURVIVING, because all eight suites that set
  # `spt-admin-name` pass the CORRECT value. It was the only guard in either module that was
  # reachable, uncovered, and not documented as deliberately untestable.
  ["deploy-wrong-keyset-name.repl-must-fail"]="spt-gov-name must be the namespace's spt-gov keyset"
  # the design record (a later change) turned one pinned keyset name into two. A second pin with no falsifying
  # test is the exact state an internal review a finding found the FIRST pin in, so it gets its own
  # fixture rather than sharing one — see the header of each file for why they cannot merge.
  ["deploy-wrong-ops-keyset-name.repl-must-fail"]="spt-ops-name must be the namespace's spt-ops keyset"
  # An external review: the footer pinned the keyset NAMES and took every property of
  # the keyset VALUE on trust. Two payloads are catastrophic and one-shot — an EMPTY keyset (gov
  # satisfiable by anyone; init-supply measured succeeding with ZERO signatures) and `keys-1`
  # (accepted by define-keyset, kills every ops operation on that chain forever). One fixture per
  # half, each with the other keyset VALID, so neither can pass for the other's reason.
  ["deploy-empty-gov-keyset.repl-must-fail"]="SPT spt-gov must not be an empty keyset"
  ["deploy-keys1-ops-predicate.repl-must-fail"]="SPT spt-ops predicate must be a built-in"
  # Cold an internal review a finding: a finding shipped four value enforces and only TWO fixtures. Mutation-measured:
  # deleting either unpinned enforce left ALL SUITES PASS and both module hashes unchanged, because
  # the preamble is outside the module form. One fixture per remaining enforce, each with the other
  # keyset VALID so neither can pass for the other's reason.
  ["deploy-empty-ops-keyset.repl-must-fail"]="SPT spt-ops must not be an empty keyset"
  ["deploy-keys1-gov-predicate.repl-must-fail"]="SPT spt-gov predicate must be a built-in"
  # Cold an internal review a finding: the NEGATIVE half of the freeze/bless property. The positive half
  # (smartpacts-freeze-blessed.repl) proves an in-flight cross-chain transfer survives the freeze;
  # this proves that survival is DUE to the bless line. Pinned on the error TEXT because the
  # unblessed run aborts at continue-pact, and pact drops its buffered expect report when a later
  # statement aborts the load — a bare non-zero exit would pin nothing.
  ["freeze-unblessed-inflight.repl-must-fail"]="Yield provenance does not match"
  # Cold an internal review a finding: the deploy footer's upgrade branch must REFUSE a chain the fresh deploy
  # never reached. Pact does not evaluate GOVERNANCE when the module is absent, so upgrade:true
  # onto such a chain fresh-installs with NO TABLES — and with the freeze artifact that chain is
  # unrepairable forever while our own post-freeze check reports it correct. These load the REAL
  # module files, because gen_frozen strips the real footer and no other test has ever run it.
  ["c2-upgrade-onto-missing-module.repl-must-fail"]="SPT_round-count not found"
  ["c2-upgrade-onto-missing-launch.repl-must-fail"]="SPT-launch_config not found"
  # a later change cold-audit CRITICAL: the fix DELETED both LIFECYCLE and deindex-proposal, so the
  # attack is a name-resolution abort. Match on the member the attacker reaches for FIRST.
  ["deindex-compose.repl-must-fail"]="has no such member: LIFECYCLE"
  # a later change / the design record: TALLY, AGGREGATE, apply-tally, release-votes-on-debit and
  # record-final-tally are all DELETED, so the an internal review a finding/a finding attack is a name-resolution
  # abort. Match the member the attacker reaches for FIRST.
  ["weakcap-writers.repl-must-fail"]="has no such member: TALLY"
  # a later change half A / the operator runbook an internal review a finding: charge-entry and charge-global were
  # named public writers behind the weak-in-effect METER cap, and a foreign compose
  # drove the global meter to 1.200 of a 2.0 cap with ZERO signatures. Both are now
  # inlined into GAS_PAYER and deleted, so the attack is a name-resolution abort.
  # Match the member the attacker reaches for FIRST.
  # a later change / the operator runbook an internal review a finding: lock-tranche was a public defun gated only by
  # (require-capability (ADMIN)), so any transaction carrying an admin signature let a
  # foreign module compose ADMIN and plant a tranche row + forge TRANCHE-LOCKED, the
  # module's own "public disclosure anchor". Inlined into init-supply and deleted.
  # THE NAME HALF ONLY — the ROUTE half is a probe kept out of this repo, which composes
  # ADMIN itself. Neither is sufficient alone; an internal review's lead finding was a name-pin
  # exactly like this one passing while the destination stayed reachable.
  ["locktranche-compose.repl-must-fail"]="has no such member: lock-tranche"
)
# 🔴 THE MANIFEST IS COMPARED IN BOTH DIRECTIONS (a later change, survived both skeptics).
# It used to be consulted ONLY disk->manifest: `for f in *.repl-must-fail` then look up `want`.
# So DELETING a fixture silently orphaned its map entry and the suite still printed ALL SUITES
# PASS — and these fixtures are the ONLY assertion that nine separately-measured CRITICALs stay
# closed. They pin compile-time name-resolution aborts, which CANNOT be wrapped in
# expect-failure, so no in-suite assertion can substitute for one. a later change recorded this hole
# and a later change then ADDED A NINTH FIXTURE TO THE GATE WITHOUT FIXING IT.
mf_want=$(printf '%s\n' "${!MUSTFAIL[@]}" | sort)
mf_have=$(ls *.repl-must-fail 2>/dev/null | sort)
if [ "$mf_want" != "$mf_have" ]; then
  echo "== must-fail fixtures =="
  echo "  FAILED — the fixture set does not match the manifest (< manifest, > on disk):"
  diff <(printf '%s\n' "$mf_want") <(printf '%s\n' "$mf_have") | sed 's/^/    /' || true
  echo "           A fixture named here but MISSING from disk means the regression proof for a"
  echo "           measured CRITICAL was deleted. Retire it from MUSTFAIL in the SAME commit,"
  echo "           with the reason, or restore the file."
  fail=1
fi
mf_seen=0
for f in *.repl-must-fail; do
  [ -e "$f" ] || continue
  mf_seen=$((mf_seen + 1))
  printf '== %s (must fail) ==\n' "$f"
  want="${MUSTFAIL[$f]:-}"
  if [ -z "$want" ]; then
    echo "  FAILED — no expected-error string registered for $f in run-tests.sh"; fail=1; continue
  fi
  if pact "$f" >"/tmp/spt-$f.log" 2>&1; then
    echo "  FAILED — fixture SUCCEEDED; the attack it encodes is live again"; fail=1
  # 🔴 MATCH THE DIAGNOSTIC, NEVER PACT'S SOURCE ECHO (CONFIRMATORY AUDIT #21, a finding).
  # pact prints the offending SOURCE LINE under the error:
  #     modules/SPT.pact:53:284: SPT spt-ops must not be an empty keyset
  #      53 | (if (read-msg 'upgrade) [...] [(let (...) (enforce ...) (enforce ...) ...)])
  #         |                              ^^^
  # The whole deploy preamble is ONE line carrying ALL FOUR keyset messages, so a bare
  # `grep -F` over the raw log matched any of the four whenever ANY of them fired. MEASURED:
  # making spt-gov empty too made the gov enforce fire first — the ops enforce never ran —
  # and deploy-empty-ops-keyset still reported "fails as required (SPT spt-ops ...)".
  # Four fixtures were satisfiable without the enforce they name ever executing, and two of
  # them were an internal review's a finding remediation. Dropping the echo lines (`NN | ...` and `   | ^^^`)
  # leaves only real diagnostics, so the pin means what it says. Proven both directions: the
  # honest failure still matches; the wrong-reason failure now reports WRONG reason.
  # Fixed HERE rather than by splitting the preamble: the preamble is inside the deployed
  # bytes, so reformatting it grows the the design record stripped build and costs a node re-measure —
  # and this closes the class for every must-fail fixture, not just the four.
  elif grep -vE '^[[:space:]]*[0-9]*[[:space:]]*\|' "/tmp/spt-$f.log" | grep -qF "$want"; then
    echo "  fails as required ($want)"
  else
    echo "  FAILED — failed for the WRONG reason; expected: $want"; tail -5 "/tmp/spt-$f.log"; fail=1
  fi
done
# A negative gate that inspected zero items is a FAILURE, never a pass.
if [ "$mf_seen" -eq 0 ]; then
  echo "== must-fail fixtures =="
  echo "  FAILED — no .repl-must-fail fixtures found; the negative gate inspected zero items"; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "ALL SUITES PASS"
else
  # Give the tee subshell a moment to flush, then name the gates. Read-only over the log.
  sync 2>/dev/null || true
  echo ""
  echo "===== WHICH GATES FAILED ====="
  # For every FAILED line, report the nearest `== header ==` above it. If this finds
  # nothing it says so LOUDLY rather than printing an empty list — an empty summary next
  # to a non-zero exit is exactly the "inspected zero items and called it a pass" shape.
  # 🔴 ANCHOR THE MARKER. The first version matched a bare /FAILED/ and reported TWO gates
  # on a run where one failed — because this block's own "WHICH GATES FAILED" banner is in
  # the teed log by the time awk reads it, and the nearest header above it is whatever ran
  # last. A summary that invents a second failure is worse than no summary: the whole point
  # is that the COUNT is trustworthy. Every real site prints exactly `  FAILED` at indent 2.
  # 🔴 `  FAILED` IS NOT THE ONLY MARKER, MEASURED 2026-08-14 (a later change). The promise gate's
  # own manifest-arithmetic check prints `  TOOLING FAILURE — …` and sets fail=1, so a run
  # that failed ONLY on that printed "no gate could be named" — the summary reporting itself
  # broken while the real message sat 200 lines up. Both markers are anchored at indent 2.
  _named=$(awk '
    /^== .* ==$/                    { hdr = $0 }
    /^  FAILED/ || /^  TOOLING FAILURE/ { if (hdr != "") print hdr }
  ' "$_GATELOG" 2>/dev/null | sort -u)
  if [ -n "$_named" ]; then
    printf '%s\n' "$_named" | sed 's/^/  /'
    echo ""
    echo "  $(printf '%s\n' "$_named" | wc -l) gate(s) above. 🔴 If you EXPECTED one of these,"
    echo "  check the count: a second name here is a NEW regression, not the known one."
  else
    echo "  🔴 fail=1 was set but no gate could be named — the summary itself is broken."
    echo "     Do not read this as 'only one thing failed'. Scroll for 'FAILED'."
  fi
  echo "SUITE FAILURE"
  exit 1
fi
