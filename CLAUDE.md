# Pendant

macOS 瀏海互動 App，Swift / SwiftUI + AppKit。

## 開始前必讀
1. 完整閱讀 `requirements/requirements.md`（唯一的需求來源）。
2. 查看 `requirements/` 內所有截圖；`notch-hover.mp4` 請以 `ffmpeg` 抽格後檢視。
3. **依文件「九、開發里程碑」由 M0 開始，逐階段實作並通過驗收後才進下一階段。**

## 絕對規則
- **不得**把 API key、token、密碼、私鑰寫進程式碼、設定檔、commit、日誌或對話；需要時用佔位符並請使用者自行填入。完整規範見需求文件「十三、資安與機密處理」。
- 最低支援 macOS 14；Liquid Glass 僅 macOS 26+ 啟用，舊系統自動降級。
- 沒有 Apple Developer 帳號：ad-hoc 簽署、不公證。
- 與需求文件衝突或有疑義時，先回報再動手。

## 備註
- `requirements/` 已在 `.gitignore` 中，只存在本機，不會出現在 GitHub；不要把它加回版控。
