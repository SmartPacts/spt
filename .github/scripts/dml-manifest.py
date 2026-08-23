#!/usr/bin/env python3
"""Pin the DML surface of a table as a NAMED MANIFEST — (function, op) — not a count.

WHY THIS REPLACES A COUNT (a later change a finding)
---------------------------------------
`the project notes` states the whole product rests on `tallies` having exactly TWO MUTATORS
(`cast-vote` and the release loop inlined in `debit`). The gate defending that claim
counted DML sites — `write=0, insert=1, update=3` — and printed *"update=3 across TWO
mutators — unchanged"*.

**A count cannot see WHICH sites.** Measured: deleting the legitimate `(update tallies …)`
from `debit`'s release loop and planting one inside the PERMISSIONLESS `close-proposal`
(written with two spaces and a line break) kept the count at 3, and the gate printed
"unchanged" while the mutator set had changed from {cast-vote, debit} to
{cast-vote, close-proposal}. Add-only (3→4) and delete-only (3→2) both went red; only
RELOCATION was invisible — and relocation is exactly what an attacker-shaped edit looks
like. The gate's own message asserted a property it did not measure, which is the same
defect a later change fixed on the `accounts` gate recurring inside the fix for it.

So the manifest names the OWNING FUNCTION of every DML site. A relocation changes the
owner, so it cannot pass.

WHY IT NOW COVERS EVERY TABLE (a later change, an internal review a finding)
-----------------------------------------------------------
Two tables were pinned — `accounts` and `tallies`. a finding demonstrated the gap rather than
arguing it: a planted permissionless writer zeroing `sum-pending` in the **`state`** table
passed every suite and every correctness gate. `state` was not special; 12 of the module
set's 14 tables had no pin at all.

So `--manifest <file>` checks the pinned surface of EVERY table, and adds the assertion a
per-table invocation structurally cannot make: **COVERAGE** — the set of tables pinned must
equal the set of `deftable` declarations in the source. Without it, `git add` of a new table
with a new writer trips nothing, because nothing names the table to check.

DISCIPLINE
----------
* Comment- and string-aware, whitespace-tolerant (a writer split across lines still counts).
* Owning function resolved by definition order, so a site moved between functions is seen.
* A check that inspected ZERO sites FAILS — never passes. Likewise zero modules, zero
 tables, or a module whose source declares no tables at all.
* Self-tests before it scans anything — including the coverage path, whose failure mode is
 silence.

USAGE
-----
 dml-manifest.py <file.pact> <table> <manifest-json> # single table, inline JSON
 dml-manifest.py --manifest <surface.json> [--root <dir>] # every table, with coverage

EXIT: 0 manifest matches · 1 surface moved · 2 tooling failure.
"""
import json
import os
import re
import sys


def strip_comments(src):
    """Blank ;; comments, preserving offsets and string contents."""
    out, i, n, instr = [], 0, len(src), False
    while i < n:
        c = src[i]
        if instr:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(src[i + 1]); i += 2; continue
            if c == '"':
                instr = False
            i += 1; continue
        if c == '"':
            instr = True; out.append(c); i += 1; continue
        if c == ';':
            while i < n and src[i] != '\n':
                out.append(' '); i += 1
            continue
        out.append(c); i += 1
    return ''.join(out)


def definitions(src):
    """[(offset, name)] for every defun/defpact/defcap, in source order."""
    return sorted((m.start(), m.group(2)) for m in
                  re.finditer(r'\(\s*(defun|defpact|defcap)\s+([A-Za-z0-9!?<>=_-]+)', src))


def owner_of(defs, off):
    cur = '<top-level>'
    for start, name in defs:
        if start <= off:
            cur = name
        else:
            break
    return cur


def dml_sites(src, table):
    """[(op, owning_function)] for every write/insert/update against `table`."""
    clean = strip_comments(src)
    defs = definitions(clean)
    out = []
    for m in re.finditer(r'\(\s*(write|insert|update)\s+' + re.escape(table) + r'\b', clean):
        out.append((m.group(1), owner_of(defs, m.start())))
    return sorted(out)


def declared_tables(src):
    """{table-name} for every `(deftable NAME:{schema})` in the source.

 This is the COVERAGE input, so it is deliberately comment-stripped: a `deftable`
 inside a commented-out block is not a table, and — the direction that matters — a
 real `deftable` must never be missed because the regex was too strict about the
 type annotation. Pact accepts `(deftable t:{s})` and bare `(deftable t)`.
 """
    clean = strip_comments(src)
    return {m.group(1) for m in
            re.finditer(r'\(\s*deftable\s+([A-Za-z0-9!?<>=_-]+)', clean)}


SELFTEST = '''
(module m G
  (deftable tallies:{t})
  (deftable other:{o})
  ;; (deftable ghost:{g})       a commented-out table is not a table
  (defun alpha ()
    ;; (update tallies "in a comment must not count")
    (update tallies k v))
  (defun beta ()
    (update  tallies
       k v)                      ; two spaces AND a line break
    (insert tallies k v))
  (defun gamma () (write other k v)))
'''


def selftest():
    got = dml_sites(SELFTEST, 'tallies')
    want = [('insert', 'beta'), ('update', 'alpha'), ('update', 'beta')]
    if got != want:
        print('  SELF-TEST FAILED: expected %r, got %r' % (want, got))
        return False
 # The coverage path fails SILENTLY if declared_tables under-reports, so exercise it:
 # both real tables found, the commented-out one not.
    tabs = declared_tables(SELFTEST)
    if tabs != {'tallies', 'other'}:
        print('  SELF-TEST FAILED: declared_tables expected {tallies, other}, got %r' % tabs)
        return False
    return True


