# MyData 保險箱文件 → SD-JWT VC 選擇性揭露：實作紀錄與驗收閘門

日期：2026-09-07（接續 `mydata-vc-verifier-scenarios.md` 2026-09-01 的規格）

## 拍板的兩個決策

1. **衍生憑證採 IETF SD-JWT VC 平面格式**（`typ: dc+sd-jwt`、頂層 `vct`、`_sd` + `_sd_alg`、`cnf`，出示為 `<jwt>~<disclosure>…~<kb-jwt>`）。政府卡維持 TWDIW 方言（VP JWT 包 `jwt_vc`），兩條路在 `OID4VPResponder.responseMaterial` 依 `credentialFormat` / `queryLanguage` 分流，互不影響。
2. **述詞由持有人算，規則參數進簽章。** 查驗方在簽章的 request object 內以 `bonds_rule` 送出問題（年度、上限、日期、縣市），App 出示當下才從保險箱原檔解析、計算、鑄造憑證，並把同一條 `rule` 簽進 payload。查驗方比對 `rule` 與自己發出的 session 一致，才接受述詞。

## 元件對照

| 層 | App（backupTW-iOS） | Verifier（twdiw-vp-verifier-lite） | 公開文件 |
|---|---|---|---|
| 型別註冊 | `Model/MyDataDerivedCredential.swift`：`MyDataDerivedCredentialType`（vct、`vct#integrity`、claims、rules） | `src/holder-derived.ts` `DERIVED_TYPES`（同一組 vct、integrity、reviewed parsers） | `bonds-tw.github.io/vct/<type>/v1.json`（Type Metadata；`.well-known/vct/` 同步一份；`vct/index.json` 列 integrity） |
| Parser | `Model/MyDataDocumentParser.swift`：`income-pdf/v1`、`labor-insurance-pdf/v1`、`household-pdf/v1` | 只接受註冊表列出的版本 | 版本字串簽進 `source.parser` |
| 規則 | `MyDataDisclosureRule`（`income-ceiling/v1`、`insurance-active/v1`、`household-city/v1`）＋ `derive(from:rule:)` | `ruleProblem` 同一套參數驗證；`ruleWithOverrides` 讓操作者改參數 | rule 的參數表寫在 metadata `x-bonds.rules` |
| 簽發 | `Presentation/SDJWTVC.swift`：`SDJWTVCIssuance.mint`、`SDJWTVCPresentation.present`（KB-JWT `sd_hash`）、`SDJWTVCReader.read` | `verifySdJwtVc`（既有）＋ `verifyHolderDerivedPresentation`（衍生契約） | — |
| 請求 | `OID4VPRequest.verify` 讀 `dcql_query`（`credentials[].id / format / meta.vct_values / claims[].path`）與 `bonds_rule`；PE 路徑補 `dc+sd-jwt` 與 `$.vct` | `buildHolderDerivedPayload`：DCQL only ＋ `bonds_rule` | — |
| 出示 | `TWDIW/MyDataDerivedPresentation.swift`：`MyDataVaultArchive` 為文件來源、`EphemeralSigningKey`、DCQL 回 `vp_token = {"derived": "<sd-jwt>"}`，PE 回裸字串＋ `dc+sd-jwt` submission | `PresentationSession.submitHolderDerived` | — |
| UI | `DiscloseFieldsViewController` 表頭顯示查驗方問題；保險箱詳情頁「可回答的問題」列；DEBUG「Parse the original」列 | 情境頁的規則欄位；結果頁四張證據卡（信任標籤／指紋／parser／規則） | — |

## 金鑰決策

衍生憑證的 `iss` 與 `cnf` 是同一把**一次性記憶體 P-256 金鑰**（`EphemeralSigningKey`），出示完即消失、不進 Keychain。理由：主張本來就是持有人自述（`assurance: holder-derived`），Secure Enclave 不會讓它多一分政府背書；一次性金鑰讓兩次出示之間沒有任何可串連的識別子。需要綁到身分證持卡人金鑰時，把 `cnf` 換成該卡金鑰即可，介面不用改。

