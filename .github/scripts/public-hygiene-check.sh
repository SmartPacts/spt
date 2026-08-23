#!/usr/bin/env bash
# ===========================================================================
# public-hygiene-check.sh — the scrub, enforced on every push instead of once.
#
# This repo was produced by removing internal cross-references from a private
# tree. A one-time removal decays: the next copied paragraph brings an internal
# id back and nobody notices. This makes the removal a property of the repo.
#
# WHAT IT DOES NOT DO: it does not remove reasoning. Saying WHAT a guard
# prevents is the point of publishing. What it bans is the internal bookkeeping
# an outside reader cannot resolve and does not need.
#
# FAILS CLOSED. Zero files scanned is a FAILURE, never a pass.
# ===========================================================================
set -uo pipefail
cd "$(dirname "$0")/../.."

# This file necessarily contains the patterns it bans, so it excludes itself —
# by exact path, never by a wildcard that could quietly cover something else.
SELF=".github/scripts/public-hygiene-check.sh"

mapfile -t FILES < <(git ls-files | grep -v -x -F "$SELF")
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "  FAILED — git ls-files returned nothing; this check inspected zero files."
  exit 1
fi

fail=0
scanned=0

check() {   # $1 = human name, $2 = ERE
  local name="$1" re="$2" bad=0 f out
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    out=$(grep -InE -- "$re" "$f" 2>/dev/null | head -3)
    if [ -n "$out" ]; then
      bad=$((bad + 1))
      printf '%s\n' "$out" | sed "s|^|    $f:|"
    fi
  done
  if [ "$bad" -ne 0 ]; then
    echo "  FAILED — $name: $bad file(s)."
    fail=1
  else
    echo "  clean — $name"
  fi
}

# ---------------------------------------------------------------------------
# WRAP-TOLERANT PASS. A line-based grep cannot see a reference broken across a
# line break, and prose wraps. MEASURED: "cold audit #22" shipped publicly past
# the audit-round pattern below, because the scrub left "cold audit" ending one
# line and "> #22" starting the next. The pattern was right; the line was wrong.
#
# So every pattern is applied a second time to each line JOINED WITH THE NEXT,
# after stripping the continuation's blockquote/list prefix. Pairwise, never the
# whole file: joining everything would invent matches across paragraphs.
# ---------------------------------------------------------------------------
check_wrapped() {   # $1 = human name, $2 = ERE
  local name="$1" re="$2" bad=0 f out
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    out=$(python3 - "$f" "$re" <<'PYEOF'
import sys, re, io
path, pat = sys.argv[1], sys.argv[2]
try:
    lines = io.open(path, encoding="utf-8", errors="replace").read().split("\n")
except OSError:
    sys.exit(0)
rx = re.compile(pat)
strip = re.compile(r"^[\s>]*(?:[-*+]\s+|\d+\.\s+)?")
for i in range(len(lines) - 1):
    joined = lines[i].rstrip() + " " + strip.sub("", lines[i + 1])
    # only report what the single-line pass could NOT already see
    if rx.search(joined) and not rx.search(lines[i]) and not rx.search(lines[i + 1]):
        print("%d: %s" % (i + 1, joined.strip()[:160]))
PYEOF
) || out=""
    if [ -n "$out" ]; then
      bad=$((bad + 1))
      printf '%s\n' "$out" | sed "s|^|    $f:|"
    fi
  done
  if [ "$bad" -ne 0 ]; then
    echo "  FAILED — $name (across a line break): $bad file(s)."
    fail=1
  else
    echo "  clean — $name (across a line break)"
  fi
}

echo "== publication hygiene =="
for f in "${FILES[@]}"; do [ -f "$f" ] && scanned=$((scanned + 1)); done
if [ "$scanned" -eq 0 ]; then
  echo "  FAILED — zero readable files; this check proved nothing."
  exit 1
fi

