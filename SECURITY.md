# Reporting a security issue

**Open a GitHub security advisory on this repository** — Security → Report a vulnerability. It is
private until we publish it, it reaches us immediately, and it depends on no mailbox of ours being
configured. That is the route we can promise today, so it is the one we publish.

**No GitHub account?** Write to **contact@smartpacts.io** saying only that you have a security
report — not the details — and we will set up a private channel with you from there.

There is **no bug bounty**. We would rather say that plainly than imply one.

## What we commit to

- An acknowledgement within **72 hours**, from a person.
- An assessment, with our reasoning, within **10 days** — including when we conclude it is not a
  problem, and why.
- Credit in the fix, unless you ask us not to.

## What helps

The contracts are two Pact modules and they are all in this repository. A report that names a
**function and a condition** — even without a working exploit — is more useful than a scanner
result. If you can express it as a failing `.repl` case against `pact/test/`, that is ideal, but
it is not required.

## Scope

In scope: `pact/modules/`, `deploy-bytes/`, and the gates under `.github/scripts/` that back the
claims in `README.md` and `VERIFY.md`.

Out of scope: the vendored Kadena fixtures under `pact/test/fixtures/` (report those to Kadena).

These contracts have run on Kadena mainnet (`mainnet01`) since 2026-08-28, and the code on chain
is the code in `deploy-bytes/` — `VERIFY.md` §3 is how you check that yourself. So a report
against this repository is a report about what is running.

## Please do not

Test against mainnet. The contracts are live there. A devnet reproduces everything, and the whole
suite runs offline with `pact/test/run-tests.sh`.
