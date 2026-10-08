#!/bin/bash
# 編譯（有需要時）並執行 iosdraw。用法：./run.sh            全自動輪迴
#                                         ./run.sh --dry-run  只判讀畫面、不點擊
#                                         ./run.sh probe      截圖並列出辨識到的文字
set -euo pipefail
cd "$(dirname "$0")"

major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -lt 15 ]; then echo "需要 macOS 15 以上才有「iPhone 鏡像輸出」（目前 $(sw_vers -productVersion)）。" >&2; exit 1; fi
if ! command -v swiftc >/dev/null; then echo "找不到 swiftc。請先執行：xcode-select --install" >&2; exit 1; fi

if [ ! -x iosdraw ] || [ iosdraw.swift -nt iosdraw ]; then
  echo "編譯 iosdraw…"
  swiftc -O iosdraw.swift -o iosdraw
fi
./iosdraw selftest >/dev/null || { echo "判讀規則自我檢查失敗，請勿執行。" >&2; exit 1; }

case "${1:-}" in
  probe|click|tap|scroll|selftest) exec ./iosdraw "$@" ;;
  *) exec ./iosdraw run "$@" ;;
esac
