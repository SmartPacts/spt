// compare-lineages.mjs — prove the relationship between the two contract lineages.
//
// contracts/testnet06/ is the LIVE deployment (byte-verifiable on-chain: verify.mjs).
// contracts/mainnet/  is the RELEASE CANDIDATE — not deployed, published for review.
//
// The claim this script checks: the mainnet candidate is EXACTLY the tested,
// deployed system minus an enumerated list of differences. Nothing else may
// differ. The whitelist below IS the authoritative list of differences — read
// it top to bottom and you have read the entire testnet-vs-mainnet delta
// (prose version: docs/TESTNET-VS-MAINNET.md).
//
// Usage:  cd scripts && node compare-lineages.mjs     (exits non-zero on drift)
import { readFileSync } from 'node:fs';

const MODULES = ['smartpacts-shares', 'smartpacts-ipo', 'smartpacts-gas-station'];
const NS = 'n_d97ffd2ca290429b5dc85ce551a8d07d038e9641'; // the testnet06 namespace

// ---------------------------------------------------------------------------
// THE DIFFERENCE WHITELIST — each entry names one allowed difference, and how
// both sides are normalized to a common token so everything else must match.
// ---------------------------------------------------------------------------
const DIFFS = [
  {
    name: 'review banner (mainnet only): the not-deployed disclaimer header',
    apply(side, src) {
      if (side !== 'mainnet') return src;
      // strip the leading banner comment block (ends at its closing ==== line)
      const lines = src.split('\n');
      let end = 0;
      for (let i = 1; i < lines.length; i++) {
        if (lines[i].startsWith(';; ====') && i > 2) { end = i + 1; break; }
      }
      return lines.slice(end).join('\n');
    },
  },
  {
    name: 'admin keyset name: testnet hardcodes the namespace; mainnet derives it from the deploy transaction (read-msg \'ns\') — no substitution step at deploy',
    apply(side, src) {
      const token = '  (defconst ADMIN-KS <NS>.spt-admin)\n';
      if (side === 'testnet06') {
        return src.replace(new RegExp(`^\\s*\\(defconst ADMIN-KS "${NS}\\.spt-admin"\\)[^\\n]*\\n`, 'm'), token);
      }
      return src.replace(/^\s*;; The admin keyset name is DERIVED[^\n]*\n\s*;;[^\n]*\n\s*\(defconst ADMIN-KS \(format "\{\}\.spt-admin" \[\(read-msg 'ns\)\]\)\)\n/m, token);
    },
  },
  {
    name: 'gas-station allowlist: testnet hardcodes the namespace in the two sponsored-call prefixes; mainnet derives them the same way',
    apply(side, src) {
      const token = '  (defconst SPONSORED-PREFIXES <NS>-derived)\n';
      if (side === 'testnet06') {
        const re = new RegExp(`^\\s*\\(defconst SPONSORED-PREFIXES:\\[string\\]\\n\\s*\\[ "\\(${NS}\\.smartpacts-shares\\.cast-vote "\\n\\s*"\\(${NS}\\.smartpacts-shares\\.claim-dividends " \\]\\)\\n`, 'm');
        return src.replace(re, token);
      }
      return src.replace(/^\s*\(defconst SPONSORED-PREFIXES:\[string\]\n\s*;; Derived from[^\n]*\n\s*\[ \(format "\(\{\}\.smartpacts-shares\.cast-vote " \[\(read-msg 'ns\)\]\)\n\s*\(format "\(\{\}\.smartpacts-shares\.claim-dividends " \[\(read-msg 'ns\)\]\) \]\)\n/m, token);
    },
  },
  {
    name: 'token identity constants (mainnet only): NAME/SYMBOL defconsts — self-documentation via describe-module; added to the candidate pre-freeze because constants are compiled code (hash-relevant), so they can never be added after deploy',
    apply(side, src) {
      if (side !== 'mainnet') return src;
      return src.replace(/^\s*;; Token identity — self-documentation[\s\S]*?\(defconst SYMBOL:string "SPT"\)\n/m, '');
    },
  },
  {
    name: 'migrate-adr015 (testnet only): the one-shot data migration that healed the in-place dividend-accrual upgrade of 2026-07-05 — test-event lifecycle; a fresh mainnet deployment writes the full schema at init and never migrates',
    apply(side, src) {
      if (side !== 'testnet06') return src;
      const lines = src.split('\n');
      const s = lines.findIndex((l) => l.trim().startsWith('(defun migrate-adr015:string'));
      if (s < 0) return src;
      let e = lines.findIndex((l, i) => i > s && l.includes('"already migrated"))))'));
      if (e + 1 < lines.length && lines[e + 1].trim() === '') e += 1;
      return lines.slice(0, s).concat(lines.slice(e + 1)).join('\n');
    },
  },
];

let fail = 0;
for (const m of MODULES) {
  let t = readFileSync(new URL(`../contracts/testnet06/${m}.pact`, import.meta.url), 'utf8');
  let c = readFileSync(new URL(`../contracts/mainnet/${m}.pact`, import.meta.url), 'utf8');
  const applied = [];
  for (const d of DIFFS) {
    const t2 = d.apply('testnet06', t);
    const c2 = d.apply('mainnet', c);
    if (t2 !== t || c2 !== c) applied.push(d.name);
    t = t2; c = c2;
  }
  if (t === c) {
    console.log(`✅ ${m}: identical after the whitelisted differences`);
    for (const a of applied) console.log(`     · ${a}`);
  } else {
    fail++;
    console.log(`❌ ${m}: DIFFERS beyond the whitelist — the lineages have drifted`);
    const tl = t.split('\n'), cl = c.split('\n');
    for (let i = 0; i < Math.max(tl.length, cl.length); i++) {
      if (tl[i] !== cl[i]) {
        console.log(`     first divergence at normalized line ${i + 1}:`);
        console.log(`       testnet06: ${(tl[i] ?? '<absent>').slice(0, 120)}`);
        console.log(`       mainnet:   ${(cl[i] ?? '<absent>').slice(0, 120)}`);
        break;
      }
    }
  }
}
console.log(fail
  ? '\n❌ lineage drift — fix before merging'
  : '\n✅ the mainnet candidate is exactly the deployed, tested system minus the differences listed above');
process.exit(fail ? 1 : 0);
