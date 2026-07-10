# Security policy

## Reporting a vulnerability

Please report vulnerabilities **privately** via GitHub's private vulnerability reporting:

**Security tab → "Report a vulnerability"** on this repository.

Do not open public issues for security findings, and please do not exploit findings against the
live deployment beyond what is needed for a proof of concept.

## Scope

- The Pact modules in [`contracts/`](contracts/) as deployed on Kadena **testnet06**, namespace
  `n_d97ffd2ca290429b5dc85ce551a8d07d038e9641` (chains 0–19).
- The event portal at `https://smartpacts.io/event/`.

## What to expect

- Acknowledgement of your report as quickly as possible, normally within a few days.
- The deployment is currently **testnet-only and all tokens are valueless**, so there is no bounty
  program at this stage. A responsible-disclosure policy for the mainnet deployment will be
  published before mainnet launch, and pre-mainnet reporters will be credited (with permission).

## Third-party reviews

- **External red-team — Oberlus / DNNS (July 2026).** Good-faith community security review by
  invitation: 88 executed attacks across 12 fronts plus a 20-mutation dividend-accounting deep-dive
  with a negative control. **Zero confirmed vulnerabilities.** Report:
  [`audits/2026-07-red-team-dnns.md`](audits/2026-07-red-team-dnns.md); the full runnable suite is in
  [`audits/2026-07-red-team-dnns/`](audits/2026-07-red-team-dnns/).

Thank you for helping keep the system safe.
