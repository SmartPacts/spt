// ===========================================================================
// spt-xchain-devnet — SPT IS HELD AND MOVED ON MORE THAN ONE CHAIN, AND MOVES
// BETWEEN THEM. The named test behind that promise.
//
// 🔴 WHY THIS IS NOT A .repl. The REPL has ONE database and no SPV. `resume` on
// the target chain needs a proof that a real node produced from a real mined
// block on the source chain, so the ARRIVAL leg is not expressible there at all
// — a REPL "cross-chain" test would either not compile or would quietly assert
// nothing, which is worse. This runs against a node, mines both legs, and reads
// both ledgers.
//
// Run: DEVNET_HOST=<node> SPT_XC_KEYFILE=<keys.json> npx --no-install tsx src/spt-xchain-devnet.ts
// Requires SPT deployed on SRC and DST and the sender holding a balance on SRC.
// ===========================================================================
import { readFileSync } from 'node:fs';
import { runXchain, localCall, type Keypair } from './config.js';

const M = process.env.SPT_MODULE ?? 'free.SPT';
const SRC = process.env.SPT_SRC ?? '0';
const DST = process.env.SPT_DST ?? '1';
const AMT = Number(process.env.SPT_XC_AMOUNT ?? '4');

let pass = 0, fail = 0;
const rec = (id: string, ok: boolean, msg: string) => {
  console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${id}  ${msg}`); ok ? pass++ : fail++;
};
const bal = async (a: string, c: string) =>
  Number(await localCall(`(${M}.get-balance "${a}")`, c).catch(() => 0));
const circ = async (c: string) => Number(await localCall(`(${M}.get-circulating)`, c));

// 🔴 KEYS COME FROM THE ENVIRONMENT, NEVER FROM THIS REPOSITORY. Point SPT_XC_KEYFILE at a JSON
// file holding a THROWAWAY devnet keypair: {"founder":{"publicKey":"…","secretKey":"…"}}.
// Never use a key that holds anything, on any network.
const KEYFILE = process.env.SPT_XC_KEYFILE;
if (!KEYFILE) {
  console.error('SPT_XC_KEYFILE is required — a JSON file with a throwaway devnet keypair.');
  process.exit(2);
}
const K = JSON.parse(readFileSync(KEYFILE, 'utf8'));
const f = K.founder;
const signer: Keypair = { account: `k:${f.publicKey}`, publicKey: f.publicKey, secretKey: f.secretKey };
const acct = signer.account;

console.log(`\n=== SPT cross-chain: ${SRC} -> ${DST}, ${AMT} SPT, module ${M} ===`);

const before = { src: await bal(acct, SRC), dst: await bal(acct, DST),
                 csrc: await circ(SRC), cdst: await circ(DST) };
console.log(`  before: c${SRC} holder=${before.src} circ=${before.csrc} · c${DST} holder=${before.dst} circ=${before.cdst}`);

// 🔴 THE HOLDER MUST ACTUALLY HOLD SOMETHING, or "it moved" is vacuous.
rec('XC-0', before.src >= AMT,
  `sender holds ${before.src} on the source chain, at least the ${AMT} about to move`);
if (before.src < AMT) { console.log('\nREFUSING to continue: nothing to move.'); process.exit(1); }

const { step0, step1 } = await runXchain({
  code: `(${M}.transfer-crosschain "${acct}" "${acct}" (read-keyset 'rg) "${DST}" ${AMT.toFixed(1)})`,
  srcChain: SRC, targetChain: DST, signer, label: `${AMT} SPT ${SRC}->${DST}`,
  keysets: { rg: { keys: [f.publicKey], pred: 'keys-all' } },
  caps: (wc: any) => [wc('coin.GAS'),
    wc(`${M}.TRANSFER_XCHAIN`, acct, acct, { decimal: AMT.toFixed(1) }, DST)],
});

rec('XC-1', step0.result.status === 'success', 'step 0 mined on the source chain (debit + yield)');
rec('XC-2', step1.result.status === 'success',
  `step 1 mined on the TARGET chain under an SPV proof (credit) — ${JSON.stringify((step1.result as any).error ?? 'ok').slice(0, 110)}`);

const after = { src: await bal(acct, SRC), dst: await bal(acct, DST),
                csrc: await circ(SRC), cdst: await circ(DST) };
console.log(`  after : c${SRC} holder=${after.src} circ=${after.csrc} · c${DST} holder=${after.dst} circ=${after.cdst}`);

rec('XC-3', after.src === before.src - AMT,
  `source ledger debited exactly ${AMT}: ${before.src} -> ${after.src}`);
rec('XC-4', after.dst === before.dst + AMT,
  `TARGET ledger credited exactly ${AMT}: ${before.dst} -> ${after.dst} — this is the half a REPL cannot reach`);
// circulating is maintained per leg, so the pair must move together and net to zero
rec('XC-5', (after.csrc - before.csrc) + (after.cdst - before.cdst) === 0,
  `circulating moved per-chain and nets to zero across the hop: ${after.csrc - before.csrc} on c${SRC}, +${after.cdst - before.cdst} on c${DST}`);
rec('XC-6', after.src + after.dst === before.src + before.dst,
  `no SPT created or destroyed by the hop: ${before.src + before.dst} -> ${after.src + after.dst}`);

console.log(`\n=== ${pass} pass, ${fail} fail ===`);
process.exit(fail ? 1 : 0);
