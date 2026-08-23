#!/usr/bin/env bash
#
# check-namespace.sh — HARD, fail-closed namespace-consistency gate (audit a finding).
#
# WHY (the central deploy risk; audit a finding, and the checklist that used to carry it was
# deleted in the doc cull — this gate is now the record):
# The tokens/launch modules embed the deploy namespace as STRING LITERALS:
# - GOV-KS / OPS-KS "<ns>.spt-gov" / "<ns>.spt-ops" (the design record, both modules)
# - the deploy-footer NAME pins in SPT (same two strings again)
# A mainnet n_<hash> deploy that forgets to patch these is SILENT and SEVERE:
# the admin guard resolves to the wrong keyset.
# (The gas station no longer participates — the design record: its ADMIN-KS binds from
# 'ns tx data at deploy and its sponsorship prefixes are per-network REGISTRY
# rows, seeded by admin tx. Zero station literals is therefore correct; this
# gate still fail-closes on ZERO literals overall, which tokens/launch provide.)
#
# This converts the previously-manual checklist grep into an executable gate the
# runbook MUST pass before any non-throwaway deploy. Fail-closed: any namespace
# token that is not the expected one, or zero qualified hits, is a VIOLATION.
#
# USAGE
# ops/check-namespace.sh <expected-namespace> # e.g. free | n_<hash>
# SPT_NAMESPACE=free ops/check-namespace.sh # or read from env
#
# EXIT STATUS
# 0 -> every namespace-qualified SPT literal uses <expected-namespace>
# 1 -> at least one literal uses a different namespace (or none were found)
# 2 -> usage error
set -euo pipefail

EXPECTED="${1:-${SPT_NAMESPACE:-}}"
if [ -z "$EXPECTED" ]; then
  echo "usage: $0 <expected-namespace>   (or set SPT_NAMESPACE)" >&2
  exit 2
fi

# Resolve module dir relative to this script so it runs from anywhere.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODDIR="$HERE/../pact/modules"
if [ ! -d "$MODDIR" ]; then
  echo "VIOLATION: module dir not found: $MODDIR" >&2
  exit 2
fi

