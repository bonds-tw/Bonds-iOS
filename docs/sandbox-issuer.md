# 沙盒發卡站「請收下卡片」（issuer.mashbean.net）

2026-09-08。這是給開發建置用的第二個沙盒發行者，與 `TWDIWIssuer.sandboxDemo`（moda demo）並列，只在 `#if DEBUG` 內存在。

## 它是什麼

[mashbean/twdiw-vc-issuer-lite](https://github.com/mashbean/twdiw-vc-issuer-lite) 是「請出示皮夾」（verifier.mashbean.net）的姊妹專案：一個 Cloudflare Worker 實作 OID4VCI 預授權碼流程，發行 TWDIW 方言的 SD-JWT 卡片，資料全是虛構的（六種日常卡片、六位不存在的人）。同一頁還有一個只信任自己的 OIDC4VP 查驗端，以及官方信任清單的即時檢視。示範站 <https://issuer.mashbean.net>。

它不在數位發展部的信任清單上，官方皮夾與請出示皮夾都會拒絕它發的卡。這個 app 的 DEBUG 建置用一條明確的信任例外接受它。

## 這個 app 動了哪裡

| 檔案 | 改動 |
|---|---|
| `TWDIW/IssuerAuthorization.swift` | `TWDIWIssuer.mashbeanSandbox`（釘住 DID 與 `issuerMetadataBaseURL`）與 `TWDIWIssuer.debugSandboxes` |
| `TWDIW/CredentialCollection.swift` | 信任清單追加 `debugSandboxes`；registry evidence 對這些 DID 回 `.developmentSandbox` |
| `TWDIW/OID4VPPresentation.swift` | `verifierHosts` 追加 `debugSandboxes` → `issuer.mashbean.net` 成為可回傳的 response host |
| `Model/IssuerDirectory.swift` | 沙盒分支對釘住的 DID 顯示「請收下卡片 測試發卡站」；`friendlyKind` 認得學生證／員工識別證／圖書借閱證／會員卡 |
| `Model/StoredNationalID.swift` | `fieldLabelTable` 補學號、學校、系所／部門、入學學年度、員工編號、證號、館別、會員編號、會員等級、駕照條件 |
| `ViewController/UseViewController.swift` | 使用 → 線上 多一列「從測試發卡站領取測試卡」（DEBUG），開啟 `issuer.mashbean.net/?wallet=bonds` |
| `Localizable.xcstrings` | 上述新字串的 zh-Hant |
| `backupTWTests/SandboxIssuerTests.swift` | 兩道閘門、DID 可解析、response host、對照表與標籤 |

Release 建置沒有任何一項。

## 釘住的 DID

```text
did:key:z2dmzD81cgPx8Vki7JbuuMmFYrWPgYoytykUZ3eyqht1j9Kbo2Mi4LUgEfFf1SyPGTHyP82LZ2VH9F6RGYsDNMtC2cmEJqADsXXbhTn4USsdTCP6h1ePhtazrv4rczSJUEKxyU1zRSHe5h4fjVg8VQRygF8YafgjNXEDzB6bquD9DUf45A
```

來源 `GET https://issuer.mashbean.net/api/issuer`（2026-09-08）。`jwk_jcs-pub` 拼法，公鑰內嵌，`TWDIWCredentialReader` 直接用它驗發卡簽章；`OID4VCICollector` 的最後一步要求卡片 `iss` 與它逐字相等。發卡站若重建 Durable Object 會換金鑰，需重新讀取並更新。

## 為什麼是信任例外，不是繞道

兩道閘門一個都沒放寬。閘門一仍然比對 offer 主機名稱是否在清單上（現在清單多一列 `issuer.mashbean.net`）；閘門二仍然比對 `credential_issuer` 的主機名稱；入庫前仍然比對 `iss` 與清單上那一列的 DID、比對 `cnf.jwk` 與裝置金鑰。沙盒發行者只是被寫進清單，而且只寫進 DEBUG 建置的清單。

## 怎麼測

1. 裝 DEBUG 建置。
2. 使用 → 線上 → 「從測試發卡站領取測試卡」（或在電腦開 issuer.mashbean.net）。
3. 選皮夾「有備而來」、卡種、虛構持卡人 → 建立 QR。
4. 同機：按「在這支手機直接開啟有備而來」→ 走 `SceneDelegate` 的 `openid-credential-offer://` 路徑。跨機：使用 → 領卡 → 掃 QR。
5. 首頁出現卡片，發卡者顯示「請收下卡片 測試發卡站」、信任來源「沙盒/測試」。
6. 回到網頁「出示測試」→ 建立出示 QR → 使用 → 出示證件 → 掃描 → 逐欄同意 → 網頁顯示驗證通過。
7. 網頁「信任清單」區塊看見官方清單與本站不在其上的標示。

實機驗收前，這條路只有 `scripts/smoke.mjs`（扮演皮夾的 Node 腳本）與本 repo 的單元測試背書。
