// Shared config + helpers for the SPT QA harness against the dedicated clean
// test devnet (:8090). Each persona signs with its own ed25519 key; sender00 is
// the sole faucet (mission constraint).
import {
  Pact,
  createClient,
  createSignWithKeypair,
  type ChainId,
  type ICommandResult,
  type IUnsignedCommand,
} from '@kadena/client';

export const DEVNET_HOST = process.env.DEVNET_HOST ?? 'http://localhost:8090';
// recap-development = the KDA-CE 3.1 devnet (plain "development" cannot mine on 3.1);
// override for a legacy 2.29 devnet with DEVNET_NETWORK_ID=development.
export const NETWORK_ID = process.env.DEVNET_NETWORK_ID ?? 'recap-development';
export const GAS_PRICE = 0.00000001;
export const GAS_LIMIT = 150000; // KDA-CE ceiling

export const client = createClient(
  ({ chainId, networkId }) =>
    `${DEVNET_HOST}/chainweb/0.0/${networkId}/chain/${chainId}/pact`,
);

export type Keypair = { account: string; publicKey: string; secretKey: string };

// Sole faucet — devnet genesis account, funded 100M KDA on every chain.
// Keypair matches the devnet genesis keys.yaml (kda-community/chainweb-node);
// verified: this secret derives to the on-chain guard pubkey 368820f8….
export const SENDER00: Keypair = {
  account: 'sender00',
  publicKey: '368820f80c324bbc7c2b0610688a7da43e39f91d118732671cd9c7500ff43cca',
  secretKey: '251a920c403ae8c8f65f59142316af3c82b631fba46ddea92ee8c95035bd2898',
};

// Test-devnet miner (block rewards accrue to k:<pub>). Used only as a neutral
// gas-payer "bot" for permissionless-claim proofs (key ≠ any holder's key).
export const MINER: Keypair = {
  account: 'k:f89ef46927f506c70b6a58fd322450a936311dc6ac91f4ec3d8ef949608dbf1f',
  publicKey: 'f89ef46927f506c70b6a58fd322450a936311dc6ac91f4ec3d8ef949608dbf1f',
  secretKey: 'da81490c7efd5a95398a3846fa57fd17339bdf1b941d102f2d3217ad29785ff0',
};

export const signerFor = (kp: Keypair) =>
  createSignWithKeypair({ publicKey: kp.publicKey, secretKey: kp.secretKey });

// a later change: the last fully-signed payload `send`/`sendExpectFail` put on the wire. The campaign
// has to EVIDENCE the capability list a real transaction carried, and every prior test drove
// DISBURSE through the REPL's `env-sigs`, which bypasses this encoding entirely. Reading it back
// off the signed command is the only way to show what was actually signed rather than intended.
let lastSignedPayload: any = null;
export function signedPayload(): any { return lastSignedPayload; }
/** The signers-and-clists array as it appears in the SIGNED cmd, decoded from the payload JSON. */
export function signedClists(): Array<{ pubKey: string; clist: any[] }> {
  const cmd = lastSignedPayload?.cmd;
  if (!cmd) return [];
  const signers = JSON.parse(cmd)?.signers ?? [];
  return signers.map((s: any) => ({ pubKey: s.pubKey, clist: s.clist ?? [] }));
}

// Unwrap Pact's tagged JSON values into JS values.
export function unwrap(v: any): any {
  if (v === null || v === undefined) return v;
  if (typeof v === 'object') {
    if ('int' in v) return Number(v.int);
    if ('decimal' in v) return Number(v.decimal);
    if ('time' in v) return v.time;
    if ('timep' in v) return v.timep;
  }
  return v;
}

function assertSuccess(r: ICommandResult, label: string): any {
  if (r.result.status !== 'success') {
    throw new Error(`${label} FAILED: ${JSON.stringify(r.result.error)}`);
  }
  return (r.result as any).data;
}

// Read-only /local call. Returns unwrapped data.
// Optional `data` rides the tx payload (read-msg / read-keyset). Added by a later change for the
// the design record D1 guard round-trip measurement: the reserve guard read from chain 0 is replayed
// back through tx data so `validate-principal` can be measured re-deriving the account on a
// REAL node — the same self-check ops/deploy/runbook.ts performs before building a spoke init.
export async function localCall(code: string, chainId: string, data?: Record<string, any>): Promise<any> {
  let b = Pact.builder.execution(code);
  for (const [k, v] of Object.entries(data ?? {})) b = b.addData(k, v);
  const tx: IUnsignedCommand = b
    .setMeta({ chainId: chainId as ChainId, senderAccount: SENDER00.account, gasLimit: GAS_LIMIT, gasPrice: GAS_PRICE })
    .setNetworkId(NETWORK_ID)
    .createTransaction();
  const r = await client.local(tx, { preflight: false, signatureVerification: false });
  return unwrap(assertSuccess(r, `local(${code.slice(0, 70)})`));
}

export async function coinBalance(account: string, chainId: string): Promise<number> {
  try {
    return Number(await localCall(`(coin.get-balance "${account}")`, chainId));
  } catch {
    return 0;
  }
}

