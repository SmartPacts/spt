// compare-lineages.mjs — prove the relationship between the two contract lineages.
//
// contracts/testnet06/ is the deployment record of the public test event
// (byte-verifiable on-chain while that network serves history: verify.mjs).
// contracts/mainnet/  is the RELEASE CANDIDATE — not deployed, published for review.
//
// The claim this script checks comes in TWO parts:
//
//   1. smartpacts-shares + smartpacts-ipo: the mainnet candidate is EXACTLY
//      the tested, deployed system minus an enumerated whitelist of
//      differences. Nothing else may differ. The whitelist below IS the
//      authoritative list — read it top to bottom and you have read the
//      entire delta (prose: docs/TESTNET-VS-MAINNET.md).
//
//   2. smartpacts-gas-station: the candidate is a REDESIGN by design —
//      registry-driven sponsorship replaces the compiled-in allowlist
//      (docs/GAS-STATION.md). Line-identity would be a lie here, so instead
//      every named design delta is asserted mechanically on both sides, AND
//      the parts that MUST stay identical across station generations — the
//      guard machinery that the funded station account resolves BY NAME —
//      are extracted from both files and compared code-exact.
//
// Usage:  cd scripts && node compare-lineages.mjs     (exits non-zero on drift)
import { readFileSync } from 'node:fs';

const IDENTITY_MODULES = ['smartpacts-shares', 'smartpacts-ipo'];
const NS = 'n_d97ffd2ca290429b5dc85ce551a8d07d038e9641'; // the testnet06 namespace

// ---------------------------------------------------------------------------
// PART 1 — THE DIFFERENCE WHITELIST (shares + ipo) — each entry names one
// allowed difference, and how both sides are normalized to a common token so
// everything else must match.
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
    name: 'account-votes post-close invariant note (mainnet only, TEMPORARY): a schema-doc note recording that weight<=balance holds only while a proposal is active (inert post-close residue — the red-team O2 observation, accepted as-is). Documentation only; it will also land on testnet when that lineage is next re-frozen',
    apply(side, src) {
      if (side !== 'mainnet') return src;
      return src.replace(/^\s*;; INVARIANT SCOPE: weight <= current balance[\s\S]*?not swept \(a cleanup path would add surface for data nothing reads\)\.\n/m, '');
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

// ---------------------------------------------------------------------------
// PART 2 — THE GAS-STATION REDESIGN DELTAS + the must-stay-identical core.
// ---------------------------------------------------------------------------

// Strip comments outside strings; collapse whitespace; drop blank lines.
function stripComments(src) {
  const out = [];
  for (const line of src.split('\n')) {
    let inStr = false, cut = line.length;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (c === '"' && line[i - 1] !== '\\') inStr = !inStr;
      else if (c === ';' && !inStr) { cut = i; break; }
    }
    const kept = line.slice(0, cut).replace(/\s+/g, ' ').trim();
    if (kept) out.push(kept);
  }
  return out.join('\n');
}

// Extract the balanced s-expression starting at the first match of `opener`
// (string-aware paren counting), with comments already stripped.
function extractForm(src, opener) {
  const s = stripComments(src);
  const at = s.indexOf(opener);
  if (at < 0) return undefined;
  let depth = 0, inStr = false;
  for (let i = at; i < s.length; i++) {
    const c = s[i];
    if (c === '"' && s[i - 1] !== '\\') inStr = !inStr;
    else if (!inStr && c === '(') depth++;
    else if (!inStr && c === ')') {
      depth--;
      if (depth === 0) return s.slice(at, i + 1).replace(/\s+/g, ' ');
    }
  }
  return undefined;
}

// Remove a @doc string (single- or multi-line continuation form) from an
// extracted, whitespace-collapsed form, so doc wording never affects the
// code comparison (module hashes ignore docs the same way).
function stripDoc(form) {
  if (form === undefined) return undefined;
  return form.replace(/@doc "(?:[^"\\]|\\.)*" ?/, '').replace(/\s+/g, ' ');
}

