# Verifying this repository

Three separate claims, in increasing order of what they prove. The first two you can check right
now. The third needs the contracts to be deployed, which at the time of writing they are not.

You need the [Pact 5.4ce](https://github.com/kda-community/pact-5) binary — the Community Edition
engine this artifact is measured against — plus `python3` and `sha256sum`.

---

## 1. The published bytes are the bytes in `SHA256SUMS`

```bash
cd deploy-bytes && sha256sum -c SHA256SUMS
```

Weak on its own — it only says the file matches a checksum published in the same commit. It is
here so a later tampering of one file without the other is loud.

## 2. 🔴 The annotated source and the deploy bytes are the same program

This is the one worth running, because it is the claim the repository's structure rests on.

```bash
for M in SPT SPT-launch; do
  python3 .github/scripts/strip-for-deploy.py pact/modules/$M.pact \
    | diff -u deploy-bytes/$M.pact - && echo "$M: identical"
done
```

`strip-for-deploy.py` removes `;;` comments and nothing else. If that prints `identical` for both,
then every annotation in `pact/modules/` is provably **absent** from what deploys, and the
commentary cannot be hiding a behavioural difference. CI runs this on every push.

Note this is a **byte** comparison, which is strictly stronger than comparing module hashes —
hash equality would tolerate arbitrary comment differences, which is exactly what is being ruled
out here.

## 3. The chain is running this code

**Only possible once the modules are deployed.**

🔴 **Do not compare the hash in `verification/artifact-baseline.json` to the hash `describe-module`
reports. They will never be equal, and that is not a problem with either one.**

A Pact module hash covers the hashes of its **dependencies**. This repository's test suite loads a
vendored `coin` fixture (`pact/test/fixtures/coin.pact`) so it can run without a network, and that
fixture is not byte-identical to the `coin` contract live on mainnet. Their hashes differ, so
SPT's hash differs too — measured: adding one unused function to the fixture, touching **zero**
bytes of SPT, moves SPT's hash. A verification script that compares those two numbers can only
ever fail, and would say nothing about whether the code matches.

**Compare the code, then hash it yourself under one fixed environment:**

```bash
NS=n_48867b242317a0216a67f8c7ca26696b5878e0e3
API=https://api.chainweb.com/chainweb/0.0/mainnet01/chain/0/pact/api/v1/local

# 1. ask the chain for the module's source
curl -s -X POST "$API" -H 'Content-Type: application/json' \
  -d "{\"exec\":{\"data\":{},\"code\":\"(describe-module \\\"$NS.SPT\\\")\"}}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["data"]["code"])' \
  > /tmp/onchain-SPT.pact

# 2. compare it to the bytes this repo publishes
diff -u deploy-bytes/SPT.pact /tmp/onchain-SPT.pact && echo "the chain is running these bytes"
```

If step 2 prints no differences, the deployed program is the one in this repository. That is the
claim that matters, and it does not depend on hashes agreeing across environments.

**If they DISAGREE: trust the chain, not this repository.** The chain is what executes and what
holds value. A mismatch means this repository is stale, wrong, or tampered with — in that order of
likelihood — and it should be reported (see `SECURITY.md`) rather than worked around.

## 4. The tests pass on your machine, not just ours

```bash
cd pact/test && ./run-tests.sh
```

Runs every suite, every negative fixture, and every gate — including a check that both module
hashes still equal the recorded baseline, and that the deploy payload still fits the measured gas
ceiling. Prints `ALL SUITES PASS`, or names exactly which gate failed.

---

## What none of this proves

- **That the code is correct.** It proves the published source is the running program. Whether
  that program does what the documentation says is what `audits/` and your own reading are for.
- **That the tests are strong enough.** A passing suite proves the assertions hold, not that the
  assertions are demanding. Two properties in this artifact are correct as written but pinned only
  by a change detector rather than a behavioural test; the audit report names them.
- **Anything about a network other than the one you queried.** SPT deploys to all 20
  chains, and each is a separate deployment. Step 3 checks the chain you point it at.