export async function sptBalance(mod: string, account: string, chainId: string): Promise<number> {
  try {
    return Number(await localCall(`(${mod}.get-balance "${account}")`, chainId));
  } catch {
    return 0;
  }
}

export async function chainTime(chainId: string): Promise<string> {
  const t = await localCall(`(at 'block-time (chain-data))`, chainId);
  return typeof t === 'string' ? t : JSON.stringify(t);
}

export type CapBuilder = (wc: (n: string, ...a: any[]) => any) => any[];

// a later change: a co-signer and the capability list IT carries. `spt-gov` is keys-2 of 3, so every
// governance operation needs TWO signatures — and since a later change made DISBURSE @managed, the two
// signers' CAPABILITY LISTS are independently meaningful: one may name the tranche/target/amount
// while the other names something else entirely. That asymmetry is exactly what the campaign has
// to be able to express, so a co-signer carries its OWN CapBuilder rather than sharing the first
// signer's. A single shared clist could not model the mixed-clist case at all.
export type CoSigner = { signer: Keypair; caps?: CapBuilder };

export type SendOpts = {
  code: string;
  chainId: string;
  signer: Keypair;
  label: string;
  caps?: CapBuilder;
  // Additional signers, each with its own clist. The FIRST signer pays gas.
  cosigners?: CoSigner[];
  // PactValues, not just strings — booleans MUST stay booleans (the tokens deploy
  // footer's (if (read-msg 'upgrade) …) type-errors on the string "false").
  data?: Record<string, any>;
  keysets?: Record<string, { keys: string[]; pred: string }>;
};

// Submit a signed tx (one signer keypair) and poll to confirmation.
// THROWS on failure (use sendExpectFail for negative tests).
export async function send(o: SendOpts): Promise<ICommandResult> {
  let b = o.caps
    ? Pact.builder.execution(o.code).addSigner(o.signer.publicKey, o.caps)
    : Pact.builder.execution(o.code).addSigner(o.signer.publicKey);
  // a later change: each co-signer contributes its OWN clist. Added BEFORE the meta/network calls so
  // the signer list is complete when the payload hash is computed — every signature commits to
  // the same hash, which is what makes a mixed-clist transaction a single atomic authorization.
  for (const cs of o.cosigners ?? []) {
    b = cs.caps ? b.addSigner(cs.signer.publicKey, cs.caps) : b.addSigner(cs.signer.publicKey);
  }
  for (const [k, v] of Object.entries(o.data ?? {})) b = b.addData(k, v);
  for (const [k, ks] of Object.entries(o.keysets ?? {})) b = b.addKeyset(k, ks.pred as any, ...ks.keys);
  const tx = b
    .setMeta({ chainId: o.chainId as ChainId, senderAccount: o.signer.account, gasLimit: GAS_LIMIT, gasPrice: GAS_PRICE })
    .setNetworkId(NETWORK_ID)
    .createTransaction();
  // 🔴 EVIDENCE HOOK. The campaign's whole point is that the CLIST ON THE WIRE is what binds, so
  // the signed payload is exposed rather than inferred. `sigs` is one entry per signer, in order.
  let signed: any = await signerFor(o.signer)(tx);
  for (const cs of o.cosigners ?? []) signed = await signerFor(cs.signer)(signed);
  lastSignedPayload = signed;
  const r = await client.pollOne(await client.submit(signed as any), { timeout: 600_000, interval: 4_000 });
  if (r.result.status !== 'success') throw new Error(`${o.label} FAILED: ${JSON.stringify(r.result.error)}`);
  console.log(`    ✓ ${o.label} (gas ${r.gas}) tx=${(r as any).reqKey}`);
  return r;
}

// Negative-test helper: expect the tx to FAIL, optionally matching an error substring.
// Returns the error text on the expected failure; throws if it unexpectedly succeeds.
export async function sendExpectFail(o: SendOpts, mustContain?: string): Promise<string> {
  let err = '';
  try {
    const r = await send({ ...o, label: `${o.label} (expect-fail)` });
    // a poll may return a failure result without throwing in some paths:
    if ((r.result as any).status === 'success') {
      throw new Error(`EXPECTED FAILURE but ${o.label} SUCCEEDED`);
    }
    err = JSON.stringify((r.result as any).error);
  } catch (e: any) {
    err = e?.message ?? String(e);
    if (err.includes('EXPECTED FAILURE but')) throw e;
  }
  if (mustContain && !err.toLowerCase().includes(mustContain.toLowerCase())) {
    throw new Error(`${o.label}: failed but error did not contain "${mustContain}". Got: ${err.slice(0, 300)}`);
  }
  console.log(`    ✓ ${o.label} correctly rejected${mustContain ? ` ("${mustContain}")` : ''}`);
  return err;
}

