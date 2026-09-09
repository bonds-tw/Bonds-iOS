# 沙盒發卡站「請收下卡片」（issuer.mashbean.net）

2026-09-08 建立；2026-09-09 決定**進入 Release/TestFlight**。

「請收下卡片」是模擬卡發行者，`TWDIWIssuer.mashbeanSandbox`。**它在每個建置都受信任，Release 也是**——這是讓皮夾在沒有真自然人憑證、沒有真政府卡時也能被完整操作（領卡→出示→查驗）的唯一辦法，TestFlight 測試者與 App Review 審查員都靠這條路。它發的卡全是虛構資料、標為模擬卡、在首頁自成一區，絕不與真卡混列。這不是把閘門放寬：它永遠不會在數位發展部信任清單上，每張卡仍要通過兩道領卡閘門與 `cnf`↔裝置金鑰綁定才會入庫。

moda demo 沙盒（`TWDIWIssuer.sandboxDemo`，issuer-oid4vci.wallet.gov.tw）仍只在 `#if DEBUG`。兩者由 `TWDIWIssuer.trustedSandboxes` 統一提供：Release 只有 mashbeanSandbox，DEBUG 另加 sandboxDemo。

## 它是什麼

[mashbean/twdiw-vc-issuer-lite](https://github.com/mashbean/twdiw-vc-issuer-lite) 是「請出示皮夾」（verifier.mashbean.net）的姊妹專案：一個 Cloudflare Worker 實作 OID4VCI 預授權碼流程，發行 TWDIW 方言的 SD-JWT 卡片，資料全是虛構的（六種日常卡片、六位不存在的人）。同一頁還有一個只信任自己的 OIDC4VP 查驗端，以及官方信任清單的即時檢視。示範站 <https://issuer.mashbean.net>。

它不在數位發展部的信任清單上，官方皮夾與請出示皮夾都會拒絕它發的卡。這個 app 的 DEBUG 建置用一條明確的信任例外接受它。

## 這個 app 動了哪裡

| 檔案 | 改動 |
|---|---|
| `TWDIW/IssuerAuthorization.swift` | `TWDIWIssuer.mashbeanSandbox`（釘住 DID 與 `issuerMetadataBaseURL`，**非 DEBUG**）、`trustedSandboxes`（Release=只 mashbean，DEBUG=另加 moda demo）、`isSimulatedCredential(issuerDID:credentialType:)` 分組判定 |
| `TWDIW/CredentialCollection.swift` | 信任清單無條件追加 `trustedSandboxes`；registry evidence 對這些 DID 回 `.developmentSandbox` |
| `TWDIW/OID4VCICollection.swift` | `case .developmentSandbox` 不再 `#if DEBUG`，Release 也處理（入庫但不取得離線信任快照） |
| `TWDIW/OID4VPPresentation.swift` | `verifierHosts` 無條件追加 `trustedSandboxes` → `issuer.mashbean.net` 成為可回傳的 response host（供同頁出示測試） |
| `TWDIW/TWDIWOnChainVerifier.swift` | `.developmentSandbox` 註解更新：每個建置都可能建立（請收下卡片），不再只 DEBUG |
| `Model/IssuerDirectory.swift` | 沙盒分支對釘住的 DID 顯示「請收下卡片 測試發卡站」（去掉 DEBUG 守衛）；`friendlyKind` 認得學生證／員工識別證／圖書借閱證／會員卡 |
| `Model/CardInventory.swift` | `CardInventoryRow.isSimulated`；`twdiwRow` 以 `isSimulatedCredential` 標記模擬卡 |
| `ViewController/HomeViewController.swift` | 政府卡濾掉模擬卡；新增 `simulatedSection`（id `simulated`，標題「模擬卡」），置於資料保險箱區塊下方、公文匣之上，僅在持有模擬卡時出現 |
| `Model/StoredNationalID.swift` | `fieldLabelTable` 補學號、學校、系所／部門、入學學年度、員工編號、證號、館別、會員編號、會員等級、駕照條件 |
| `ViewController/UseViewController.swift` | 使用 → 線上：「領取模擬卡」（開啟 `issuer.mashbean.net/?wallet=bonds`）與「領取駕照電子卡」（掃描監理服務網 QR → 既有 `ScanToCollect`）兩列，皆非 DEBUG |
| `Localizable.xcstrings` | 上述新字串的 zh-Hant，移除舊 DEBUG 字串 |
| `backupTWTests/SandboxIssuerTests.swift`、`SimulatedCardHomeTests.swift` | 兩道閘門、DID 可解析、response host、Release 受信任、`isSimulatedCredential` 判定、首頁模擬卡自成一區在保險箱下方 |

Release 建置包含 mashbeanSandbox 信任與「領取模擬卡」「領取駕照電子卡」兩列；只有 moda demo（sandboxDemo）仍 DEBUG-only。

## 釘住的 DID

```text
did:key:z2dmzD81cgPx8Vki7JbuuMmFYrWPgYoytykUZ3eyqht1j9Kbo2Mi4LUgEfFf1SyPGTHyP82LZ2VH9F6RGYsDNMtC2cmEJqADsXXbhTn4USsdTCP6h1ePhtazrv4rczSJUEKxyU1zRSHe5h4fjVg8VQRygF8YafgjNXEDzB6bquD9DUf45A
```

來源 `GET https://issuer.mashbean.net/api/issuer`（2026-09-08）。`jwk_jcs-pub` 拼法，公鑰內嵌，`TWDIWCredentialReader` 直接用它驗發卡簽章；`OID4VCICollector` 的最後一步要求卡片 `iss` 與它逐字相等。發卡站若重建 Durable Object 會換金鑰，需重新讀取並更新。

## 為什麼是信任例外，不是繞道

兩道閘門一個都沒放寬。閘門一仍然比對 offer 主機名稱是否在清單上（現在清單多一列 `issuer.mashbean.net`）；閘門二仍然比對 `credential_issuer` 的主機名稱；入庫前仍然比對 `iss` 與清單上那一列的 DID、比對 `cnf.jwk` 與裝置金鑰。沙盒發行者只是被寫進清單——這一個沙盒（mashbeanSandbox）連 Release 都寫，其餘（moda demo）只寫 DEBUG。首頁把模擬卡與真卡分區顯示，模擬卡自成一區在資料保險箱下方，卡面發卡者標「請收下卡片 測試發卡站」、信任來源「沙盒/測試」，任何情況都不會被誤認為真證件。

## 領取駕照電子卡

真的駕照電子卡（公路局）**不在** app 可直接開啟的「申請新卡」目錄裡（`frontend.wallet.gov.tw/api/moda/dwapp/apply/vcList` 只有三張電信卡，2026-09-09 實測）。它由持卡人登入監理服務網後在網頁端發卡。因此「領取駕照電子卡」列導進既有的 `ScanToCollect`：掃描監理服務網的卡片 QR（`/api/moda/qrcode?mode=vc&vcUid=`），`ModaServiceURLResolver` 解出 `issuerServiceUrl`（監理服務網登入頁），在內嵌 `WebCollectViewController` 開啟；登入後回傳的 `modadigitalwallet://credential_offer` 走同樣兩道閘門入庫。這是真政府卡，不需信任例外。

## 怎麼測

1. 裝建置（Release/TestFlight 也有這些列）。
2. 使用 → 線上 → 「領取模擬卡」（或在電腦開 issuer.mashbean.net）。
3. 選皮夾「有備而來」、卡種、虛構持卡人 → 建立 QR。
4. 同機：按「在這支手機直接開啟有備而來」→ 走 `SceneDelegate` 的 `openid-credential-offer://` 路徑。跨機：使用 → 領卡 → 掃 QR。
5. 首頁「模擬卡」區（在資料保險箱下方）出現卡片，發卡者顯示「請收下卡片 測試發卡站」、信任來源「沙盒/測試」；政府卡區不受影響。
6. 回到網頁「出示測試」→ 建立出示 QR → 使用 → 出示證件 → 掃描 → 逐欄同意 → 網頁顯示驗證通過。
7. 網頁「信任清單」區塊（已收合）展開後看見官方清單與本站不在其上的標示。
8. 駕照：使用 → 線上 → 「領取駕照電子卡」→ 掃描監理服務網卡片 QR → 登入 → 收下（需真監理服務網帳號，Apple 審查員無法完成，屬真實使用者路徑）。

實機領卡與出示已於 2026-09-09 通過（iPhone 14）。`scripts/smoke.mjs`（扮演皮夾的 Node 腳本，在 twdiw-vc-issuer-lite repo）與本 repo 單元測試持續背書。
