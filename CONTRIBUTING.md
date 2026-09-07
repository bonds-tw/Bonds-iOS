# Contributing to Bonds-iOS

Thanks for looking. This document explains how the project is organised so a
first pull request lands without friction. A Chinese summary follows at the end.

## Ground rules

1. **No real personal data, ever.** Not in code, fixtures, screenshots, docs,
   issues, or commit messages. Use the canonical Taiwan test IDs
   `A123456789` / `A234567890` and the persona 王小明. Captured TW FidO
   responses, issued `.jws` credentials, and replay files are blocked by
   `.gitignore`; treat that as a backstop, not permission.
2. **Honesty is a feature.** If a flow only works in Debug, on one device, or
   with a caveat, the UI and the docs must say so. Do not turn `.partial` into
   `.supported` to make a demo look better.
3. **Fail closed.** A missing trust record, an unreachable RPC, a hash that
   does not match, or a broker host outside the allowlist stops the flow. Do
   not add a cached or "best effort" pass-through.
4. **Release stays clean.** Nothing outside `#if DEBUG` may read local TW FidO
   SP credentials. CI runs a `strings` canary over the Release binary and will
   fail your PR if a marker survives.

## Branches and pull requests

- `main` is the integration branch and is protected by CI.
- Work on a topic branch. Existing naming is `feat/<topic>` or
  `codex/<topic>`; either is fine.
- Open a pull request against `main`. The template asks what changed, why,
  how it was verified, and walks the privacy checklist. Fill it in.
- Commit messages describe the *why*. English or Traditional Chinese both
  work; the history has both.
- Keep unrelated refactors out of a feature PR. A separate small PR merges
  faster.

## Building and testing

See the README for the clone and build commands. Before opening a PR:

```bash
xcodebuild test -project backupTW.xcodeproj -scheme backupTW \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:backupTWTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

Tests use Swift Testing and XCTest side by side. Put new tests next to the
existing file for that area (`backupTWTests/<Area>Tests.swift`).

**Real-device verification is required** when a change touches:

- Keychain, Secure Enclave, App Attest, or `LocalDataEraser`
- Bluetooth transport or the camera scanner
- The signing broker client or TW FidO deep links
- ZK proving (the simulator is far slower and some FFI paths differ)

Say in the PR which device and iOS version you used. The in-app `Diagnostics`
screen prints which self-checks could not run on a simulator.

`backupTWUITests` are not in CI. Run them locally for navigation or
screenshot-tour changes.

## Localization and copy

- All user-facing strings go through `backupTW/Localizable.xcstrings`.
  `en` is the source language, `zh-Hant` ships. `LocalizationCoverageTests`
  fails on a missing translation.
- `CopyGuideTests` enforces house style: the app refers to itself as
  「這個 App」, the service as `bonds.tw`, and verdict wording must not
  conflate "partial" with "pass". Read `docs/design-system.md` §copy before
  writing new screen text.
- Do not add colours, fonts, or spacing outside `BondsDesign.swift`.

## Docs

- Design decisions, plans, and phase reports live in `docs/`. Add an entry to
  `docs/README.md` when you add a document.
- Field reports with measurements are published on
  [pro.mashbean.net](https://pro.mashbean.net/?series=ready-digital-government);
  link to them rather than duplicating them here.
- Findings against upstream systems go into `docs/upstream-reports.md` as
  drafts. Sending them is a maintainer decision.

## Dependencies

- Swift packages are pinned in `backupTW.xcodeproj`. Adding one needs a
  justification in the PR and an entry in `NOTICE`.
- `Native/OpenACAge` is a reproducible overlay on a pinned `ethereum/zkID`
  commit. Its build script refuses any other revision; do not bump it without
  re-running the release gate described in `Native/OpenACAge/README.md`.
- Runtime assets (circuits, keys, revocation snapshots) are pinned by SHA-256
  in code. Changing a pin is a release event: update
  `docs/zk-verifying-key-manifest.md` in the same PR.

## Reporting

- Bugs and proposals: GitHub issues, using the templates.
- Security problems: **not** an issue. See [SECURITY.md](SECURITY.md).

---

## 中文摘要

- 不得在程式、測試資料、截圖、文件、issue 或 commit 中放入任何真實個人資料。
  測試請用 `A123456789` / `A234567890` 與王小明。
- 只在 Debug 可用、只在單一裝置驗證過、或帶有但書的功能，畫面與文件都要如實
  標示。
- 信任紀錄缺漏、RPC 不通、雜湊不符或主機不在允許清單時一律停止流程，不得加入
  快取放行。
- `#if DEBUG` 之外不得讀取本機行動自然人憑證 SP 憑證，CI 會掃描 Release
  二進位。
- 從 `main` 開 topic branch，PR 依模板填寫變更、原因、驗證方式與隱私檢查。
- 送 PR 前跑 `backupTWTests`。凡涉及 Keychain、Secure Enclave、App Attest、
  藍牙、相機、簽章代理或零知識證明的修改，必須在真機驗證並註明裝置與 iOS
  版本。
- 所有介面文字放在 `Localizable.xcstrings`，`en` 為來源、`zh-Hant` 為出貨語言，
  缺譯會讓測試失敗。文案規則見 `docs/design-system.md`。
- 新增文件請登記到 `docs/README.md`。安全問題請依 [SECURITY.md](SECURITY.md)
  私下回報。
