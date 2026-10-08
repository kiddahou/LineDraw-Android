# iosdraw：用 Mac 的「iPhone 鏡像輸出」讓 iPhone 自動抽選

iOS 不開放 App 操作其他 App，所以 iPhone 版改由 Mac 透過「iPhone 鏡像輸出」視窗代為點擊。
授權同本倉庫（PolyForm Noncommercial 1.0.0，限非商業使用）。

> **目前狀態：尚未在真實的 LINE 畫面上跑通。** 判讀規則有自我檢查（`./run.sh selftest`），截圖、文字辨識、點擊都確認可用；但「按抽獎 → 關視窗 → 回清單」這段還沒對著實機驗證過，第一次請先用 `--dry-run` 和 `--max 1`。

## 它怎麼運作

[Funbox 抽選頁](https://uxux11.github.io/funbox-line/)本身有「⚡ 自動連抽」模式：回到該頁 2 秒後會自己開下一筆。iosdraw 只負責 LINE 這一側：

1. 活動頁出現後等 1–2 秒，按抽獎（需要時先按加入好友）。
2. 等 1–3 秒，讀結果（中獎／未中獎／已抽過／已結束）。
3. 按活動頁右上角的關閉鈕，再點左上角的「◀ Safari」回到清單。
4. Funbox 開下一筆，重複，直到 Funbox 顯示「全部完成」。

遇到登入、驗證碼會停下來交給本人；已抽過、已結束的直接關掉；同一筆不會按第二次。判讀規則對齊 Android 版的 `app/src/main/java/com/linedraw/app/engine/Rules.kt`。

## 需求

- Mac：macOS 15 以上（Apple 晶片，或有 T2 晶片的 Intel Mac），已登入 Apple 帳號。
- iPhone：iOS 18 以上，與 Mac 登入同一個 Apple 帳號，藍牙與 Wi-Fi 開啟，放在 Mac 旁並鎖定螢幕。
- Xcode 命令列工具：`xcode-select --install`
- iPhone 的 LINE 已登入要抽選的帳號。

## 安裝

```bash
git clone -b full-auto https://github.com/kiddahou/LineDraw-Android.git
cd LineDraw-Android/ios-mirroring
./run.sh selftest
```

`run.sh` 會在第一次執行時自動編譯。

## 權限（只需設定一次）

到「系統設定 → 隱私權與安全性」，把執行 `run.sh` 的終端機 App 加進這兩項，改完後把該 App 完全關掉重開：

- **螢幕與系統錄音**：截圖辨識畫面用。
- **輔助使用**：點擊用。

## 使用

1. 開啟「iPhone 鏡像輸出」，等視窗出現 iPhone 畫面。
2. 在鏡像畫面用 Safari 開 <https://uxux11.github.io/funbox-line/>。
3. 把「抽選模式」切到「⚡ 自動連抽」，按開始，讓它開出第一筆。
4. 在 Mac 終端機執行：

   ```bash
   ./run.sh --dry-run    # 第一次：只印出它看到什麼、打算點哪裡，不會真的點
   ./run.sh --max 1      # 確認判讀正確後，先跑一筆
   ./run.sh              # 全自動，跑到 Funbox 顯示全部完成
   ```

執行期間 Mac 的滑鼠會被拿去點擊，請不要同時操作這台 Mac。要中止按 `Ctrl+C`。

## 選項

| 選項 | 作用 |
| --- | --- |
| `--dry-run` | 只判讀與列印，不點擊 |
| `--max N` | 處理 N 筆後停止 |
| `--close-x 0.93` `--close-y 0.075` | 活動頁關閉鈕在鏡像視窗內的相對位置（0–1），關不掉時調整 |
| `--stall 120` | 這麼多秒沒有任何動作就停止 |

## 除錯指令

| 指令 | 作用 |
| --- | --- |
| `./run.sh probe shot.png` | 截鏡像視窗，列出辨識到的每行文字與螢幕座標 |
| `./run.sh tap 文字` | 找到畫面上的這段文字並點它 |
| `./run.sh click X Y` | 點螢幕座標 |
| `./run.sh selftest` | 檢查判讀規則 |

## 結束代碼與常見狀況

| 訊息 | 代碼 | 處理 |
| --- | --- | --- |
| Funbox 顯示全部完成 | 0 | 正常結束 |
| 畫面要求「請輸入驗證碼」等 | 2 | 在 iPhone 上本人處理後重跑 |
| 關不掉活動頁 | 3 | `probe` 截圖，看關閉鈕位置，調 `--close-x` / `--close-y` |
| Funbox 頁沒有開下一筆 | 4 | 確認已切到「自動連抽」並按過開始 |
| 畫面超過 N 秒認不出來 | 4 | `probe` 看辨識到的文字；按鈕文字不在清單內時，加進 `iosdraw.swift` 的 `Reader` |
| 找不到「iPhone 鏡像輸出」 | 1 | App 沒開，或沒開在執行腳本的這台 Mac 上 |
| 截圖失敗 | 1 | 沒有「螢幕與系統錄音」權限，或終端機改完權限後沒重開 |
| 鏡像視窗顯示「已登出 iCloud」 | — | 這台 Mac 尚未登入 Apple 帳號 |

## 尚待實機確認

- LINE 活動頁的抽獎按鈕文字能否被辨識（文字辨識對「獎／奬」等異體字可能不一致）。
- 關閉鈕的相對位置（預設右上角 0.93, 0.075）。
- 關掉活動頁後，左上角是否出現可點的「◀ Safari」。
- Safari 是否會先跳出「要在 LINE 中打開嗎？」（已處理，但沒看過實際文字）。
