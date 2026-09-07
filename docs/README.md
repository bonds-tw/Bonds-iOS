# Documentation index / 文件索引

Most documents are written in Traditional Chinese. Dates in file names are the
day the document was written; a document may carry a later status banner at
the top that supersedes its older sections. Field reports with measurements
are published separately on
[pro.mashbean.net](https://pro.mashbean.net/?series=ready-digital-government).

## Start here

| Document | What it is |
|---|---|
| [roadmap-2026-08-27.md](roadmap-2026-08-27.md) | The development roadmap: tracks, milestones, risks, and a status banner updated 2026-08-31. Read this before picking up any open issue. |
| [app-development-checkpoint-2026-09-04.md](app-development-checkpoint-2026-09-04.md) | Checkpoint of what is on GitHub, which evidence exists, and what the next stage owes. |
| [design-system.md](design-system.md) | Design system v1.0: naming, principles, colour and type tokens, verdict semantics, copy rules. `BondsDesign.swift` implements it. |

## Integration plans and research

| Document | What it is |
|---|---|
| [twdiw-integration-plan.md](twdiw-integration-plan.md) | Full plan for interoperating with the official TWDIW wallet: OpenID4VCI/VP, trust list, DID handling, with read-only measurements against production endpoints and the author's corrections left in. |
| [trust-chain-recommendation.md](trust-chain-recommendation.md) | Research on the trust-list commitment model. Not an adopted design; a canonicalization collision was reproduced and partly fixed. |
| [wall-signing-plan.md](wall-signing-plan.md) | The Lennon Wall signing flow: written and tested under `backupTW/Wall/`, deliberately not wired to any screen. |
| [proposal-unified-checker.md](proposal-unified-checker.md) | Proposal to merge the two verifier entry points and why the two QR formats cannot simply be swapped. |
| [release-signing-backend-v0.md](release-signing-backend-v0.md) | Architecture decision record for Release signing: separate App Attest-gated broker, SP secrets never on device, three fixed intents, fail-closed rules. |

## Zero-knowledge proofs

| Document | What it is |
|---|---|
| [zk-verifying-key-manifest.md](zk-verifying-key-manifest.md) | Release gate for the Groth16 verifying keys: manifest ID, byte counts, SHA-256 pins compiled into the app. |
| [zkp-web-verification-2026-09-04.md](zkp-web-verification-2026-09-04.md) | Web ZK age verification at `verifier.mashbean.net/zkp` and the ZKP versus SD-JWT-VC timing comparison. |
| [../Native/OpenACAge/README.md](../Native/OpenACAge/README.md) | Reproducible overlay on `ethereum/zkID` for the age predicate proof and its release vector. |

## Official-document inbox (電子公文個人接收站)

Phase reports, in order. Each records what was built, what was verified on a
real device, and what the competent authority still has to provide.

| Phase | Document |
|---|---|
| 2 | [official-document-inbox-phase2.md](official-document-inbox-phase2.md) |
| 3 | [official-document-inbox-phase3.md](official-document-inbox-phase3.md) |
| 4 | [official-document-inbox-phase4.md](official-document-inbox-phase4.md) |
| 5 | [official-document-inbox-phase5.md](official-document-inbox-phase5.md) |
| 6 | [official-document-inbox-phase6.md](official-document-inbox-phase6.md) |
| 7 | [official-document-inbox-phase7.md](official-document-inbox-phase7.md) — physical 自然人憑證 card consent signing over PKCS#11 |
| 8 | [official-document-inbox-phase8.md](official-document-inbox-phase8.md) — Debug-only G2C sandbox |

## Field test records

| Document | What it is |
|---|---|
| [m52-live-collection-2026-08-26.md](m52-live-collection-2026-08-26.md) | Live credential collection against `demo.wallet.gov.tw`, including the CR/LF deep-link bug and the trust-gate fix. |
| [mydata-vc-verifier-scenarios.md](mydata-vc-verifier-scenarios.md) | Verifier scenarios for the self-issued MyData credential. |
| [app-attest-uat-test.md](app-attest-uat-test.md) | App Attest UAT test procedure and evidence. |

## Audits

| Document | What it is |
|---|---|
| [ux-audit-2026-08-13.md](ux-audit-2026-08-13.md) | First UX audit. |
| [ux-audit-2026-08-18.md](ux-audit-2026-08-18.md) | Second UX audit; most ZK findings here have since been fixed. |
| [upstream-reports.md](upstream-reports.md) | Draft findings against TWDIW and zkID, ordered by user harm. **None sent.** Sending is a maintainer decision. |

---

## 中文

文件多為正體中文。檔名日期是撰寫日；文件開頭若有較新的現況說明，以現況說明為
準。含量測數據的開發報告另發佈於
[pro.mashbean.net](https://pro.mashbean.net/?series=ready-digital-government)。

- 起點：`roadmap-2026-08-27.md`（路線圖）、`app-development-checkpoint-2026-09-04.md`
  （開發階段註記）、`design-system.md`（設計系統）。
- 整合與研究：TWDIW 整合計畫、信任鏈研究、連儂牆簽署計畫、統一查驗入口提案、
  Release 簽章後端決策紀錄。
- 零知識證明：驗證金鑰清單、網頁查驗與計時比較、`Native/OpenACAge` 說明。
- 電子公文接收站：Phase 2 至 Phase 8 階段報告。
- 實測紀錄：官方示範環境收卡、MyData 自發證件查驗情境、App Attest UAT。
- 稽核：兩次 UX 稽核、上游回報草稿（尚未送出）。
