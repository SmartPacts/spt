# Verifying this repository

Four separate claims, in increasing order of what they prove. Three of them — 1, 2 and 4 — you
can check right now, with no network. Only 3 needs the contracts to be deployed, which at the
time of writing they are not.

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

`strip-for-deploy.py` removes `;` comments — the `;;` blocks and the short trailing ones alike —
along with the blank lines they leave behind, and touches nothing else: no code, and no `@doc`. If that prints `identical` for both,
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

Save this as `fetch-onchain.py`. It is read-only: it signs nothing and sends nothing.
`/local` takes a full command envelope rather than a bare expression, which is why this is a
script and not a one-line `curl`.

```python
#!/usr/bin/env python3
"""Print the source the chain is running for one module. Read-only."""
import json, sys, time, base64, hashlib, urllib.request

module  = sys.argv[1]
chain   = sys.argv[2] if len(sys.argv) > 2 else "0"
network = sys.argv[3] if len(sys.argv) > 3 else "mainnet01"
host    = sys.argv[4] if len(sys.argv) > 4 else "https://api.chainweb-community.org"

cmd = json.dumps({
    "networkId": network,
    "payload": {"exec": {"data": {}, "code": '(describe-module "%s")' % module}},
    "signers": [],
    "meta": {"creationTime": int(time.time()) - 60, "ttl": 600, "gasLimit": 150000,
             "chainId": chain, "gasPrice": 1e-8, "sender": ""},
    "nonce": "verify",
}, separators=(",", ":"))

digest = hashlib.blake2b(cmd.encode(), digest_size=32).digest()
body = json.dumps({
    "cmd": cmd,
    "hash": base64.urlsafe_b64encode(digest).decode().rstrip("="),
    "sigs": [],
}).encode()

url = "%s/chainweb/0.0/%s/chain/%s/pact/api/v1/local" % (host, network, chain)
req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
res = json.load(urllib.request.urlopen(req, timeout=60))["result"]
if res["status"] != "success":
    sys.exit("chain refused the read: %s" % json.dumps(res)[:300])
sys.stdout.write(res["data"]["code"])
```

```bash
NS=n_48867b242317a0216a67f8c7ca26696b5878e0e3

# 1. ask the chain for the module's source
python3 fetch-onchain.py "$NS.SPT" 0 mainnet01 > /tmp/onchain-SPT.pact

# 2. take the module form out of the deploy payload. The payload is a whole
#    transaction in THREE parts — a namespace line and keyset checks, then the
#    module, then a create-table footer — while describe-module returns the
#    module and nothing else. Stop at the module's closing paren: ,/^)$/p
sed -n '/^(module SPT /,/^)$/p' deploy-bytes/SPT.pact > /tmp/repo-SPT.pact

# 3. compare
diff -u /tmp/repo-SPT.pact /tmp/onchain-SPT.pact && echo "the chain is running these bytes"
```

🔴 **Do not compare the whole of `deploy-bytes/SPT.pact` against what the chain returns**,
and do not extract to end-of-file either. `describe-module` returns the module form ALONE. The
payload has a preamble before it AND a `create-table` footer after it, so `,$p` swallows the
footer and reports a false mismatch — MEASURED against the live deployment: 1,340 lines extracted
against the chain's 1,323. `,/^)$/p` stops at the module's closing paren and comes out clean.

**This comparison has been run against the real deployment: the code on mainnet chain 0 is
BYTE-IDENTICAL to the module form in `deploy-bytes/SPT.pact`.**

If step 3 prints no differences, the deployed program is the one in this repository. That is the
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
  by a change detector rather than a behavioural test; the published review names them.
- **Anything about a network other than the one you queried.** SPT deploys to all 20
  chains, and each is a separate deployment. Step 3 checks the chain you point it at.