# Every namespace-qualified SPT reference. The forms actually present today:
# "<ns>.spt-gov" / "<ns>.spt-ops" (keyset names, lowercase) -> capture <ns>
# "m:<ns>.SPT-launch:…" (module-guard principal) -> capture <ns>
# and the matcher also covers, because they are shapes this source can legally take:
# "(<ns>.SPT.…" (sponsored call prefix)
# "<ns>.SPT" (a literal ENDING at the module name)
# 🔴 The old comment named `"(<ns>.spt-…` and `"m:<ns>.smartpacts-…` — forms the a later change rename
# made false, since the modules are now `SPT` / `SPT-launch`. A comment that documents coverage
# the matcher no longer has is worse than none: it is what a reviewer checks instead of the regex.
# The capture is the namespace token immediately before the module-or-keyset name.
#
# 🔴 THE `m:` FORM WAS ADDED BY a later change AND THE GATE WAS BLIND TO IT BEFORE. a later amendment D6
# introduced SPT.LAUNCH-RESERVE-PIN, a FOURTH namespace-dependent literal of the
# shape "m:<ns>.SPT-launch:SPT-launch-reserve". The old pattern required the namespace
# token to start immediately after the quote, so the leading `m:` made it unmatchable: the gate
# reported "checked: 3" and PASSED while the newest literal — the one guarding 20,000 SPT — was
# never inspected. MEASURED before/after: 3 literals -> 4. A gate that silently narrows its own
# scope is the estate's most-repeated defect; this comment exists so the next literal shape is
# added here rather than discovered by an reviewer.
matches="$(grep -rhoE '"\(?(m:)?[A-Za-z0-9_-]+\.(SPT|spt|smartpacts)[-a-z:."]' "$MODDIR" || true)"

if [ -z "$matches" ]; then
  echo "VIOLATION: no namespace-qualified SPT literal found under $MODDIR —"
  echo "           the grep pattern or the source moved; refusing to pass blind."
  exit 1
fi

violations=0
total=0
# Extract the <ns> token from each match and compare to EXPECTED.
while IFS= read -r m; do
  [ -z "$m" ] && continue
  total=$((total + 1))
  ns="$(printf '%s' "$m" | sed -E 's/^"\(?//; s/^m://; s/\.(SPT|spt|smartpacts)[-a-z:."]$//')"
  if [ "$ns" != "$EXPECTED" ]; then
    printf 'VIOLATION: namespace %-12s != expected %-12s  (literal: %s)\n' "$ns" "$EXPECTED" "$m"
    violations=$((violations + 1))
  fi
done <<< "$matches"

# ---------------------------------------------------------------------------
# 🔴 a later change: THE GATE NOW ASSERTS **WHICH FOUR**, NOT JUST "MORE THAN ZERO".
#
# Everything above this line only ever proved two things: at least one literal exists,
# and no literal names the wrong namespace. Neither can see a literal that STOPPED BEING
# MATCHED — and that is not hypothetical here, it is the recorded a later change run: the gate
# printed "checked: 3" and PASSED while `LAUNCH-RESERVE-PIN`, the literal guarding 20,000
# SPT, was invisible to the pattern. A zero-literal source fails; a THREE-literal source
# passed. The distance between those two is where the defect lived.
#
# A bare count of 4 would close that specific hole and leave its sibling open: a count
# cannot see RELOCATION. Swap the `m:` module-guard principal in `SPT` for a
# plain keyset literal and add an `m:` one to `SPT-launch` and the total is still 4
# — the same blindness `dml-manifest.py` was written to fix on the DML surface (a later change
# a finding), which is why this is a manifest and not a number.
#
# So: pin (file, form) and compare the whole set. FORMS are the three shapes the pattern
# above knows about — `plain` = "<ns>.spt-…" (keyset name, also the sponsored-prefix
# shape), `m` = "m:<ns>.smartpacts-…" (module-guard principal, a later amendment D6).
#
# WHEN THIS GOES RED, THE ANSWER IS ALMOST NEVER TO EDIT THE PIN. A new namespace-dependent
# literal is a DEPLOY-SURFACE change: it has to be patched by F2 along with the other four
# and re-audited. Edit `EXPECTED_MANIFEST` only after that is true, and say which commit
# added the literal.
# EVERY module gets a row, including the ones whose correct answer is ZERO. The gas
# station's zero is a CLAIM (the design record: its ADMIN-KS binds from 'ns tx data and its prefixes
# are per-network registry rows), and an unstated zero is indistinguishable from a file the
# gate never opened — which is the whole failure being closed here.
# 🔴 RE-PINNED AT a later change (the design record, the two admin keyset tiers): 4 -> 7.
# This is the legitimate case the paragraph above describes, so the commit is named. the design record
# retires `spt-admin` and defines `<ns>.spt-gov` + `<ns>.spt-ops`, which turns ONE
# namespace-qualified literal into TWO in each of three places:
# SPT plain 2 -> 4 (the deploy-footer NAME pins, + the GOV-KS/OPS-KS defconsts)
# SPT-launch plain 1 -> 2 (its GOV-KS/OPS-KS defconsts)
# SPT m 1 (LAUNCH-RESERVE-PIN — unchanged)
# The gas station stays at 0/0: it FORMATS its two names from (read-msg 'ns) rather than
# embedding a literal, so it has no deploy-surface literal to patch. That zero is still a
# CLAIM, and it is still stated rather than left implicit.
# 🔴 ALL SEVEN ARE PATCHED BY F2 TOGETHER. Splitting the keyset doubled the F2 surface; a
# patch that updates the defconsts and forgets the footer's name pins now produces a module
# whose gate points at a keyset the deploy transaction never defined.
EXPECTED_MANIFEST='a separate gas-sponsorship module.pact m 0
a separate gas-sponsorship module.pact plain 0
SPT-launch.pact m 0
SPT-launch.pact plain 2
SPT.pact m 1
SPT.pact plain 4'
# 🔴 THE TERMINATOR CLASS CARRIES `.` AND `"` (delta an internal review verification, newly found).
# It was `[-a-z:]`, which cannot match a literal that ENDS at the module name — a bare
# `"<ns>.SPT"` — so an eighth literal of that shape would be invisible and this count would
# happily stay at 7. MEASURED: the old class saw 7 and missed the injected bare form; the wider
# class sees the same 7 today (no regression) and catches it. This is the third time a matcher
# here has narrowed silently: a later change (3->4), a later change (4->7), a later change (7->6 in config.ts).
# The count below is what makes a narrowing LOUD — never adjust it to make a scan pass.
EXPECTED_TOTAL=7

# 🔴 `grep -c` counts LINES, not MATCHES — two literals on one line would count as one and
# the manifest would under-report exactly the way the old gate did. `-o | grep -c .` counts
# matches. (`grep -c .` over empty input is 0 with exit 1, hence the `|| true`.)
count_form() {   # $1 = file, $2 = extended regex
  grep -oE "$2" "$1" | grep -c . || true
}
actual_manifest="$(
  for f in "$MODDIR"/*.pact; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    printf '%s m %s\n%s plain %s\n' \
      "$b" "$(count_form "$f" '"\(?m:[A-Za-z0-9_-]+\.(SPT|spt|smartpacts)[-a-z:."]')" \
      "$b" "$(count_form "$f" '"\(?[A-Za-z0-9_-]+\.(SPT|spt|smartpacts)[-a-z:."]')"
  done | sort
)"

echo "-- namespace gate --"
uniq_ns="$(printf '%s\n' "$matches" | sed -E 's/^"\(?//; s/^m://; s/\.(SPT|spt|smartpacts)[-a-z:."]$//' | sort -u | paste -sd, -)"
echo "expected: $EXPECTED   checked: $total qualified literal(s)   namespaces seen: $uniq_ns"

if [ "$total" -ne "$EXPECTED_TOTAL" ]; then
  echo "VIOLATION: expected exactly $EXPECTED_TOTAL namespace-qualified literal(s), found $total."
  violations=$((violations + 1))
fi

if [ "$actual_manifest" != "$(printf '%s' "$EXPECTED_MANIFEST" | sort)" ]; then
  echo "VIOLATION: the namespace-literal MANIFEST moved (expected vs actual):"
  diff <(printf '%s\n' "$EXPECTED_MANIFEST" | sort) <(printf '%s\n' "$actual_manifest") \
    | sed 's/^/           /' || true
  echo "           A count alone cannot see this: a literal changing FORM or FILE keeps the"
  echo "           total at $EXPECTED_TOTAL. Every one of these is patched by F2 together."
  violations=$((violations + 1))
fi

if [ "$violations" -ne 0 ]; then
  echo "RESULT: FAIL ($violations finding(s)) — patch the source to '$EXPECTED' + re-audit before deploy."
  exit 1
fi
printf 'manifest: %s\n' "$(printf '%s' "$actual_manifest" | tr '\n' ';' | sed 's/;/ · /g')"
echo "RESULT: PASS — all $EXPECTED_TOTAL SPT-qualified literals use '$EXPECTED', in the pinned shape."
