# TX-03 — Register (or replace) a dedicated voting key

Registers a second key that can do exactly one thing: vote as this account (TX-01/TX-02).
The main (transfer) key stays cold. Registration is **per chain** — register where the
test-shares live. The same call with a new keyset replaces a previous registration.

| | |
|---|---|
| Actor | account owner — **MAIN key only** (the voting key can never manage itself) |
| Chain | `$CHAIN` = where the account votes |
| Sender / gas | the owner's account, self-paid (this call is deliberately NOT sponsored) |
| Verification | `devnet-verified` (2026-07-18: register → hot-key vote → hot key refused for a transfer → clear → cleared key refused) |

## The signable command

```json
{
  "networkId": "$NETWORK",
  "payload": {
    "exec": {
      "code": "($NS.smartpacts-shares.set-vote-key \"<ACCOUNT>\" (read-keyset 'vk))",
      "data": {
        "vk": { "keys": ["<VOTING_PUBKEY_HEX>"], "pred": "keys-all" }
      }
    }
  },
  "signers": [
    {
      "pubKey": "<MAIN_PUBKEY_HEX>",
      "clist": [
        { "name": "coin.GAS", "args": [] },
        { "name": "$NS.smartpacts-shares.VOTE-KEY-ADMIN", "args": ["<ACCOUNT>"] }
      ]
    }
  ],
  "meta": {
    "chainId": "$CHAIN",
    "sender": "<ACCOUNT>",
    "gasLimit": 2500,
    "gasPrice": 0.00000001,
    "ttl": 1800,
    "creationTime": "<unix-seconds, backdated ~30 s>"
  },
  "nonce": "<unique>"
}
```

- **Scope the signature** to `VOTE-KEY-ADMIN` exactly as shown — that is the point of this
  capability: a scoped signature cannot be spent on anything else, so a malicious dapp
  cannot smuggle a stealth registration onto an unrelated transaction.
- Use a **plain keyset** for `vk` (single key, `keys-all`). An exotic guard whose
  predicate reads contract tables can fail at vote time.
- The registration emits `VOTE-KEY-SET (account key)` — the `key` is a fingerprint of the
  granted guard, so anyone watching events can detect an unexpected registration.
- Rotating the account's main guard **auto-revokes** the voting key.

## Read it back / clear it

- `($NS.smartpacts-shares.get-vote-key "<ACCOUNT>")` → `{ guard, active }` (free read).
- Deactivate with TX-04.

## Failure modes

| Error | Meaning / fix |
|---|---|
| `Keyset failure` | not signed by the MAIN key, or `VOTE-KEY-ADMIN` missing/mis-scoped |
| `row not found` (on the account) | the account holds no test-shares on this chain yet |