// Generic 2-step SPV defpact: step0 on srcChain, SPV proof, step1 continuation on targetChain.
export async function runXchain(o: {
  code: string; srcChain: string; targetChain: string; signer: Keypair; label: string;
  caps?: CapBuilder; data?: Record<string, any>; keysets?: Record<string, { keys: string[]; pred: string }>;
}): Promise<{ step0: ICommandResult; step1: ICommandResult }> {
  let b = o.caps
    ? Pact.builder.execution(o.code).addSigner(o.signer.publicKey, o.caps)
    : Pact.builder.execution(o.code).addSigner(o.signer.publicKey);
  for (const [k, v] of Object.entries(o.data ?? {})) b = b.addData(k, v);
  for (const [k, ks] of Object.entries(o.keysets ?? {})) b = b.addKeyset(k, ks.pred as any, ...ks.keys);
  const step0tx = b
    .setMeta({ chainId: o.srcChain as ChainId, senderAccount: o.signer.account, gasLimit: GAS_LIMIT, gasPrice: GAS_PRICE })
    .setNetworkId(NETWORK_ID).createTransaction();
  const desc0 = await client.submit(await signerFor(o.signer)(step0tx) as any);
  const r0 = await client.pollOne(desc0, { timeout: 600_000, interval: 4_000 });
  if (r0.result.status !== 'success') throw new Error(`${o.label} step0 FAILED: ${JSON.stringify(r0.result.error)}`);
  console.log(`    ✓ ${o.label} step0 @ ${o.srcChain} (gas ${r0.gas})`);

  const proof = await client.pollCreateSpv(desc0, o.targetChain as ChainId);
  const step1tx = Pact.builder
    .continuation({ pactId: desc0.requestKey, step: 1, rollback: false, proof })
    .addSigner(o.signer.publicKey)
    .setMeta({ chainId: o.targetChain as ChainId, senderAccount: o.signer.account, gasLimit: GAS_LIMIT, gasPrice: GAS_PRICE })
    .setNetworkId(NETWORK_ID).createTransaction();
  const r1 = await client.pollOne(await client.submit(await signerFor(o.signer)(step1tx) as any), { timeout: 600_000, interval: 4_000 });
  console.log(`    • ${o.label} step1 @ ${o.targetChain} -> ${r1.result.status} (gas ${r1.gas ?? '?'})`);
  return { step0: r0, step1: r1 };
}

export { Pact, type ChainId, type ICommandResult };

// ── PRODUCTION-BUILD PRECONDITION ────────────────────────────────────────────────────────
// 🔴 WHY THIS EXISTS. Three drivers deploy a TIME-SCALED x1440 build — cw32-award-round-devnet,
// cw32-award-20chain-devnet and cw32-governance-devnet — and they do it by UPGRADING THE MODULE
// IN PLACE. That is deliberate (a real record date is 12 hours away; nobody can wait), and the
// build labels itself "NOT DEPLOYABLE ANYWHERE REAL". But it MOVES THE MODULE HASH, so every
// account guard minted under the previous hash stops validating, and the next driver that
// expects the real artifact dies on:
//
//     Execution aborted, hash not blessed for module: ...SPT
//
// That message points at BLESSING. The actual cause is "a previous driver left a test build
// installed on this chain". Measured 2026-08-21: it cost a full devnet rebuild and an hour of
// re-warming, because the error sent the diagnosis in the wrong direction.
//
// Same shape as an internal review's C-2: a correct payload sent to a chain in an UNEXPECTED STATE,
// with an error that misdirects. C-2's answer was to refuse at the door, and so is this.
//
// Correct order is real-build drivers first, scaled-build drivers after, freeze last.
export async function assertProductionBuild(module: string, chainId: string): Promise<void> {
  const PROD_MIN_RETRACT_LEAD = 21600; // 6h, the real defconst
  let lead: number;
  try {
    lead = Number(await localCall(`${module}.MIN-RETRACT-LEAD`, chainId));
  } catch (e: any) {
    // 🔴 UNREADABLE MUST FAIL, NEVER PASS. If the constant cannot be read, this check inspected
    // nothing — reporting that as "fine" is the false clearance the guard exists to prevent.
    throw new Error(
      `assertProductionBuild: could not read ${module}.MIN-RETRACT-LEAD on chain ${chainId} `
      + `(${String(e?.message ?? e).slice(0, 120)}). A precondition that inspected nothing FAILS.`);
  }
  if (lead !== PROD_MIN_RETRACT_LEAD) {
    throw new Error(
      `\n🔴 THIS CHAIN IS RUNNING A TIME-SCALED TEST BUILD, NOT THE ARTIFACT.\n`
      + `   ${module}.MIN-RETRACT-LEAD on chain ${chainId} = ${lead}s; the real build is ${PROD_MIN_RETRACT_LEAD}s.\n`
      + `   A previous driver (award-round / award-20chain / governance) upgraded the module in\n`
      + `   place and moved its hash. Guards minted under the old hash no longer validate, so this\n`
      + `   run would fail with a "hash not blessed" error that names the WRONG cause.\n`
      + `   Fix: tear the devnet down WITH ITS VOLUME (test-down.sh -v) and re-run the real-build\n`
      + `   drivers first. Scaled-build drivers go after them; the freeze drill goes last.\n`);
  }
}