## 測試

App（Swift Testing，simulator）：
- `MyDataDocumentParserTests`：日期／數字／標籤工具、三個 parser 的正常與拒絕路徑、規則衍生（年度不符拒絕而非回 false、投保期間邊界、縣市正規化、參數白名單）。
- `SDJWTVCTests`：payload 形狀、只帶選定 disclosure、KB-JWT nonce/aud/sd_hash、外加 disclosure 拒絕、他人金鑰拒絕、保留字拒絕、過期拒絕。
- `OID4VPDCQLRequestTests`／`OID4VPDerivedResponseTests`：DCQL 與 PE 兩種請求、`vp_token` 物件形狀、只揭露選定欄位、兩次出示金鑰不同、無原檔／無規則／年度不符／原檔不可解析／欄位不在型別內 各自的錯誤、勞保情境。

Verifier（vitest）：`test/holder-derived.test.ts` 用 jose 鑄造同形憑證，涵蓋接受路徑與每種拒絕（規則不符、缺 rule／assurance、parser 未審、來源型別錯、指紋格式錯、vct 錯、integrity 錯、nonce 重放、aud 錯、無 KB、他人 KB、credential id 不符），規則參數驗證與覆寫，三個 profile 的判定與 DCQL 請求形狀。

## 驗收閘門（對照 scenarios 文件的六關）

| # | 閘門 | 狀態 2026-09-07 |
|---|---|---|
| 1 | 真實文件逐類驗證 PDF／CSV 格式與版本差異 | **待實機**。parser 以合成頁面文字寫成；保險箱詳情頁 DEBUG「Parse the original」列會印出解析欄位，用真檔跑一次即知版面是否吻合。不吻合就改 parser 並升版（`income-pdf/v2`），verifier 註冊表同步。 |
| 2 | parser 有去識別化 fixture、錯誤格式拒絕、邊界值測試 | 完成（合成 fixture）。真檔去識別後補進 `backupTWTests/Fixtures/mydata/` 是下一步。 |
| 3 | 讀取並驗證來源文件的機關簽章 | **未做**。`PDFSignatureScan` 已存在，尚未接進衍生流程；結果頁固定顯示「持有人從文件衍生」。 |
| 4 | App 產出的憑證可選擇性揭露，未勾欄位不進 presentation | 完成，有測試。 |
| 5 | verifier 驗簽、檢查 schema／規則版本，並顯示來源與 assurance | 完成，有測試；結果頁四張證據卡。 |
| 6 | 兩支真機跑過掃碼、同意、揭露選擇、驗證結果與撤回／刪除 | **待實機**。步驟見下。 |

## 實機驗收步驟

1. iPhone 裝新版（branch `codex/mydata-vault-flow`）。保險箱要有所得、勞保、戶籍任一份真檔。
2. 保險箱 → 該文件 → `[DEBUG] Parse the original`，確認欄位；失敗就把 alert 內容回報（不含個資的部分）。
3. Mac 開 `https://verifier.mashbean.net/`，皮夾選「有備而來」，情境選「所得是否在門檻內」（或勞保／設籍），填規則參數（年度要跟文件一致），勾告知，建立 QR。
4. iPhone「使用」→「出示證件給查驗方」掃 QR → 表頭出現「查驗方的問題：…」→ 關掉不想給的欄位 → 出示。
5. 網頁結果頁：判定標題＋「信任標籤：持有人從文件衍生」＋指紋＋parser＋規則四張卡；claims 表只有勾選的欄位。
6. 撤回／刪除：保險箱刪掉該文件後重掃同一 QR，App 應回「資料保險箱裡沒有查驗方要問的這種文件」。

## 尚未做、刻意留下的

- 健保投退保、納稅證明、勞退、地籍四類文件沒有 parser（詳情頁會說「還沒有對應的查驗問題」）。
- 機關簽章驗證（閘門 3）。
- `vct` metadata 由 GitHub Pages 靜態提供，verifier 以 `vct#integrity` 釘住而非即時抓取。