const STATION_CHECKS = [
  {
    name: 'registry replaces the compiled-in allowlist: testnet06 carries defconst SPONSORED-PREFIXES and no registry table; the candidate carries the registry + prefix-index tables, set-entry, REGISTRY-ADMIN and the ENTRY-SET event — and no SPONSORED-PREFIXES',
    check: (t, c) =>
      t.includes('defconst SPONSORED-PREFIXES') && !/deftable registry/.test(t) &&
      !c.includes('SPONSORED-PREFIXES') &&
      ['(deftable registry:{reg-entry})', '(deftable prefix-index:{idx-row})',
       '(defun set-entry:string', '(defcap REGISTRY-ADMIN', '(defcap ENTRY-SET'].every((k) => c.includes(k)),
  },
  {
    name: 'exec-only: testnet06 sponsors exec AND cont; the candidate enforces tx-type = exec and has no cont branch at all',
    check: (t, c) =>
      t.includes('(= "cont" tx-type)') &&
      c.includes('(enforce (= "exec" tx-type)') && !c.includes('"cont"'),
  },
  {
    name: 'per-entry budgets: testnet06 has one global charge-epoch against EPOCH-CAP; the candidate meters each entry (charge-entry: per-entry gas-limit ceiling, epoch cap, lifetime accounting) AND keeps a global backstop (charge-global vs GLOBAL-EPOCH-CAP)',
    check: (t, c) =>
      t.includes('(defun charge-epoch:bool') && !t.includes('charge-entry') &&
      c.includes('(defun charge-entry:bool') && c.includes('(defun charge-global:bool') &&
      c.includes('GLOBAL-EPOCH-CAP') && !c.includes('(defun charge-epoch'),
  },
  {
    name: 'deploy-time namespace binding: the candidate derives the admin keyset from the deploy transaction and hardcodes NO namespace anywhere; sponsored prefixes are on-chain data rows, not source',
    check: (t, c) =>
      c.includes("(format \"{}.spt-admin\" [(read-msg 'ns)])") && !c.includes(NS),
  },
  {
    name: 'gas-price ceiling unchanged: both lineages cap the sponsored gas price at the same constant',
    check: (t, c) => {
      const grab = (s) => extractForm(s, '(defconst MAX-GAS-PRICE');
      return grab(t) !== undefined && grab(t) === grab(c);
    },
  },
  {
    name: 'gas-ceiling positivity guard (candidate only): the candidate additionally rejects a non-positive gas price/limit — defense in depth from the community red-team; it lands on the testnet lineage at its next redeploy',
    check: (t, c) =>
      !t.includes('"Gas price must be positive"') &&
      c.includes('"Gas price must be positive"') && c.includes('"Gas limit must be positive"'),
  },
  {
    name: 'init admin-gated (candidate only): the candidate wraps the one-shot init in the governance capability — defense in depth (on a live station both init writes already fail closed)',
    check: (t, c) =>
      c.includes('(defun init') &&
      /\(defun init \(\) \(with-capability \(GOVERNANCE\)/.test(stripDoc(extractForm(c, '(defun init'))),
  },
  {
    name: 'global meter row shape unchanged (the deployed meter row survives an in-place upgrade)',
    check: (t, c) => {
      const grab = (s) => extractForm(s, '(defschema meter-row');
      return grab(t) !== undefined && grab(t) === grab(c);
    },
  },
  {
    name: 'guard machinery IDENTICAL (the funded station account resolves these BY NAME — they may never change): ALLOW_GAS, gas-payer-pred, station-guard-pred, create-gas-payer-guard, the GAS_STATION principal',
    check: (t, c) => ['(defcap ALLOW_GAS', '(defun gas-payer-pred:bool', '(defun station-guard-pred:bool',
      '(defun create-gas-payer-guard:guard', '(defconst GAS_STATION:string']
      .every((o) => {
        const a = stripDoc(extractForm(t, o)), b = stripDoc(extractForm(c, o));
        return a !== undefined && a === b;
      }),
  },
];

// ---------------------------------------------------------------------------
let fail = 0;

for (const m of IDENTITY_MODULES) {
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

{
  const t = readFileSync(new URL('../contracts/testnet06/smartpacts-gas-station.pact', import.meta.url), 'utf8');
  const c = readFileSync(new URL('../contracts/mainnet/smartpacts-gas-station.pact', import.meta.url), 'utf8');
  const ts = stripComments(t), cs = stripComments(c);
  let bad = 0;
  console.log('   smartpacts-gas-station: REDESIGNED lineage — asserting the named deltas:');
  for (const chk of STATION_CHECKS) {
    const ok = chk.check(ts, cs);
    console.log(`  ${ok ? '✅' : '❌'}   · ${chk.name}`);
    if (!ok) bad++;
  }
  if (bad) { fail++; }
  else console.log('✅ smartpacts-gas-station: every declared redesign delta holds; the guard core is code-identical');
}

console.log(fail
  ? '\n❌ lineage drift — fix before merging'
  : '\n✅ shares + ipo are exactly the deployed, tested system minus the whitelisted differences; the gas station redesign matches its declared deltas exactly');
process.exit(fail ? 1 : 0);
