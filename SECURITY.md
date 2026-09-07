# Security policy / 安全回報政策

Bonds-iOS handles national identity documents, MyData files, and signing
keys. We treat every report about it seriously.

## Reporting a vulnerability

Please do **not** open a public issue for a security problem.

- Preferred: open a private report via
  [GitHub Security Advisories](https://github.com/bonds-tw/Bonds-iOS/security/advisories/new).
- Alternative: email `mashbean@gmail.com` with the subject line
  `[Bonds-iOS security]`.

Include the build (branch or commit), device and iOS version, reproduction
steps, and what you believe the impact is. Screenshots of a real credential
are not needed; redact anything that identifies a real person.

We aim to acknowledge within 7 days. Because this is a volunteer research
project there is no bounty, but we will credit you in the fix unless you ask
otherwise.

## Scope

In scope:

- The iOS app in this repository (`backupTW/`).
- The Rust physical-card signer under `tools/`.
- The Node scripts under `scripts/`.

Out of scope here (report to the owner of that system instead):

- The government services the app talks to (TW FidO, TWDIW wallet APIs,
  MyData, the official-document exchange). Draft findings against those
  upstreams that this project has already written up live in
  [`docs/upstream-reports.md`](docs/upstream-reports.md); they are
  **not yet reported** and coordinated disclosure is tracked there.
- `bonds-signing-broker` (separate repository).
- `twdiw-vp-verifier-lite` (separate repository).

## What we consider a vulnerability

- Any path that lets a Release build read or ship local TW FidO SP
  credentials (CI has a `strings` canary for this; see `.github/workflows/ci.yml`).
- A stored credential, MyData original, or official-document envelope that
  becomes readable from the Files app, iCloud backup, or another app.
- A holder key that survives "erase all local data" or is synced off-device.
- A verifier path that accepts a presentation whose selective-disclosure
  digests do not match, or that accepts an issuer outside the trust list.
- A ZK proof package that verifies without the caveats it is required to carry.

## Secrets hygiene for contributors

- Never commit `Secrets.swift`, captured TW FidO round trips, `.jws`
  credentials, or `ReplayLocal*.swift`. `.gitignore` blocks the known names;
  it is a backstop, not the rule.
- Test IDs `A123456789` / `A234567890` are the canonical Taiwan test numbers.
  Real ID numbers must never appear in fixtures, docs, or issues.

---

## 中文摘要

請勿在公開 issue 回報安全問題。優先使用
[GitHub Security Advisories](https://github.com/bonds-tw/Bonds-iOS/security/advisories/new)
私下回報，或寄信至 `mashbean@gmail.com`，主旨加上 `[Bonds-iOS security]`。

回報時請附上 build 版本、裝置與 iOS 版本、重現步驟與影響評估。請去除任何可
辨識真實個人的資料。本專案為志願研究計畫，沒有獎金，修補時會列名致謝。

政府端服務（行動自然人憑證、數位憑證皮夾、MyData、電子公文交換）的問題請向
該系統負責單位回報。本專案對上游整理的草稿見
[`docs/upstream-reports.md`](docs/upstream-reports.md)，尚未送出。
