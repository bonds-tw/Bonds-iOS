# 更正：卡片簽章不依賴 Bonds 自建後端（2026-09-12）

使用者確認不提供 Bonds 後端服務。本次移除 PR #66 的能力端點／App Attest 前置查詢，並移除國民身分卡建立流程對 SigningBrokerSessionAssembly 的 Release 接線。後端 PR #9 未部署，本流程不再使用它。其他既有功能的 broker 程式不在本次變更範圍。

保留下載後核對、明確另行簽章、成功儲存才顯示完成、失敗重試、取消等待、密碼保護與草稿釋放。

現有直接 TW FidO client 仍需 SP service ID 與 AES 介接憑證來產生 checksum；使用者在 TW FidO 的簽章，與應用服務發起要求的介接授權是不同事項。開發版先在本機檢查介接設定，不傳送個資。正式版沒有可發行的直接憑證提供方式，因此不再用 broker URL 推論可領卡，而是明確停止卡片建立、提示可從首頁匯入 MyData 原始文件。沒有將共用 SP 密鑰放進 App，沒有把 MyData 登入成功冒充卡片簽章。

官方來源：https://fido.moi.gov.tw/pt/agency （App 對 App 為需申請的介接模式）。程式證據：TWFidOClient.swift、SPSecrets.swift。這不代表已證明所有無自建後端方案都不可行；仍需確認官方是否提供適合公開行動 App、無共用密鑰散布的正式介接方式。

未完成：正式版 TW FidO 直接簽章整合、TestFlight 真實領卡驗收。MyData 原始文件匯入不依賴 Bonds 簽章服務。
