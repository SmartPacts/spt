# Contributing

**Issues and questions are very welcome. Pull requests against the contracts are not.**

That is not unfriendliness — it is what the repository is for. `pact/modules/` and
`deploy-bytes/` are a reviewed artifact pinned at two specific module hashes, and a merged change
would silently invalidate both the recorded baseline and the review in `audits/`. If you have
found something wrong, an issue describing it is worth far more to us than a patch, because the
fix has to go back through review either way.

**If it is a security issue, use [`SECURITY.md`](SECURITY.md) instead of a public issue.**

Corrections to the documentation — `README.md`, `VERIFY.md`, `docs/` — are a different matter, and
a PR is welcome. Those are not part of the artifact and cannot move a hash.

## If you are reviewing the code

Start with [`docs/SPT-WHAT-IT-DOES.md`](docs/SPT-WHAT-IT-DOES.md) for what it is meant to do, then
`pact/modules/` for how, then `audits/` for what an independent reviewer already found. Run
`pact/test/run-tests.sh` before you believe any of it — including this sentence.
