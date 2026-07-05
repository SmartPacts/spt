// verify.mjs — check this repository against the live network, trustlessly.
//
// For each of the three modules, on every chain (0–19):
//   1. fetch the module the node stores (`describe-module`) via a free, read-only
//      /local call — no keys, no account, no gas;
//   2. byte-compare the stored source against the file in contracts/;
//   3. check the module hash is identical across all chains;
//   4. report the deploying transaction's request key (look it up in the explorer
//      to see the full signed deployment).
//
// Usage:  cd scripts && npm install && node verify.mjs
// Exits non-zero on any mismatch.
import { readFileSync } from 'node:fs';
import blake from 'blakejs';

const NS = 'n_d97ffd2ca290429b5dc85ce551a8d07d038e9641';
const API = process.env.SPT_API ?? 'https://api.testnet.chainweb-community.org';
const NETWORK = 'testnet06';
const CHAINS = Array.from({ length: 20 }, (_, i) => String(i));
const MODULES = ['smartpacts-shares', 'smartpacts-ipo', 'smartpacts-gas-station'];

// The on-chain module record stores the `(module …)` form: the file's deployment
// wrapper (header comment, namespace, keyset definition, table-creation footer) is
// part of the deploy transaction but not of the stored module body.
function moduleForm(src) {
  const lines = src.split('\n');
  const s = lines.findIndex((l) => l.startsWith('(module '));
  const e = lines.findIndex((l, i) => i > s && l === ')');
  if (s < 0 || e < 0) throw new Error('module form not found');
  return lines.slice(s, e + 1).join('\n');
}

function b64url(bytes) {
  return Buffer.from(bytes).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// Minimal read-only /local command (unsigned; empty signer set).
async function local(code, chainId) {
  const cmd = JSON.stringify({
    networkId: NETWORK,
    payload: { exec: { data: {}, code } },
    signers: [],
    meta: { creationTime: Math.floor(Date.now() / 1000), ttl: 600, gasLimit: 150000, gasPrice: 1e-8, chainId, sender: 'verify' },
    nonce: new Date().toISOString(),
  });
  const hash = b64url(blake.blake2b(Buffer.from(cmd, 'utf8'), undefined, 32));
  const res = await fetch(`${API}/chainweb/0.0/${NETWORK}/chain/${chainId}/pact/api/v1/local`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ cmd, hash, sigs: [] }),
  });
  if (!res.ok) throw new Error(`chain ${chainId}: HTTP ${res.status} ${await res.text()}`);
  const r = await res.json();
  if (r?.result?.status !== 'success') throw new Error(`chain ${chainId}: ${JSON.stringify(r?.result?.error)}`);
  return r.result.data;
}

let failures = 0;
for (const m of MODULES) {
  const localSrc = moduleForm(readFileSync(new URL(`../contracts/testnet06/${m}.pact`, import.meta.url), 'utf8'));
  const results = await Promise.all(CHAINS.map(async (c) => {
    const d = await local(`(describe-module "${NS}.${m}")`, c);
    return { c, match: d.code === localSrc, hash: d.hash, rk: d.tx_hash };
  }));
  const hashes = new Set(results.map((r) => r.hash));
  const bad = results.filter((r) => !r.match);
  const okay = bad.length === 0 && hashes.size === 1;
  if (!okay) failures++;
  console.log(`${okay ? '✅' : '❌'} ${NS}.${m}`);
  console.log(`     source: ${bad.length === 0 ? 'byte-identical to contracts/ on all 20 chains' : `MISMATCH on chains ${bad.map((r) => r.c).join(',')}`}`);
  console.log(`     hash:   ${hashes.size === 1 ? [...hashes][0] : `NOT UNIFORM (${hashes.size} values)`}`);
  console.log(`     deploy request key (chain 0): ${results[0].rk}`);
}
console.log(failures ? `\n❌ ${failures} module(s) failed verification` : '\n✅ everything this repository claims about the deployed code checks out');
process.exit(failures ? 1 : 0);
