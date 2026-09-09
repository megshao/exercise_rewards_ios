#!/usr/bin/env python3
"""把 docs/screenshots/raw/ 的原始截圖縮成 README 內嵌用的尺寸。

**為什麼不直接內嵌原始圖**：原始圖是上架素材的解析度（約 1280x2856），一張 300 KB 上下，
九張就將近 3 MB——而 README 裡的顯示寬度只有 240px。光是打開專案首頁就要下載那些完全
用不到的像素。

兩個處理：
1. 縮到 **480px 寬**（顯示寬度的 2 倍，高解析螢幕上仍然清晰）。
2. 轉成 **256 色調色盤 PNG**。UI 截圖是平色為主，量化後幾乎看不出差別，
   但檔案小 60% 上下（實測最大那張 292 KB → 115 KB）。**刻意不用 JPEG**：
   文字邊緣會出現壓縮雜訊，而這些畫面的重點就是讀得懂上面的字。

重跑：python3 docs/screenshots/readme/make-thumbs.py
原始圖的來源見同層 raw/ 的產生方式（Android 是 scripts/capture-screenshots.sh）。
"""
import os
from PIL import Image

WIDTH = 480
COLOURS = 256

# README 裡實際用到的九張。改這裡就等於改 README 要放哪些畫面。
NAMES = [
    "01-disclaimer.png", "02-login.png", "03-home.png",
    "04-tasks.png", "06-upload.png", "08-redeem.png",
    "09-wallet.png", "10-voucher.png", "11-profile.png",
]

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "..", "raw")

def main():
    total = 0
    for name in NAMES:
        src = os.path.join(RAW, name)
        if not os.path.exists(src):
            print(f"  跳過（raw 裡沒有這張）：{name}")
            continue
        im = Image.open(src).convert("RGB")
        im = im.resize((WIDTH, round(im.height * WIDTH / im.width)), Image.LANCZOS)
        im = im.convert("P", palette=Image.ADAPTIVE, colors=COLOURS)
        dst = os.path.join(HERE, name)
        im.save(dst, "PNG", optimize=True)
        size = os.path.getsize(dst)
        total += size
        print(f"  {name:26s} {WIDTH}x{im.height}  {size:>7,} bytes")
    print(f"  共 {len(NAMES)} 張，合計 {total/1024:.0f} KB")

if __name__ == "__main__":
    main()
