# MyData 首次領卡流程（2026-09-12）

下載資料與建立卡片是兩個不同的成功條件。MyData 完成授權、PDF 解鎖後，App 顯示資料檢查頁；使用者主動按「簽章並建立卡片」才開始 Bonds 的另一筆簽章。只有驗證成功且 CredentialStore 儲存成功，才顯示「卡片已儲存」與完成按鈕。

Release 在開啟 MyData 前，查詢固定 broker 的 `GET /v1/signatures/capabilities`（version 1、start_enabled、poll_enabled、transports）。兩個開關皆開啟且支援選用的 transport 才做 App Attest 連線檢查。舊後端的 404、無法解析、停用或連線失敗皆阻止下載；查詢本身不傳身分證字號。DEBUG 的既有直接供應者不使用此 broker 檢查。

後端配套：https://github.com/bonds-tw/bonds-signing-broker/pull/9 。必須先部署配套端點，再發佈新版 App。能力旗標只表示設定接受要求，不能保證外部 TW FidO 服務可用。此修改沒有開啟簽章開關或新增簽章密鑰。

簽章失敗保留本次記憶體中的資料。重新簽章需明確確認，並提醒先取消憑證 App 的待簽要求或等候過期；不自動重新下載或重發。停止等候取消本機工作，寫入前再次檢查取消，不等於遠端撤銷。草稿不寫入磁碟，離開需確認捨棄；關閉 App 後尚無跨次恢復。

MyData 的憑證 App 無法開啟時保留原網頁並顯示恢復指示。PDF 密碼可取消、採遮罩輸入，去除前後空白並轉大寫，且說明不是憑證 PIN。

## 驗證與尚未完成

- 本機完整 Swift 測試：1,640 tests / 173 suites 通過；網路隔離檢查通過。
- 模擬器 UI：資料檢查／取消保留，以及兩個 MyData 保險箱測試通過。區段索引修正後另做針對性重跑。
- Release arm64 模擬器編譯通過。OpenAC 既有二進位不含 x86_64，不能以 Intel 模擬器建置驗證。
- 未發佈新 TestFlight，也未證明真實 MyData／TW FidO 領卡成功。
- 發佈驗收應由首次使用者在實機完成：服務檢查 → MyData 授權 → 憑證 App 返回 → PDF 解鎖 → 核對 → 另一次卡片簽章 → 卡片儲存 → Home 開啟卡片。另測未安装、拒絕、斷線、逾時、停止等候與重啟 App；只記錄階段與結果，不蒐集個資或待簽內容。
