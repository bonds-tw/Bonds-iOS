# Bonds-iOS · 有備而來

**A third-party Taiwan citizen digital identity wallet for iOS.**
Holds the national ID, government credentials from the official TWDIW wallet
ecosystem, MyData files, and official electronic documents. Presents and
verifies them online, offline over Bluetooth, and with zero-knowledge proofs.

[![CI](https://github.com/bonds-tw/Bonds-iOS/actions/workflows/ci.yml/badge.svg)](https://github.com/bonds-tw/Bonds-iOS/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
![iOS 16+](https://img.shields.io/badge/iOS-16%2B-lightgrey.svg)
![Swift 5 · UIKit](https://img.shields.io/badge/Swift-5%20%C2%B7%20UIKit-orange.svg)
[![Reports](https://img.shields.io/badge/field%20reports-pro.mashbean.net-0D5B48.svg)](https://pro.mashbean.net/?series=ready-digital-government)

[中文說明在下方](#中文說明) · [Field reports](#field-reports-and-background) · [Getting started](#getting-started) · [Status](#project-status)

---

## Why this exists

Taiwan is rolling out a national digital credential wallet (數位憑證皮夾, TWDIW),
a mobile citizen certificate (行動自然人憑證, TW FidO), a personal data
portability platform (MyData), and electronic official-document delivery. Each
is designed as a service the government runs. Bonds asks a different question:

> If a citizen wrote the wallet instead of the state, what would the ideal one
> look like, and where does the public infrastructure fall short?

The answer is built, not argued. Bonds speaks the official protocols end to end
against the real production and demo endpoints, on real devices, and publishes
what it finds as a report series. Every gap, caveat, and policy recommendation
in those reports traces back to code in this repository.

The project name 有備而來 means "to arrive prepared". The short English name is
Bonds; the working codename `backupTW` survives in the Xcode target and bundle
identifier `tw.bonds.backupTW`.

## What the app does

| Capability | Standards and counterparties | Where |
|---|---|---|
| **Collect government credentials** from the official TWDIW ecosystem (driver licence, telecom card, partner cards) | OpenID4VCI pre-authorized code flow, SD-JWT credentials, two trust gates before the issuer is contacted: the 數位發展部 trust list and an on-chain anchor on Arbitrum | `backupTW/TWDIW/` |
| **Present credentials** with selective disclosure to any TWDIW-compatible verifier | OpenID4VP by reference, request object as JWS verified against the verifier's `did:key`, holder picks claims, signed `vp_token` | `backupTW/TWDIW/OID4VP*`, `Presentation/SelectiveDisclosure.swift` |
| **Convenience-store pickup** barcode from a telecom credential | Official offline verifier list, short-lived till-readable barcode; used for a real 7-ELEVEN pickup | `TWDIW/ConvenienceStorePickup.swift` |
| **Self-issued national ID credential** from a MyData download | The ID document is parsed into a `vc+moica` credential signed by a per-card key; the plaintext is destroyed | `Model/`, `Storage/MyDataScratch.swift` |
| **MyData vault** for eight other personal documents | Originals kept in Application Support with Data Protection, excluded from backup, SHA-256 fingerprinted, previewable, individually deletable | `Storage/MyDataVaultArchive.swift` |
| **Official-document inbox** (電子公文個人接收站) | 檔案管理局 EN/DI/ESW XML triple, SHA-256 integrity, public G2B2C address book; physical 自然人憑證 card consent signing via PKCS#11 | `Model/OfficialDocument*`, `tools/` |
| **Zero-knowledge age proof** ("over 18" without revealing the birth date) | OpenAC `jwt_2k` + `show` circuits from `ethereum/zkID` (Spartan2/Hyrax, P-256) over an ES256 SD-JWT, verifier-first nonce, linked Prepare/Show proofs; verifiable on-device, on a second device over Bluetooth, or on the web | `Native/OpenACAge/`, `backupTW/Model/AgePredicate*` |
| **Zero-knowledge proof of certificate holding** over the holder's 自然人憑證 X.509 chain | Groth16 `cert_chain_rs4096` + `user_sig_rs2048` circuits, sparse-Merkle-tree revocation snapshot, SHA-256-pinned assets, every proof carries explicit caveats | `backupTW/ZK/` |
| **Offline verification** between two Bonds devices | W3C VC/VP over ES256 JWS, SD-JWT disclosures, chunked QR or BLE transport, cached trust list and revocation snapshot, caveats shown on the verdict | `Presentation/OfflineVerifier.swift`, `BluetoothLink.swift` |
| **Mobile citizen certificate signing** (TW FidO) | 行動自然人憑證 SP API v2.9 (`getSpTicket`, `getAthOrSignResult`, push), AES-256-GCM `sp_checksum`, app-to-app via `mobilemoica://` | `backupTW/TWFidO/` |
| **Release signing boundary** | Debug builds may use local SP credentials; Release builds can only sign through an App Attest-gated broker with three fixed intents. CI fails if a Release binary contains any local-credential marker | `TWFidO/AppAttestSigningBroker.swift`, `.github/workflows/ci.yml` |
| **Device self-check** | Runs the assertions only a real device can answer: Keychain erase, Secure Enclave backing, file-protection class, with plain-language verdicts | `Diagnostics/SelfCheck.swift` |

Design principles that shape every screen are written down in
[`docs/design-system.md`](docs/design-system.md): honesty is layout, offline is
the default, verdicts must be readable at a counter, and "partial" must never
look like "pass".

## Project status

Bonds is a **working research prototype**, not a shipped product. Read the
"completed" claims in the reports with that in mind.

- Real-device evidence exists for: OID4VCI collection and OID4VP presentation
  against the official demo, one real convenience-store pickup with a telecom
  credential, MyData vault with a real account, offline cross-device
  verification, web ZK age verification, physical-card consent signing.
- Release builds cannot sign yet. The App Attest signing broker
  (`bonds-signing-broker`) is deployed to UAT with signing disabled; TestFlight
  and App Store distribution wait on it. Most feature completeness so far is
  Debug-build completeness.
- The ZK certificate-holding proof carries a protocol-level caveat: TW FidO
  SIGN does not sign a verifier challenge, so the signing material is
  replayable. The app says so on screen rather than hiding it.
- To obtain a pre-authorized code from the official issuer, the app must send
  the official wallet's `client_id` (`moda_dw`); the token endpoint rejects any
  other value. This is documented in code and is one of the items queued for
  upstream disclosure.
- Draft findings against upstream systems live in
  [`docs/upstream-reports.md`](docs/upstream-reports.md). They have **not been
  sent**; coordinated disclosure is a pending decision, not a done one.
- Open work is tracked in
  [GitHub issues](https://github.com/bonds-tw/Bonds-iOS/issues) and
  [`docs/roadmap-2026-08-27.md`](docs/roadmap-2026-08-27.md).

## Trust and privacy posture

- **Keys.** One long-lived P-256 install key (Secure Enclave when available)
  and one signing key per stored card so two verifiers cannot correlate two
  cards. All Keychain items are `WhenUnlockedThisDeviceOnly`, never synced.
- **Files.** Every store lives in Application Support, never `Documents`,
  with `completeUnlessOpen` protection and `isExcludedFromBackup`. One code
  path erases everything, including the ZK working directory.
- **Network.** Trust lists, revocation snapshots, and circuit assets are
  fetched and pinned; verifying-key hashes are compiled in and no remote
  source can override them. Proofs are only sent to an allow-listed verifier
  host.
- **No telemetry.** Verification timings recorded for the test matrix contain
  no name, DID, credential identifier, or disclosed value.
- **Secrets.** TW FidO SP credentials exist only inside `#if DEBUG`, are read
  from scheme environment variables, and are blocked from the tree by
  `.gitignore` and from the Release binary by CI.

See [SECURITY.md](SECURITY.md) for how to report a problem.

## Getting started

Requirements: macOS with Xcode 16 or later, an iOS 16+ simulator or device,
Node.js 20+ for the helper scripts, Rust for the physical-card tool.

```bash
git clone https://github.com/bonds-tw/Bonds-iOS.git
cd Bonds-iOS
xcodebuild -resolvePackageDependencies -project backupTW.xcodeproj
open backupTW.xcodeproj
```

Run the unit tests the same way CI does (pick any available iPhone simulator):

```bash
xcodebuild test -project backupTW.xcodeproj -scheme backupTW \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:backupTWTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

Notes for a first build:

- The project file carries the maintainers' `DEVELOPMENT_TEAM`. Set your own
  team in Signing & Capabilities to run on a device.
- Keychain, Secure Enclave, App Attest, Bluetooth, and the camera behave
  differently on a simulator. Anything that touches them should be verified on
  a real device; `Diagnostics` in the app tells you which checks it could not
  run.
- TW FidO signing in Debug needs `TWFIDO_SP_SERVICE_ID` and
  `TWFIDO_SP_AES_KEY` as scheme environment variables from your own SP
  registration. Without them the signing entry points fail closed. Never put
  them in a source file.
- ZK circuit assets are downloaded on first use and pinned by SHA-256. The
  certificate-holding circuits need roughly 1 GB on disk after decompression.
- `backupTWUITests` are not run in CI. Run them locally when a change touches
  navigation or the screenshot tour.
- Strings live in `backupTW/Localizable.xcstrings` with `en` as source and
  `zh-Hant` as the shipped localization; `LocalizationCoverageTests` fails on
  a missing translation.

## Repository layout

```text
backupTW/            The app (UIKit, Swift 5)
  Crypto/            Install key, per-card holder keys, did:key
  TWDIW/             OpenID4VCI / OpenID4VP, trust list, on-chain anchor, pickup
  TWFidO/            Mobile citizen certificate SP API, App Attest signing broker client
  Presentation/      QR/BLE transport, selective disclosure, offline verifier, ZK packages
  ZK/                Groth16 certificate-holding proof: assets, verifying keys, caveats
  Model/ Storage/    Credentials, MyData vault, official-document inbox, erasure
  Wall/              Lennon Wall signing client (written and tested, not wired to UI)
  ViewController/    Every screen
  BondsDesign.swift  Design tokens; spec in docs/design-system.md
backupTWTests/       Unit tests (Swift Testing + XCTest), the bundle CI runs
backupTWUITests/     UI tests and the screenshot tour, run locally
Native/OpenACAge/    Reproducible overlay on ethereum/zkID for the age proof (Rust, Mopro)
Native/OpenACAgePackage/  SwiftPM wrapper around the checksummed XCFramework
tools/               Rust PKCS#11 signer for the physical 自然人憑證 card (Debug only)
scripts/             TW FidO signing helper, PDF signature check, timing collection, icons
docs/                Design docs, plans, phase reports, audits (index in docs/README.md)
```

## Field reports and background

The report series **有備而來：理想的數位皮夾開發報告** on
[pro.mashbean.net](https://pro.mashbean.net/?series=ready-digital-government)
documents each stage with real-device measurements and policy analysis.
The reports are in Traditional Chinese.

| Date | Report | Topic |
|---|---|---|
| 2026-09-06 | [斷網時，讓數位皮夾互相離線驗證](https://pro.mashbean.net/reports/2026-09-06-offline-wallet-verification/) | Offline cross-device verification of SD-JWT-VC and ZK proofs over Bluetooth |
| 2026-09-05 | [整合 MyData：用數位皮夾實踐資料保險箱](https://pro.mashbean.net/reports/2026-09-05-mydata-vault-in-the-digital-wallet/) | MyData vault design, real-account results, verifier recognition policy |
| 2026-09-05 | [讓數位皮夾實現零知識證明，同時免費部署服務到 Cloudflare](https://pro.mashbean.net/reports/2026-09-05-zero-knowledge-age-proof-from-phone-to-cloudflare/) | ZK age proof from phone to a Cloudflare-fronted verifier, timings and costs |
| 2026-09-03 | [請出示皮夾：把數位皮夾查驗做成一鍵部署的開源服務](https://pro.mashbean.net/reports/2026-09-03-one-click-twdiw-vp-verifier-lite/) | The companion one-click verifier and its governance boundary |
| 2026-09-02 | [用「有備而來」完整重現數位皮夾超商取貨](https://pro.mashbean.net/reports/2026-09-02-telecom-credential-convenience-store-pickup/) | Telecom credential to store POS pickup on a real device |
| 2026-09-01 | [如果用自然人憑證接收電子公文？](https://pro.mashbean.net/reports/2026-09-01-natural-person-certificate-official-documents/) | Official-document inbox prototype, legal delivery, procurement gaps |

More on the same site: the
[digital identity topic](https://pro.mashbean.net/topics/digital-identity/) and
the [civic proof series](https://civic-proof.mashbean.net) that frames why a
citizen-built wallet matters.

Inside this repository, [`docs/README.md`](docs/README.md) indexes the design
documents, integration plans, phase reports, and audits.

## Related projects

| Project | Role |
|---|---|
| [bonds-tw/bonds-signing-broker](https://github.com/bonds-tw/bonds-signing-broker) | App Attest-gated TW FidO signing broker that Release builds use (private while in UAT) |
| [mashbean/twdiw-vp-verifier-lite](https://github.com/mashbean/twdiw-vp-verifier-lite) | One-click Cloudflare verifier for TWDIW presentations and Bonds ZK proofs; demo at [verifier.mashbean.net](https://verifier.mashbean.net) |
| [bonds-tw/bonds-tw.github.io](https://github.com/bonds-tw/bonds-tw.github.io) | Deep-link landing, TWDIW field notes, credential type metadata |
| [moda-gov-tw/TWDIW-official-app](https://github.com/moda-gov-tw/TWDIW-official-app) | The official wallet this project interoperates with |
| [ethereum/zkID](https://github.com/ethereum/zkID), [privacy-ethereum/openac-rsa-x509-swift](https://github.com/privacy-ethereum/openac-rsa-x509-swift) | Circuits and bindings for both zero-knowledge proofs |
| [denkeni: TWDIW, The Missing Manual](https://docs.denkeni.org/twdiw) | Independent documentation the integration plan builds on |

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md)
first: it covers the branch model, what must be verified on a real device, the
localization rule, and the hard line on real personal data in fixtures. This
project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for
third-party components. To cite the project, see [CITATION.cff](CITATION.cff).

---

## 中文說明

**有備而來（Bonds）是一個由公民自行開發的台灣數位身分皮夾 iOS App。**
它能收存國民身分證、數位憑證皮夾（TWDIW）生態系的政府卡片、MyData 文件與電子
公文，並以線上、離線藍牙與零知識證明三種方式出示或查驗。

### 為什麼要做

數位憑證皮夾、行動自然人憑證、MyData 與電子公文送達都由政府設計並營運。本專案
從另一個方向提問：如果皮夾由公民來寫，理想的皮夾應該長什麼樣，公共基礎設施還
缺哪些零件。答案用程式碼回答。App 對正式與示範環境跑完整協定，在真機上量測，
再把發現寫成報告。報告裡每一項缺口、但書與政策建議，都能對回本 repo 的程式碼。

### 功能

- 以 OpenID4VCI 向官方發卡端收卡，收卡前同時核對數位發展部信任清單與 Arbitrum
  鏈上紀錄。
- 以 OpenID4VP 對任何相容查驗端做選擇性揭露出示。
- 用電信卡產生超商取貨條碼，已在真實門市完成一次取貨。
- 讀取 MyData 下載的身分證明，轉為每卡獨立金鑰簽章的自發證件後銷毀明文。
- MyData 資料保險箱收存其他八種文件，原始檔受 Data Protection 保護、不進備份、
  可重驗指紋、預覽與單項刪除。
- 電子公文個人接收站，含實體自然人憑證卡簽署同意的桌面工具。
- 零知識年齡證明：只證明「已滿 N 歲」，不揭露生日，可在本機、第二台裝置或網頁
  查驗。
- 零知識持證證明：對自然人憑證 X.509 鏈做 Groth16 證明，並附撤銷快照，每份證明
  都帶明示但書。
- 兩台裝置間的離線查驗，走 QR 或藍牙，信任清單與撤銷快照事先快取。
- 行動自然人憑證簽章，Debug 版用本機 SP 憑證，Release 版只能透過 App Attest
  把關的簽章代理，CI 會檢查 Release 二進位不含任何本機憑證痕跡。

### 現況

本專案是可運作的研究原型，尚未上架。Release 版目前無法簽章，簽章代理仍在 UAT
且簽章功能關閉。零知識持證證明受協定限制，簽章材料可重放，App 會在畫面上說明。
向官方發卡端取碼時必須送出官方皮夾的 `client_id`，程式碼中已註明，並列入待回
報上游的項目。對上游系統的問題草稿在
[`docs/upstream-reports.md`](docs/upstream-reports.md)，尚未送出。

### 快速開始

需要 Xcode 16 以上、iOS 16 以上的模擬器或裝置。

```bash
git clone https://github.com/bonds-tw/Bonds-iOS.git
cd Bonds-iOS
xcodebuild -resolvePackageDependencies -project backupTW.xcodeproj
open backupTW.xcodeproj
```

裝機請改成自己的開發團隊。Keychain、Secure Enclave、App Attest、藍牙與相機在
模擬器上行為不同，相關修改請在真機驗證。Debug 版的行動自然人憑證簽章需要自
己申請的 SP 帳號，以 scheme 環境變數 `TWFIDO_SP_SERVICE_ID` 與
`TWFIDO_SP_AES_KEY` 提供，不得寫進原始碼。

### 文件與報告

開發報告系列「有備而來：理想的數位皮夾開發報告」發佈於
[pro.mashbean.net](https://pro.mashbean.net/?series=ready-digital-government)，
六篇報告連結見上方英文表格。Repo 內的設計文件、整合計畫、階段報告與稽核索引
在 [`docs/README.md`](docs/README.md)。

### 授權與參與

Apache License 2.0，第三方元件見 [NOTICE](NOTICE)。參與方式見
[CONTRIBUTING.md](CONTRIBUTING.md)，安全回報見 [SECURITY.md](SECURITY.md)。
在 issue 或 PR 中不得出現任何真實個人的證件、身分證字號或憑證。
