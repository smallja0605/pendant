# Pendant

把 MacBook 的瀏海變成可以互動的動態島。游標移到瀏海、點一下就展開成一個小面板，放著常用的小工具；有東西在進行時（播放音樂、計時）會在瀏海旁邊以小膠囊顯示。

使用 Swift / SwiftUI + AppKit 製作，需要 **macOS 14 以上**（Liquid Glass 外觀需要 macOS 26 以上，舊系統自動使用標準材質）。

## 功能

- **動態島**:音樂與計時器等進行中的活動顯示在瀏海旁；有兩個以上時，優先的在主島、其餘分成最多兩個副島。
- **媒體播放器**:Apple Music、Spotify；封面、進度條（可拖曳）、音量、AirPlay 多裝置與各裝置音量。
- **筆記**:自動儲存、輕量 Markdown（粗體、清單、待辦勾選）、釘選、可復原的刪除。
- **待辦事項**:讀寫系統提醒事項；快速新增、日期與更多選項、左滑刪除。
- **行事曆**:日期條與當日行程。
- **計時器**:倒數與碼錶可同時進行。
- **鏡子**:點一下開啟前鏡頭，再點一下關閉。
- **檔案中轉站**:拖入的檔案存成複本（原檔不動），可多選、快速預覽、AirDrop；拖曳檔案靠近瀏海會自動展開。
- **捷徑**:一鍵執行「捷徑」App 的捷徑。
- 觸控板觸覺回饋、可自訂的分頁與小工具排序、動畫參數的開發者視窗。

## 安裝（自用，不經 GitHub）

```bash
scripts/install.sh          # 建置、ad-hoc 簽署，安裝到 /Applications 並開啟
```

本專案沒有 Apple 開發者帳號，App 以 ad-hoc 簽署、未經公證；自己建置的版本不會被 Gatekeeper 擋下。第一次開啟後 App 會在選單列出現圖示，可在「設定 → 一般」設定登入時啟動。

## 更新

```bash
scripts/publish-update.sh 0.1.1   # 建置新版本，放進本機更新資料夾
```

已安裝的 App 會在啟動時與每 24 小時檢查更新，也可以在「設定 → 關於 → 檢查更新」手動檢查；驗證 SHA-256、Bundle ID、簽章與版本後取代 `/Applications/Pendant.app` 並重新啟動。更新來源：

- **一般使用者**：本專案在 GitHub 的 [Releases](https://github.com/smallja0605/pendant/releases)（只接受本專案自己的發佈檔）。
- **開發者本機**：有 `~/Library/Application Support/Pendant/Updates` 資料夾的電腦只讀這個資料夾，不連網。

發佈約每天一次（版本號每天最多升一次）：`scripts/prepare-daily-release.sh` 建置並打包當天版本，確認後 `scripts/publish-github.sh X.Y.Z` 才會提交、推送並建立 GitHub Release。

## 權限與隱私

所有資料只留在你的電腦上，**沒有任何遙測**。檢查更新時，一般使用者的 App 會連到 GitHub 讀取本專案的發佈資訊（不送出任何個人資料，只有 App 版本在 User-Agent 中）；開發者本機只讀本機資料夾。其他對外連線是專輯封面：Apple Music 串流曲目（App 內拿不到封面時）把歌名與歌手送到 Apple 公開的 iTunes 搜尋服務、Spotify 封面從其圖片伺服器載入（可在媒體設定關閉前者）。權限在第一次使用對應功能時才會詢問：

| 權限 | 用途 |
|---|---|
| 行事曆、提醒事項 | 顯示與新增行程、待辦 |
| 相機 | 鏡子（只在你點開時啟動，收合立刻關閉） |
| 自動化（Music、Spotify） | 讀取播放狀態、控制播放與音量 |
| 輔助使用（選用） | 僅「智慧避讓」實驗功能，預設關閉 |

App 不使用 App Sandbox（需要 AppleScript、全域事件監聽），改用 Hardened Runtime，entitlements 只保留上表所需。

## 自行建置

```bash
xcodebuild -project Pendant.xcodeproj -scheme Pendant -configuration Release build
xcodebuild -project Pendant.xcodeproj -scheme Pendant test    # 單元測試
```

需要支援 Swift 6 的 Xcode。開發用的 Swift 工具：`brew install swiftlint gitleaks`，並執行 `scripts/install-hooks.sh` 安裝提交前檢查（SwiftLint 與機密掃描）。

開發者選項視窗（動畫與尺寸參數）:按住 ⌥ 點選單列圖示，或以 `--developer` 啟動。設計決策記錄在 [docs/DECISIONS.md](docs/DECISIONS.md)。

## 解除安裝

「設定 → 關於 → 解除安裝」會移除登入項目、資料夾與偏好設定（可選擇保留筆記），並把 App 移到垃圾桶。

## 授權

[MIT License](LICENSE)
