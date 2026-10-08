# iosdraw：用 Mac 的「iPhone 鏡像輸出」操作 iPhone 抽選

iOS 不開放 App 操作其他 App，所以 iPhone 版改由 Mac 透過「iPhone 鏡像輸出」視窗代為點擊。
授權同本倉庫（PolyForm Noncommercial 1.0.0，限非商業使用）。

## 目前進度

- 已完成：`iosdraw.swift` 基礎工具，可截圖、辨識畫面文字（繁中）、點擊、捲動。只確認過能編譯，**尚未在真實的鏡像畫面上跑過**。
- 未完成：自動輪迴。要先對著實際畫面走通一筆，才能寫成自動流程。

## 需求

- Mac：macOS 15 以上，Apple 晶片或 T2 晶片的 Intel Mac。
- iPhone：iOS 18 以上，與 Mac 登入同一個 Apple 帳號，藍牙與 Wi-Fi 開啟，放在 Mac 旁並鎖定螢幕。
- Xcode 命令列工具：`xcode-select --install`

## 編譯

```bash
swiftc -O iosdraw.swift -o iosdraw
```

## 權限

到「系統設定 → 隱私權與安全性」，把執行 `iosdraw` 的終端機 App 加進這兩項，改完後重開該 App：

- 螢幕與系統錄音（截圖用）
- 輔助使用（點擊與捲動用）

## 指令

| 指令 | 作用 |
| --- | --- |
| `./iosdraw probe [截圖路徑]` | 截鏡像視窗，列出辨識到的每行文字與其螢幕座標 |
| `./iosdraw tap 文字` | 找到畫面上的這段文字並點它 |
| `./iosdraw click X Y` | 點螢幕座標 |
| `./iosdraw scroll 行數` | 捲動，負數往下 |

## 要做成的流程

1. iPhone 用 Safari 開 <https://uxux11.github.io/funbox-line/>。
2. 點一個商品的抽獎按鈕，LINE 開啟活動頁。
3. 等 1–2 秒，點抽獎（需要時先加好友）。
4. 等 1–3 秒讀結果。
5. 點活動頁右上角的關閉按鈕，回到清單。
6. 換下一個商品，直到清單沒有可點的為止。

行為請對齊 Android 版（`app/src/main/java/com/linedraw/app/engine/Rules.kt`）：遇到登入、驗證碼要停下來交給本人；已抽過、已結束的略過；不重複送出。

## 接手的下一步

1. 開啟「iPhone 鏡像輸出」並連上 iPhone，Safari 停在 Funbox 頁。
2. 跑 `./iosdraw probe shot.png`，看截圖與辨識結果是否抓得到抽獎按鈕。
3. 用 `tap` / `click` 手動走完一筆，每步都 `probe` 確認畫面。
4. 走通後再把輪迴寫進 `iosdraw.swift`（新增 `run` 指令）。
