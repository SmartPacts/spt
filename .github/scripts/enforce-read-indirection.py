#!/usr/bin/env python3
"""Find table reads that reach an `enforce` condition THROUGH A HELPER FUNCTION.

WHY THIS EXISTS
---------------
A table read inside an `enforce` condition evaluates in read-only mode on upstream-lineage nodes
and aborts there. The REPL allows it EVERYWHERE, so no REPL test can fail. This module states the
rule in four places and let-binds everywhere else — but a cold red-team found one violation that
had survived eighteen reviews:

 (defun get-prop-count:integer () (at 'n (read prop-count PROP-COUNT-KEY))) ; a ONE-LINE reader
 ...
 (enforce (< (get-prop-count) MAX-ACTIVE-PROPOSALS) ...) ; the read, hidden

🔴 IT IS INVISIBLE TO THE OBVIOUS CHECK. `grep '(enforce (.*(read'` returns ZERO on that line,
because the read is behind a zero-arg helper. Reading for the PATTERN misses it; only resolving one
level of indirection finds it. That is this script's entire job.

🔴 AND THE FIRST VERSION OF THIS SCRIPT FAILED ITS OWN SELF-TEST — it captured a defun's body
starting at the NEXT line, so one-line readers (exactly the case above) were invisible to it too.
A checker that cannot find the bug it was written for is worse than none, which is why the
self-test below runs FIRST and the script exits non-zero if it does not fire.
"""
import re, sys, pathlib

READ = r'\((read|with-read|with-default-read|select|keys)\s'

def scan(src: str):
    code = "\n".join(re.sub(r';.*$', '', l) for l in src.split('\n'))
    readers = set()
    for m in re.finditer(r'\(defun\s+([A-Za-z0-9?!*<>=/+-]+)', code):
        nxt = re.search(r'\n  \(def', code[m.end():])
        body = code[m.end(): m.end() + (nxt.start() if nxt else 4000)]
        if re.search(READ, body):
            readers.add(m.group(1))
    hits = []
    for m in re.finditer(r'\(enforce(-one)?\s+\(', code):
        cond = code[m.start(): m.start() + 400].split('"')[0]
        for r in sorted(readers, key=len, reverse=True):
            if re.search(r'\(' + re.escape(r) + r'[\s)]', cond):
                hits.append((code[:m.start()].count('\n') + 1, r))
                break
    return readers, hits

# ---- SELF-TEST FIRST: a synthetic violation MUST be found, in the one-line shape that fooled v1.
SELF = """(module m G
 (defun peek:integer () (at 'n (read t "k")))
 (defun go () (enforce (< (peek) 32) "too many")))"""
_, self_hits = scan(SELF)
if not self_hits:
    print("SELF-TEST FAILED: the checker did not find a synthetic helper-hidden read. "
          "It would report every real module clean. Refusing to run.", file=sys.stderr)
    sys.exit(2)
# and it must NOT fire on the let-bound form
_, self_clean = scan(SELF.replace('(enforce (< (peek) 32) "too many")',
                                  '(let ((n (peek))) (enforce (< n 32) "too many"))'))
if self_clean:
    print("SELF-TEST FAILED: the checker fires on the CORRECT let-bound form. Refusing to run.", file=sys.stderr)
    sys.exit(2)

fail = 0
for p in sorted(pathlib.Path('pact/modules').glob('*.pact')):
    readers, hits = scan(p.read_text(encoding='utf-8'))
    if hits:
        fail = 1
        for line, fn in hits:
            print(f"  FAILED {p.name}:{line} — `{fn}()` reads a table and is called INSIDE an enforce "
                  f"condition. Let-bind it first: (let ((x ({fn}))) (enforce ... x ...)).")
    else:
        print(f"  {p.name}: {len(readers)} table-reading fn(s), 0 reached from inside an enforce")
print("  self-test passed first (fires on a synthetic one-line helper, silent on the let-bound form)")
sys.exit(fail)
