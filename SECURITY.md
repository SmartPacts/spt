# Reporting a security issue

**Email: security@smartpacts.io** — or open a GitHub security advisory on this repository
(Security → Report a vulnerability), which is private until we publish it.

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

Out of scope: the vendored Kadena fixtures under `pact/test/fixtures/` (report those to Kadena),
and anything about a deployment that does not exist yet — at the time of writing these contracts
are **not on any network**.

## Please do not

Test against mainnet. There is nothing deployed to test against, and when there is, a devnet
reproduces everything: the whole suite runs offline with `pact/test/run-tests.sh`.
