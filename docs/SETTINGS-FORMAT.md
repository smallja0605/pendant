# Pendant 設定檔格式（Mac 與 Windows 共用）

設定 › 關於 › 設定檔 › 匯出設定，會存成一個 JSON 檔；匯入設定讀同樣的檔。兩個平台的版本都照這份格式讀寫，所以在 Mac 匯出的檔可以在 Windows 匯入，反過來也可以。

```json
{
  "format": "pendant-settings",
  "version": 1,
  "platform": "macOS",
  "app": "0.4.16",
  "exportedAt": "2026-10-27T01:00:00Z",
  "common": { "hoverEffectEnabled": true, "lyricsOffset": 0.3, "focus.waveformBars": 5, "moduleLayout": { } },
  "macOS": { "liquidGlassEnabled": true }
}
```

## 規則

- `format` 必須是 `pendant-settings`；`version` 比讀的程式新時拒絕匯入並請使用者先更新。
- `common`：兩個平台都有的設定，鍵名就是設定名稱（Mac 的偏好設定去掉 `settings.` 前綴）。單獨膠囊的設定用 `focus.` 開頭。
- 以平台命名的區塊（`macOS`、`windows`）：只有那個平台才有的設定。讀檔的程式只套用 `common` 和自己平台的區塊，其他區塊與不認得的鍵一律略過（不報錯）。
- 值只有布林、數字、文字、文字清單；`moduleLayout`（大膠囊的工具順序、格數、分頁）與 `lyricsSources`（歌詞來源清單，含自訂來源）是 JSON 物件／清單。
- 不匯出：鑰匙圈裡的東西（Musixmatch 金鑰、更新簽章私鑰）、這台電腦專屬的項目（筆記資料夾、鏡頭、日曆與提醒清單 ID、看過一次的導覽、快捷鍵）。
- 自訂歌詞來源的網址樣板會一起匯出：網址裡如果放了個人的存取權杖，請先拿掉再分享檔案。

## 鍵名

Mac 的完整清單在 `Pendant/Services/Settings/SettingsTransfer.swift`（`appKeys`、`focusKeys`、`excluded`、`macOnly`），有單元測試確認它和 `AppSettings.swift` 一致。Windows 版有相同功能的設定要用同樣的鍵名與值的意義（例如 `lyricsOffset` 秒、`virtualMiddle` 的 `clock` / `lyrics` / `none`、`wheelSensitivity` 0.25–3）。