check "internal decision-record ids"  '\bADR-[0-9]{3}\b'
check "internal work-item ids"        '\bCW32-[0-9]+\b'
check "internal finding ids"          '\b(F-[0-9]{1,2}|F#[0-9]{1,2}|C-[0-9]{1,2}|L[0-9]-F[0-9]{1,2})\b'
check "audit-round references"        '\b(cold |delta |confirmatory |external )?audit #?[0-9]+'
check "private filesystem paths"      '(/home/[a-z]|/Users/[a-z]|~/claude/)'
check "personal email addresses"      '[A-Za-z0-9._%+-]+@(gmail|hotmail|outlook|yahoo)\.'
check "AI-assistant traces"           '(CLAUDE\.md|[Cc]laude [Cc]ode|Anthropic|Co-Authored-By)'
check "signing-device identifiers"    "(Nano S|Ledger device|device hash|m/44'?/626)"

# The same patterns again, this time across a line break. See check_wrapped.
check_wrapped "internal decision-record ids"  '\bADR-[0-9]{3}\b'
check_wrapped "internal work-item ids"        '\bCW32-[0-9]+\b'
check_wrapped "internal finding ids"          '\b(F-[0-9]{1,2}|F#[0-9]{1,2}|C-[0-9]{1,2}|L[0-9]-F[0-9]{1,2})\b'
check_wrapped "audit-round references"        '\b(cold |delta |confirmatory |external )?audit #?[0-9]+'
check_wrapped "private filesystem paths"      '(/home/[a-z]|/Users/[a-z]|~/claude/)'

# A 64-hex string is a public key. The suites use synthetic repeated-nibble keys
# on purpose (aaaa…, f0f0…, deadbeef-style); a REAL key is never a short repeat,
# so those shapes are filtered out and anything else is reported for a human to
# clear. Two passes rather than one regex: ERE has no lookahead, and a pattern
# that silently failed to compile would report "clean" over every file.
# EXACT paths whose 64-hex strings were read and cleared BY HAND as checksums,
# not keys. Exact paths only — a wildcard here would silently cover a file
# nobody looked at. A dead entry (no such file) FAILS: an exemption that
# exempts nothing is an exemption someone will copy without noticing.
HEX_CLEARED=(
  ".github/workflows/ci.yml"      # sha256 of the pinned Pact release + binary
  "deploy-bytes/SHA256SUMS"       # sha256 of the two deployable artifacts
)
for c in "${HEX_CLEARED[@]}"; do
  if [ ! -f "$c" ]; then
    echo "  FAILED — hex clearance names $c, which does not exist. Remove the stale entry."
    fail=1
  fi
done

echo "  -- possible real public keys --"
keyhits=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  cleared=0
  for c in "${HEX_CLEARED[@]}"; do [ "$f" = "$c" ] && cleared=1; done
  [ "$cleared" = 1 ] && continue
  while IFS= read -r line; do
    hex="${line##*:}"
    # Reject repeats of a 1-, 2- or 4-character unit (the synthetic test keys).
    # Done in bash, not in a regex: `grep -E` has no backreferences, and the
    # backreference version FAILED TO COMPILE while still printing a result —
    # a filter that errors and passes everything through is the false-positive
    # twin of a check that inspects nothing.
    synthetic=0
    for u in 1 2 4; do
      unit="${hex:0:$u}"; rep=""
      while [ "${#rep}" -lt 64 ]; do rep="$rep$unit"; done
      [ "$rep" = "$hex" ] && synthetic=1
    done
    [ "$synthetic" = 1 ] && continue
    echo "    $f: $line"; keyhits=$((keyhits + 1))
  done < <(grep -IonE '\b[0-9a-f]{64}\b' "$f" 2>/dev/null | head -3)
done
if [ "$keyhits" -ne 0 ]; then
  echo "  FAILED — possible real public keys: $keyhits occurrence(s). Clear each by hand."
  fail=1
else
  echo "  clean — possible real public keys"
fi

echo "  scanned $scanned tracked file(s)"
if [ "$fail" -ne 0 ]; then
  echo "PUBLICATION HYGIENE FAILURE — remove the reference; never weaken this check."
  echo "Keep the defensive reasoning: say WHAT a guard prevents, not which internal"
  echo "ticket asked for it."
  exit 1
fi
echo "PUBLICATION HYGIENE OK"
