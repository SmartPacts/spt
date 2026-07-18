#!/usr/bin/env bash
# Run the SPT REPL test suites (devnet-independent regression).
# Each suite (load "setup.repl") loads coin + the 3 modules, then asserts behavior.
set -euo pipefail
cd "$(dirname "$0")"
fail=0
for t in mainnet-lineage mainnet-gas-station smartpacts-shares smartpacts-shares-init smartpacts-shares-ext smartpacts-dividend-fairness smartpacts-tranches smartpacts-votekey smartpacts-ipo smartpacts-ipo-ext smartpacts-governance smartpacts-gas-station smartpacts-attacks smartpacts-attacks-voting smartpacts-upgrade smartpacts-upgrade-float smartpacts-upgrade-rps-guard; do
  printf '== %s ==\n' "$t"
  if pact "$t.repl" >/tmp/spt-$t.log 2>&1; then
    grep -E 'PASSED' "/tmp/spt-$t.log" || echo "  (loaded ok)"
  else
    echo "  FAILED — see /tmp/spt-$t.log"; tail -20 "/tmp/spt-$t.log"; fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "ALL SUITES PASS" || { echo "SUITE FAILURE"; exit 1; }
