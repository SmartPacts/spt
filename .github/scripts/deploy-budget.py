#!/usr/bin/env python3
"""THE GATE THAT DID NOT EXIST: does the artifact still fit under the deploy ceiling?

WHY
------------------------------
`SPT` grew **6 % past a HARD 150,000-gas ceiling across two audited
items and nothing went red**, because nothing in this tree measured deploy cost.
It was found only when a reviewer deployed it on a node: **176,205 gas, 117.5 %**.
The ceiling was bisected there — 150,000 accepted, **150,001 rejected at validation**.

🔴 THIS GATE NEVER EXTRAPOLATES, AND THAT IS ITS WHOLE DESIGN.
The estate's standing "≈94 %" figure was a LINEAR extrapolation from bytes and it
was **wrong by 24 %** (2.32 gas/byte actual vs 0.585 assumed). Deploy gas is not
linear in source size, and the REPL model has missed devnet by +29 %/−36 %. So this
gate holds exactly one kind of evidence — **a NODE MEASUREMENT, pinned to the byte
count it was taken at** — and fails the moment the artifact outgrows it:

 measured on a node -> recorded here with its byte count and commit
 artifact grows past -> FAIL: "the measurement is stale, re-measure on a node"
 measured gas > ceil -> FAIL: "it does not deploy"

A gate that guessed would be the same defect one turn on. **The correct response to
this gate failing is a node run, never a bigger number in the table below.**

TWO CHECKS, BOTH REQUIRED
-------------------------
 HASH the stripped build's module hash == the reviewed source's module hash.
 That equality is what proves the stripper touched no code, and it is the
 entire safety argument for deploying a build nobody reviewed line-by-line.
 Verified by loading BOTH in the REPL (`--verify-hash`, needs `pact`).
 BUDGET the stripped artifact's size against the last node measurement.

EXIT CODES
----------
 0 within the recorded measurement, hashes equal
 1 over budget / hash mismatch / measurement stale
 2 TOOLING FAILURE — self-test failed, unreadable input, or `pact` missing when
 a hash verification was requested. Never confuse this with 0.
"""
import os
import re
import subprocess
import sys
import tempfile

CEILING = 150_000          # KDA-CE per-transaction gas ceiling. NOT a policy dial.

# ---------------------------------------------------------------------------
# 🔴 NODE MEASUREMENTS. Every row was mined on a real node. Adding a row without a
# node run — or raising one to make this gate quiet — reintroduces exactly the
# defect this file exists for. Record: module, stripped bytes, measured gas, where.
# ---------------------------------------------------------------------------
#
# "≈ +3.3 % on the stripped build" — 7.5x out, alongside the same ADR under-predicting the
# per-transfer gas delta (+280 predicted, +408 measured; see the gas suite kept out of this repo).
#
# 🔴 THE CONTROL RUN IS WHY THIS FILE FORBIDS EXTRAPOLATION, AND IT FINALLY HAS A CLEAN
# MEASUREMENT BEHIND THE RULE. Both trees were deployed to the SAME live 3.2 node in the SAME
# session, minutes apart:
# main token 96,536 B -> 84,886 gas launch 9,521 B -> 17,468 gas
#
# main reproduced the previously recorded pairs EXACTLY, which is what makes the branch
# numbers comparable rather than merely newer.
#
# 🔴 AND `SPT-launch` MOVED +2,960 GAS (+16.9 %) WITH NOT ONE BYTE OF ITS OWN SOURCE
# CHANGED — it is byte-for-byte identical to main at 9,521 B on both runs. The only variable
# is its DEPENDENCY: `SPT` grew. So deploy gas is NOT a function of a module's
# own size, and any bytes -> gas scaling is the wrong MODEL, not merely an imprecise one.
# The provenance note on the launch entry below used to reason exactly that way ("the rename
#
# For the record: naive scaling of the old token pair predicted ~105,800 and the node said
# 104,847 — close THIS time. The launch result is the reason that near-miss is not evidence.
#
# Re-measure with: cd test/harness && DEVNET_HOST=<node> npx --no-install tsx src/deploy-gas-devnet.ts
# 🔴 Verify the node is ALIVE by sampling height TWICE and requiring an increase — a wedged
# node reports health=healthy and still serves every read. Never raise a recorded number to
# make this gate quiet.
MEASURED = {
 # module: (stripped_bytes_at_measurement, measured_gas, provenance)
 #
 # These pairs come from an ACTUAL DEPLOY on a Kadena 3.2 devnet, mined, against the
 # comment-stripped build in `deploy-bytes/`. They are not estimates.
 #
 # Why a node and not the REPL: the REPL backend does not charge for the module-source
 # write that the real chain does, and has missed the node by +29 %/-36 % in one campaign.
 # Why not scale from bytes: measured marginal rates on this module span 0.005 gas/B for
 # documentation text to 2.32 gas/B for code -- a 430x spread -- and a dependent module
 # pays for its dependency's size even when its own source is byte-identical. Bytes -> gas
 # is the wrong model here, not merely an imprecise one, so this gate refuses to
 # extrapolate: if the artifact grows past its measured size, it FAILS until re-measured.
    'SPT': (
        92_474, 101_421,
        '2026-08, Kadena 3.2 devnet, fresh genesis, mined, comment-stripped. '
        '101,421 = 67.6 % of the hard 150,000 gas deploy ceiling.',
    ),
    'SPT-launch': (
        10_705, 21_883,
        '2026-08, same node and run as the token, mined, comment-stripped. '
        '21,883 = 14.6 % of the hard 150,000 gas deploy ceiling.',
    ),
}


