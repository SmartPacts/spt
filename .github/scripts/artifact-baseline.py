#!/usr/bin/env python3
"""Pin the deploy artifact to a RECORDED BASELINE, and say what that baseline's audit status is.

WHY THIS EXISTS (a later change, item 3)
---------------------------------
Nothing in this tree linked the artifact to a baseline. `ops/mainnet-config.json` recorded
two module hashes with the note *"these are the hashes an internal review must audit; any
audited-hash pin taken BEFORE this patch is void"* — and **nothing read it**. A recorded
number that no check compares against is a note, not a pin: the tree could stop being the
recorded tree between any two commits and the only signal would be a human remembering.

That is not hypothetical in this estate. The modules are UNAUDITED right now precisely
because a rename (a later change) moved the tree off the last audited baseline, and **no bless
lineage survives a rename** — the kind of change that is invisible in a diff review and
total in its effect.

WHAT IT ASSERTS
---------------
1. The live module hash of each artifact module equals its recorded pin.
2. The pin block names an AUDIT STATUS, and that status is printed on every run — loudly
 when it is UNAUDITED. A pin whose status nobody states drifts into being read as
 "audited" by anyone who sees a green gate.
3. The namespace the hash was computed under is the namespace the recorded identity names.
 The namespace is INSIDE the module source, so a repatch changes the hash; a probe still
 pointing at the old namespace would silently hash a module that is not the one deploying.

WHY THE MODULE HASH AND NOT A FILE CHECKSUM
-------------------------------------------
Pact's module hash covers the PARSED code and its dependency hashes — comments and `@doc`
strings are outside it (measured twice for the design record). A file checksum would go red on every
comment edit, which trains the operator to re-pin without looking, and would go GREEN for a
dependency change that alters semantics. The module hash is the thing that actually decides
whether an audit of the reviewed source is an audit of what deploys.

🔴 WHEN THIS GOES RED, RE-PINNING IS THE LAST STEP, NOT THE FIRST. The tree has stopped
being the baseline tree. Either revert, or record the new hashes AND reset the audit status
to UNAUDITED in the same commit. Silently copying the new hash over the old one is the
whole defect this gate exists to make impossible.

SCOPE: the artifact only — `SPT` + `SPT-launch` (a later amendment keeps
`a separate gas-sponsorship module` out of the first deployment). Read that absence as a scope
decision, never as coverage.

EXIT: 0 the tree IS the recorded baseline · 1 it is not · 2 tooling failure (never a pass).
"""
import importlib.util
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARTIFACT = ('SPT', 'SPT-launch')


