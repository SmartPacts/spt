#!/usr/bin/env python3
"""Produce the DEPLOYABLE build of a Pact module: the source with `;` comments removed.

WHY THIS EXISTS (the design record, founder ; forced by an internal review)
----------------------------------------------------------------------
`SPT` measured **176,205 gas against a hard 150,000 ceiling** on a
3.2 node — it could not be deployed at all. Deploy cost scales with SOURCE SIZE,
and **62.8 % of that file is comments**. Stripping them measured **78,248 gas
(52.2 %), mined OK**.

🔴 THE SAFETY ARGUMENT IS THE MODULE HASH, AND IT IS EXACT.
Pact's module hash covers the PARSED code and its dependency hashes — comments
and `@doc` strings are outside it. Measured twice before the design record was written:
stripping every comment, and separately collapsing all 66 `@doc` blocks to `"x"`,
each left the hash at `jQWplU2vb3iXCTt12VP0DW8cpTv9AH-nAhmu-v9DHqQ`.

So: **identical hash ⇒ identical semantics ⇒ an audit of the commented source IS
an audit of the stripped build**, provably rather than by assertion. It also means
bless lists, `SPT-launch`'s hash linkage and the frozen fixture are untouched.

**This script is therefore safety-critical, and the hash check is what disarms it.**
A stripper that ate a line of code would change the hash. `deploy-budget.py` and
`ops/deploy/runbook.ts` both re-derive the hash and REFUSE on mismatch. Never
deploy a stripped build without that comparison.

WHAT IT MUST NEVER DO
---------------------
 * Strip a `;` inside a string literal. Pact `;` starts a comment only OUTSIDE
 strings, and this module's error messages and `@doc` blocks contain them.
 The tokenizer below is the same string-aware shape already proven in
 `ops-deploy-gate.py` `_mask` and `run-tests.sh` `dml_count` — reused, not
 reinvented, because a third hand-rolled scanner is a third chance to be wrong.
 * Touch `@doc`. Those are CODE, not comments, and they are the only
 documentation that survives on chain (`describe-module` returns them).
 the design record keeps them, shortened to one sentence, in the SOURCE.

EXIT CODES
----------
 0 stripped source written to stdout (or --out)
 2 TOOLING FAILURE — self-test failed. Never confuse this with 0.
"""
import sys


def strip_comments(src: str) -> str:
    """Remove `;`-to-end-of-line comments that are OUTSIDE string literals.

 Blank-only lines left behind by whole-line comments are dropped; a line that
 still holds code keeps its code and loses its trailing comment. Newlines are
 preserved everywhere else so a Pact parse error still points somewhere sane.
 """
    out = []
    i, n, instr = 0, len(src), False
    while i < n:
        c = src[i]
        if instr:
            out.append(c)
            if c == '\\' and i + 1 < n:      # escape: copy the pair verbatim
                out.append(src[i + 1])
                i += 2
                continue
            if c == '"':
                instr = False
            i += 1
            continue
        if c == '"':
            instr = True
            out.append(c)
            i += 1
            continue
        if c == ';':
            while i < n and src[i] != '\n':  # drop the comment, keep the newline
                i += 1
            continue
        out.append(c)
        i += 1
    text = ''.join(out)
    return '\n'.join(l.rstrip() for l in text.split('\n') if l.strip()) + '\n'


# --- Self-test: runs on EVERY invocation, before anything real is stripped -------
# Each case is a shape this module actually contains. The string cases are the ones
# that matter: a naive stripper eats them and silently changes the code.
SELFTEST = [
 # (input, expected)
    (';; whole line\n(defun f () 1)\n', '(defun f () 1)\n'),
    ('(defun f () 1) ;; trailing\n', '(defun f () 1)\n'),
 # a `;` INSIDE a string must survive untouched
    ('(enforce false "a; b")\n', '(enforce false "a; b")\n'),
 # a quote inside a comment must not open a string
    (';; it\'s "quoted\n(f 1)\n', '(f 1)\n'),
 # escaped quote inside a string, then a real comment
    ('(f "say \\"hi\\"") ;; c\n', '(f "say \\"hi\\"")\n'),
 # multi-line @doc with continuations and a semicolon: CODE, never stripped
    ('(defun f ()\n  @doc "one; two \\\n       three"\n  1)\n',
     '(defun f ()\n  @doc "one; two \\\n       three"\n  1)\n'),
]


def selftest() -> bool:
    for idx, (src, want) in enumerate(SELFTEST):
        got = strip_comments(src)
        if got != want:
            print('  SELF-TEST FAILED (case %d)\n    in   %r\n    want %r\n    got  %r'
                  % (idx, src, want, got), file=sys.stderr)
            return False
 # and the property that makes the whole scheme safe: stripping is idempotent
    once = strip_comments(SELFTEST[0][0])
    if strip_comments(once) != once:
        print('  SELF-TEST FAILED: stripping is not idempotent', file=sys.stderr)
        return False
    return True


def main(argv):
    if not selftest():
        return 2
    if not argv:
        print('usage: strip-for-deploy.py <module.pact> [--out FILE]', file=sys.stderr)
        return 2
    src_path = argv[0]
    out_path = None
    if '--out' in argv:
        out_path = argv[argv.index('--out') + 1]
    try:
        src = open(src_path, encoding='utf-8').read()
    except OSError as exc:
        print('  FAILED — unreadable %s (%s)' % (src_path, exc), file=sys.stderr)
        return 2
    if not src.strip():
        print('  FAILED — %s is empty; refusing to emit an empty build' % src_path,
              file=sys.stderr)
        return 2
    stripped = strip_comments(src)
 # A stripped module that lost its module form is a broken strip, not a small one.
    if '(module ' not in stripped:
        print('  FAILED — the stripped build contains no module definition', file=sys.stderr)
        return 2
    if out_path:
        open(out_path, 'w', encoding='utf-8').write(stripped)
    else:
        sys.stdout.write(stripped)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