#
# rehearsal). This harness pinned "n_48867b…" as a literal, so it could only ever load bytes
# already patched to the mainnet namespace: a rehearsal build repatched to `free` failed the
# HASH COMPARISON with "spt-gov-name must be the namespace's spt-gov keyset" — the gate refusing
# the artifact for a reason that had nothing to do with the artifact. Deriving it means the gate
# validates whatever namespace the source actually carries, which is also what
# ops/check-namespace.sh independently pins.
def _source_namespace(*paths):
    """The namespace THE ARTIFACT carries.

 🔴 Scans BOTH modules, with comments stripped, and refuses anything but exactly one
 namespace. It used to read ONE file, take the
 FIRST match of `"<ns>.spt-gov"`, and not strip comments — 1 of the 7 namespace literals.
 Three measured consequences:
 * a SPLIT repatch that left SPT.pact:25 correct was invisible;
 * a namespace named only inside a `;;` comment could steer the answer, and this function
 also feeds deploy-budget's HASH_PROBE, so a comment could pick the namespace the probe
 hashes under;
 * a module naming NO namespace was cleared by reading its sibling.
 The anchor deliberately names no module — a pattern that lists module names goes blind on
 the next rename, silently, which is how this project's other namespace gate once lost a
 literal. It is
 the SAME anchor config.ts uses, so the two gates cannot drift apart about what "the source
 carries".

 Takes the EXPLICIT files to scan. It briefly derived them from one path's directory,
 which broke the hash probe: that caller passes a STRIPPED BUILD in a temp dir where the
 sibling does not exist. Guessing a check's inputs is how a check inspects the wrong thing.
 """
    import re as _re
    if not paths:
        raise SystemExit('deploy-budget: _source_namespace called with no files — a check that '
                         'inspects nothing is a FAILURE, not a pass')
    found, per_file = set(), {}
    for fp in paths:
        name = os.path.basename(fp)
        try:
            src = open(fp, encoding='utf-8').read()
        except OSError as e:
            raise SystemExit('deploy-budget: cannot read %s (%s) — refusing to guess' % (fp, e))
        code = _re.sub(r';;[^\n]*', '', src)          # a comment does not get a vote
        here = set(_re.findall(r'\b(n_[0-9a-f]{40}|free)\.[A-Za-z]', code))
        if not here:
            raise SystemExit(
                'deploy-budget: %s names NO namespace — a module that names none cannot be '
                'cleared by reading its sibling' % name)
        per_file[name] = sorted(here)
        found |= here
    if len(found) != 1:
        raise SystemExit(
            'deploy-budget: the artifact carries MORE THAN ONE namespace: %s %s — a split '
            'repatch is how a deploy lands half in the wrong place'
            % (', '.join(sorted(found)), per_file))
    return next(iter(found))