def load_deploy_budget():
    """Reuse `deploy-budget.py`'s REPL probe rather than writing a second one.

 A second hand-rolled bootstrap is a second chance to load the artifact differently
 from the way the deploy gate loads it — and then the two gates would be pinning
 different objects while both printing a hash.
 """
    spec = importlib.util.spec_from_file_location(
        'deploy_budget', os.path.join(HERE, 'deploy-budget.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main(argv):
    args = dict(zip(argv[::2], argv[1::2]))
    cfg_path = args.get('--config')
    mod_dir = args.get('--modules')
    test_dir = args.get('--test-dir')
    if not (cfg_path and mod_dir and test_dir):
        print('  usage: artifact-baseline.py --config <mainnet-config.json> '
              '--modules <pact/modules> --test-dir <pact/test>')
        return 2

 # FAILS CLOSED. `pact` absent is a tooling failure, never a skip: an unrunnable check
 # is not a passed check, and this one's entire job is to refuse to be assumed.
    if not shutil.which('pact'):
        print('  FAILED — `pact` not found. This gate FAILS CLOSED: the baseline can only be')
        print('           verified by loading the artifact, and an unverified baseline is not')
        print('           a verified one.')
        return 2

    try:
        with open(cfg_path, encoding='utf-8') as fh:
            cfg = json.load(fh)
    except (OSError, ValueError) as exc:                                # noqa: BLE001
        print('  FAILED — cannot read %s (%s)' % (cfg_path, exc))
        return 2

    pins = cfg.get('_module_hashes')
    if not pins:
        print('  FAILED — %s carries no `_module_hashes` block. The pin IS the check; with no'
              % cfg_path)
        print('           pin there is nothing to compare, so this is a tooling failure, never')
        print('           a pass.')
        return 2

    status = pins.get('audit_status')
    if not status:
        print('  FAILED — the pin block states no `audit_status`. A pin without a stated audit')
        print('           status gets read as "audited" by whoever sees this gate go green.')
        return 2

    ns = cfg.get('ns')
    if not ns:
        print('  FAILED — %s carries no `ns`.' % cfg_path)
        return 2

    db = load_deploy_budget()

 # The namespace is INSIDE the module source, so the hash is namespace-dependent. If the
 # probe and the recorded identity disagree, every hash below describes a module that is
 # not the one that deploys — and `describe-module` would fail confusingly rather than
 # loudly. Assert it instead.
 # 🔴 THE PROBE NOW DERIVES THE NAMESPACE FROM THE SOURCE (a later change), so the mismatch this
 # check was written to catch is unrepresentable rather than merely detected: there is no
 # second copy of the namespace to disagree with the first. What must still be asserted is
 # that the SOURCE carries the namespace this file records — same guarantee, checked against
 # the thing that actually deploys instead of against a literal in a sibling script.
    if '{ns}' not in db.HASH_PROBE:
        print('  FAILED — deploy-budget.py\'s HASH_PROBE no longer derives the namespace.')
        print('           If it has been re-hardcoded, this gate can no longer tell whether the')
        print('           probe and the source agree. Restore the {ns} placeholder.')
        return 2
 # EVERY artifact module, named explicitly — not ARTIFACT[0], not a guessed directory.
    src_ns = db._source_namespace(*[os.path.join(mod_dir, n + '.pact') for n in ARTIFACT])
    if src_ns != ns:
 # 🔴 SAY WHAT WAS COMPARED, NOT WHAT WE GUESS HAPPENED. This used to assert "repatched
 # on one side only", which was reproduced FALSE in two cases: a comment-only edit, and a
 # correct 7/7 repatch. Both printed a confident wrong cause (delta an internal review verification).
        print('  FAILED — the artifact source carries namespace %s; ops/mainnet-config.json'
              % src_ns)
        print('           records %s. These must agree: the namespace is INSIDE the module, so' % ns)
        print('           it is part of the hash this gate pins. One of the two is wrong — this')
        print('           gate cannot tell you which. `ops/check-namespace.sh <ns>` shows every')
        print('           literal and which file it is in.')
        return 2

    paths = {}
    for name in ARTIFACT:
        p = os.path.join(mod_dir, name + '.pact')
        if not os.path.isfile(p):
            print('  FAILED — artifact module missing: %s' % p)
            return 2
        paths[name] = p

    findings = []
    for name in ARTIFACT:
        want = pins.get(name)
        if not want:
            print('  FAILED — no recorded hash for artifact module `%s`. Every shipping module'
                  % name)
            print('           needs a pin, or the baseline covers only part of what deploys.')
            return 2
        got, err = db.module_hash(name, paths, test_dir)
        if got is None:
            print('  FAILED — could not load %s to derive its hash: %s' % (name, err))
            return 2
        if got != want:
            findings.append((name, want, got))
        else:
            print('  %-20s %s  == recorded baseline' % (name, got))

    print('  BASELINE AUDIT STATUS: %s' % status)
    if pins.get('as_of'):
        print('  recorded: %s' % pins['as_of'])
    if str(status).upper().startswith('UNAUDITED'):
        print('  🔴 The recorded baseline is UNAUDITED. This gate proves the tree still IS the')
        print('     recorded tree; it says NOTHING about that tree having been reviewed. Do not')
        print('     read a green line here as an audit.')

    if findings:
        print('  FAILED — the artifact is NO LONGER the recorded baseline:')
        for name, want, got in findings:
            print('    %s' % name)
            print('      recorded: %s' % want)
            print('      actual:   %s' % got)
        print('           A module hash changes only when the PARSED CODE or a dependency hash')
        print('           changes — comments and @doc are outside it — so this is a semantic')
        print('           change, not formatting. Revert it, or record the new hashes AND reset')
        print('           `audit_status` to UNAUDITED in the SAME commit. Copying the new hash')
        print('           over the old one and leaving the status alone is the defect this gate')
        print('           exists to prevent.')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