def check_table(src, path, table, want, why):
    """Return True if `table`'s DML surface in `src` matches `want`. Prints on failure."""
    got = dml_sites(src, table)
    if not got and want:
        print('  FAILED — ZERO `%s` DML sites found in %s. A check that inspected nothing is '
              'not a passed check.' % (table, path))
        return False
    if got != want:
        print('  FAILED — the `%s` DML surface MOVED in %s (manifest vs actual):' % (table, path))
        for x in sorted(set(want) - set(got)):
            print('    MISSING  %-7s in %s   (the manifest names it; the code no longer has it)' % x)
        for x in sorted(set(got) - set(want)):
            print('    UNEXPECTED %-7s in %s   (the code has it; the manifest does not)' % x)
        if sorted(op for op, _ in want) == sorted(op for op, _ in got):
            print('    🔴 NOTE: the COUNTS ARE UNCHANGED — this is a RELOCATION, which is exactly')
            print('       what a count-based gate cannot see (a later change a finding). Do not "fix" this by')
            print('       editing the manifest: a mutator moving into another function is a')
            print('       DESIGN CHANGE needing an ADR.')
        if why:
            print('    WHY THIS TABLE IS PINNED: %s' % why)
        return False
    return True


def run_manifest(manifest_path, root):
    """Check every table of every module named in the manifest, plus COVERAGE."""
    try:
        with open(manifest_path, encoding='utf-8') as fh:
            spec = json.load(fh)
    except (OSError, ValueError) as exc:                               # noqa: BLE001
        print('  FAILED — cannot read manifest %s (%s)' % (manifest_path, exc))
        return 2

    modules = spec.get('modules') or {}
    if not modules:
        print('  FAILED — the manifest names ZERO modules. A check that inspected nothing '
              'is not a passed check.')
        return 2

    ok, sites_seen, tables_seen = True, 0, 0
    for rel in sorted(modules):
        path = os.path.join(root, rel) if root else rel
        try:
            src = open(path, encoding='utf-8').read()
        except OSError as exc:
            print('  FAILED — cannot read %s (%s)' % (path, exc))
            return 2

        pinned = modules[rel]
        if not pinned:
            print('  FAILED — %s is in the manifest with ZERO tables pinned.' % rel)
            return 2

 # --- COVERAGE: the pinned set must BE the declared set ------------------
 # 🔴 This is the assertion a per-table invocation cannot make. Without it, adding a
 # table and a writer to it trips nothing, because nothing names the table to check.
        declared = declared_tables(src)
        if not declared:
            print('  FAILED — %s declares NO tables; the coverage check inspected nothing.' % rel)
            return 2
        missing = declared - set(pinned)
        extra = set(pinned) - declared
        if missing or extra:
            ok = False
            print('  FAILED — table COVERAGE moved in %s:' % rel)
            for t in sorted(missing):
                print('    UNPINNED  %-15s a table exists with NO pinned DML surface. Add it here'
                      % t)
                print('    %17s with its site list — that is the a finding shape.' % '')
            for t in sorted(extra):
                print('    PHANTOM   %-15s pinned here but no longer declared in the module.' % t)

        for table in sorted(set(pinned) & declared):
            entry = pinned[table]
            want = sorted(tuple(x) for x in entry.get('sites', []))
            if not check_table(src, rel, table, want, entry.get('why')):
                ok = False
            sites_seen += len(want)
            tables_seen += 1

    if sites_seen == 0:
        print('  FAILED — the manifest pins ZERO DML sites in total.')
        return 2
    if ok:
        print('  %d table(s) across %d module(s), %d DML site(s) — manifest and coverage match'
              % (tables_seen, len(modules), sites_seen))
    return 0 if ok else 1


def main(argv):
    if not argv:
        print('  usage: dml-manifest.py <file.pact> <table> <manifest-json>')
        print('         dml-manifest.py --manifest <surface.json> [--root <dir>]')
        return 2
    if not selftest():
        return 2

    if argv[0] == '--manifest':
        if len(argv) < 2:
            print('  usage: dml-manifest.py --manifest <surface.json> [--root <dir>]')
            return 2
        args = dict(zip(argv[::2], argv[1::2]))
        return run_manifest(args['--manifest'], args.get('--root', ''))

    if len(argv) < 3:
        print('  usage: dml-manifest.py <file.pact> <table> <manifest-json>')
        return 2
    path, table, manifest_raw = argv[0], argv[1], argv[2]
    try:
        want = sorted(tuple(x) for x in json.loads(manifest_raw))
    except Exception as exc:                                       # noqa: BLE001
        print('  FAILED — manifest is not valid JSON: %s' % exc)
        return 2
    try:
        src = open(path, encoding='utf-8').read()
    except OSError as exc:
        print('  FAILED — cannot read %s (%s)' % (path, exc))
        return 2

    if not check_table(src, path, table, want, None):
        return 1
    got = dml_sites(src, table)
    owners = sorted({fn for _, fn in got})
    print('  %d site(s) across %d function(s): %s — manifest matches'
          % (len(got), len(owners), ', '.join(owners)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