def strip(path):
    """Reuse the ONE stripper. A second implementation here would be a second
 chance to disagree with the thing that actually builds the deploy tx."""
    here = os.path.dirname(os.path.abspath(__file__))
    r = subprocess.run([sys.executable, os.path.join(here, 'strip-for-deploy.py'), path],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, 'stripper failed: %s' % (r.stderr.strip() or r.returncode)
    return r.stdout, None


HASH_PROBE = '''(env-chain-data {{ "chain-id": "0", "block-time": (time "2026-06-01T00:00:00Z") }})
(begin-tx)
(load "fixtures/fungible-v2.pact")
(load "fixtures/fungible-xchain-v1.pact")
(load "fixtures/coin.pact")
(create-table coin.coin-table)
(create-table coin.allocation-table)
(commit-tx)
(begin-tx)
(env-data
  {{ "ns": "{ns}"
  , "spt-gov-name": "{ns}.spt-gov"
  , "spt-gov": {{ "keys": ["admin-key"], "pred": "keys-all" }}
  , "spt-ops-name": "{ns}.spt-ops"
  , "spt-ops": {{ "keys": ["admin-key"], "pred": "keys-any" }}
  , "upgrade": false }})
(env-keys ["admin-key"])
(define-namespace "{ns}" (read-keyset 'spt-gov) (read-keyset 'spt-gov))
(load "{tokens}")
(load "{launch}")
(print (format "HASH={{}}" [(at 'hash (describe-module "{ns}.{name}"))]))
(commit-tx)
'''


def module_hash(name, paths, test_dir):
    """Load the WHOLE artifact in dependency order and return `name`'s module hash.

 🔴 BOTH modules, always, and the order is load-bearing: `SPT-launch`
 references `SPT`, so probing the sale alone fails to load and the
 gate would report a tooling error instead of a hash. `paths` maps each module to
 the file to load for it, so the caller can swap ONE module for its stripped build
 while the other stays as-is — which is what makes the comparison isolate the strip.
 """
    with tempfile.NamedTemporaryFile('w', suffix='.repl', delete=False,
                                     dir=test_dir) as fh:
        fh.write(HASH_PROBE.format(
            name=name,
            ns=_source_namespace(paths['SPT'], paths['SPT-launch']),
            tokens=os.path.abspath(paths['SPT']),
            launch=os.path.abspath(paths['SPT-launch'])))
        probe = fh.name
    try:
        r = subprocess.run(['pact', probe], capture_output=True, text=True, cwd=test_dir)
        m = re.search(r'HASH=([A-Za-z0-9_-]+)', r.stdout)
        if not m:
            return None, (r.stderr or r.stdout)[-400:]
        return m.group(1), None
    finally:
        os.unlink(probe)


def selftest():
    """The stripper is the dependency that could silently break this gate, so the
 self-test exercises IT, not our own arithmetic."""
    here = os.path.dirname(os.path.abspath(__file__))
    with tempfile.NamedTemporaryFile('w', suffix='.pact', delete=False) as fh:
        fh.write('(module m G ;; comment\n  (defun f () "a; b") ;; another\n)\n')
        p = fh.name
    try:
        out, err = strip(p)
    finally:
        os.unlink(p)
    if err or out is None:
        print('  SELF-TEST FAILED: %s' % err, file=sys.stderr)
        return False
    if ';; comment' in out or ';; another' in out:
        print('  SELF-TEST FAILED: comments survived the strip', file=sys.stderr)
        return False
    if '"a; b"' not in out:
        print('  SELF-TEST FAILED: a semicolon inside a string was eaten', file=sys.stderr)
        return False
    return True


def main(argv):
    args = dict(zip(argv[::2], argv[1::2]))
    mod_dir = args.get('--modules', 'pact/modules')
    test_dir = args.get('--test-dir')
    verify_hash = '--verify-hash' in argv

    if not selftest():
        return 2

    names = sorted(MEASURED)
    seen = 0
    findings = []
    for name in names:
        path = os.path.join(mod_dir, name + '.pact')
        if not os.path.exists(path):
            findings.append('%s: NOT FOUND at %s' % (name, path))
            continue
        seen += 1
        stripped, err = strip(path)
        if err:
            print('  FAILED — %s' % err, file=sys.stderr)
            return 2
        size = len(stripped.encode('utf-8'))
        measured_bytes, measured_gas, prov = MEASURED[name]

        if measured_gas > CEILING:
            findings.append(
                '%s: the LAST NODE MEASUREMENT is %s gas, over the %s ceiling — it does '
                'not deploy (%s)' % (name, f'{measured_gas:,}', f'{CEILING:,}', prov))
            continue

        if measured_bytes is None:
            print('  %-20s %8s B stripped · last node measurement %s gas (%.0f%% of ceiling) '
                  '· size not pinned' % (name, f'{size:,}', f'{measured_gas:,}',
                                         100.0 * measured_gas / CEILING))
            continue

        if size > measured_bytes:
            findings.append(
                '%s: %s B stripped, but the last NODE measurement (%s gas) was taken at '
                '%s B — it has grown %s B past its evidence. 🔴 RE-MEASURE ON A NODE. Do '
                'NOT extrapolate: the estate\'s last extrapolation was wrong by 24%%. (%s)'
                % (name, f'{size:,}', f'{measured_gas:,}', f'{measured_bytes:,}',
                   f'{size - measured_bytes:,}', prov))
        else:
            print('  %-20s %8s B stripped (<= %s B measured) · %s gas on a node = %.1f%% '
                  'of the ceiling' % (name, f'{size:,}', f'{measured_bytes:,}',
                                      f'{measured_gas:,}', 100.0 * measured_gas / CEILING))

    if seen == 0:
        print('  FAILED — inspected ZERO modules; a scan of nothing is not a clean scan',
              file=sys.stderr)
        return 2

    if verify_hash:
        if not test_dir or not os.path.isdir(test_dir):
            print('  FAILED — --verify-hash needs --test-dir <pact/test>', file=sys.stderr)
            return 2
        try:
            subprocess.run(['pact', '--version'], capture_output=True, check=True)
        except Exception:
            print('  FAILED — `pact` not found; the hash check FAILS CLOSED because it is '
                  'the whole safety argument for deploying a stripped build', file=sys.stderr)
            return 2
        reviewed = {n: os.path.join(mod_dir, n + '.pact') for n in names}
        if not all(os.path.exists(p) for p in reviewed.values()):
            print('  FAILED — the hash check needs BOTH artifact modules present',
                  file=sys.stderr)
            return 2
        for name in names:
            stripped, _ = strip(reviewed[name])
            with tempfile.NamedTemporaryFile('w', suffix='.pact', delete=False) as fh:
                fh.write(stripped)
                sp = fh.name
            try:
 # Swap in ONLY this module's stripped build; the other stays reviewed,
 # so any hash difference is attributable to THIS strip and nothing else.
                h_src, e1 = module_hash(name, reviewed, test_dir)
                h_str, e2 = module_hash(name, dict(reviewed, **{name: sp}), test_dir)
            finally:
                os.unlink(sp)
            if h_src is None or h_str is None:
                print('  FAILED — could not load %s to compare hashes: %s'
                      % (name, e1 or e2), file=sys.stderr)
                return 2
            if h_src != h_str:
                findings.append(
                    '%s: 🔴 HASH MISMATCH — reviewed %s vs stripped %s. The stripper '
                    'CHANGED THE CODE. Do not deploy. This check is the only thing '
                    'standing between a stripped build and an unreviewed one.'
                    % (name, h_src, h_str))
            else:
                print('  %-20s hash identical stripped vs reviewed (%s)' % (name, h_src))

    if findings:
        print('  FAILED — %d finding(s):' % len(findings))
        for f in findings:
            print('    ' + f)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
