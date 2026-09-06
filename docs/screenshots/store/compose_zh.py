#!/usr/bin/env python3
"""
Sports Rewards — App Store 6.9" screenshot composer (zh-Hant).

Derived from the aso-cosmicmeta-ss skill's compose.py, adapted for:
  - Traditional Chinese headlines (Heiti TC, no space-based word wrap;
    explicit "\\n" line breaks instead)
  - white / warm-cream background with the app's orange accent (#F2711C family)
    instead of the skill's dark-brand-colour default
  - an "eyebrow" compliance pill above every headline
  - device sized so the ENTIRE 1320x2868 raw shot stays visible (tab bar included)

Output is always exactly 1320 x 2868 (Apple 6.9" iPhone).
"""

import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SKILL_ASSETS = "/Users/jackcheng/.claude/skills/aso-cosmicmeta-ss/assets"
FRAME_FILE = os.path.join(SKILL_ASSETS, "iphone_frame.png")

FONT_TC = "/System/Library/Fonts/STHeiti Medium.ttc"
FONT_TC_INDEX = 0          # 0 = Heiti TC, 1 = Heiti SC

CANVAS_W, CANVAS_H = 1320, 2868

# device geometry — solved so screen_y + scaled_shot_height == CANVAS_H
DEVICE_Y = 720
DEVICE_W = 1018
BEZEL = 19
SCREEN_CORNER_R = 126
FRAME_NATIVE_W = 1054

# palette
BG_TOP = (255, 255, 255)
BG_BOTTOM = (255, 244, 234)
GLOW = (242, 113, 28)
EYEBROW_BG = (255, 233, 216)
EYEBROW_FG = (194, 82, 8)
VERB_FG = (232, 89, 12)
DESC_FG = (74, 74, 80)

# typography
EYEBROW_SIZE = 48
EYEBROW_Y = 138
EYEBROW_PAD_X = 40
EYEBROW_PAD_Y = 20
VERB_TOP = 258
VERB_SIZE_MAX = 184
VERB_SIZE_MIN = 128
VERB_STROKE = 5
VERB_DESC_GAP = 56
DESC_SIZE = 64
DESC_LINE_GAP = 22
MAX_TEXT_W = int(CANVAS_W * 0.87)


def font(size):
    return ImageFont.truetype(FONT_TC, size, index=FONT_TC_INDEX)


def text_size(draw, text, f, stroke=0):
    b = draw.textbbox((0, 0), text, font=f, stroke_width=stroke)
    return b[2] - b[0], b[3] - b[1], b


def fit_verb(draw, text):
    for size in range(VERB_SIZE_MAX, VERB_SIZE_MIN - 1, -2):
        f = font(size)
        w, _, _ = text_size(draw, text, f, VERB_STROKE)
        if w <= MAX_TEXT_W:
            return f
    return font(VERB_SIZE_MIN)


def background():
    canvas = Image.new("RGB", (CANVAS_W, CANVAS_H))
    d = ImageDraw.Draw(canvas)
    for y in range(CANVAS_H):
        t = y / (CANVAS_H - 1)
        t = t ** 0.85
        c = tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        d.line([(0, y), (CANVAS_W, y)], fill=c)

    # soft orange glow behind the top of the device
    glow = Image.new("L", (CANVAS_W, CANVAS_H), 0)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-260, DEVICE_Y - 420, CANVAS_W + 260, DEVICE_Y + 700], fill=46)
    glow = glow.filter(ImageFilter.GaussianBlur(180))
    canvas.paste(Image.new("RGB", (CANVAS_W, CANVAS_H), GLOW), (0, 0), glow)
    return canvas.convert("RGBA")


def draw_eyebrow(canvas, text):
    d = ImageDraw.Draw(canvas)
    f = font(EYEBROW_SIZE)
    w, h, b = text_size(d, text, f)
    pill_w = w + EYEBROW_PAD_X * 2
    pill_h = h + EYEBROW_PAD_Y * 2
    x0 = (CANVAS_W - pill_w) // 2
    y0 = EYEBROW_Y
    d.rounded_rectangle([x0, y0, x0 + pill_w, y0 + pill_h],
                        radius=pill_h // 2, fill=EYEBROW_BG)
    d.text((CANVAS_W // 2, y0 + EYEBROW_PAD_Y - b[1]), text,
           font=f, fill=EYEBROW_FG, anchor="mt")
    return y0 + pill_h


def compose(shot_path, eyebrow, verb, desc, out_path):
    canvas = background()
    draw_eyebrow(canvas, eyebrow)
    d = ImageDraw.Draw(canvas)

    # headline
    vf = fit_verb(d, verb)
    vw, vh, vb = text_size(d, verb, vf, VERB_STROKE)
    d.text((CANVAS_W // 2, VERB_TOP - vb[1]), verb, font=vf, fill=VERB_FG,
           anchor="mt", stroke_width=VERB_STROKE, stroke_fill=VERB_FG)
    y = VERB_TOP + vh + VERB_DESC_GAP

    df = font(DESC_SIZE)
    for line in desc.split("\n"):
        lw, lh, lb = text_size(d, line, df)
        if lw > MAX_TEXT_W:
            raise SystemExit(f"desc line too wide ({lw}px > {MAX_TEXT_W}): {line}")
        d.text((CANVAS_W // 2, y - lb[1]), line, font=df, fill=DESC_FG, anchor="mt")
        y += lh + DESC_LINE_GAP
    text_bottom = y - DESC_LINE_GAP
    if text_bottom > DEVICE_Y - 40:
        raise SystemExit(f"text overlaps device: bottom={text_bottom} device_y={DEVICE_Y}")

    device_x = (CANVAS_W - DEVICE_W) // 2
    screen_x = device_x + BEZEL
    screen_y = DEVICE_Y + BEZEL
    screen_w = DEVICE_W - 2 * BEZEL

    # device drop shadow
    sh = Image.new("L", (CANVAS_W, CANVAS_H), 0)
    ImageDraw.Draw(sh).rounded_rectangle(
        [device_x, DEVICE_Y + 22, device_x + DEVICE_W, CANVAS_H + 200],
        radius=160, fill=70)
    sh = sh.filter(ImageFilter.GaussianBlur(46))
    canvas.paste(Image.new("RGB", (CANVAS_W, CANVAS_H), (120, 70, 30)), (0, 0), sh)

    # app screenshot, clipped to the rounded screen area
    shot = Image.open(shot_path).convert("RGBA")
    sc_h = round(shot.height * screen_w / shot.width)
    shot = shot.resize((screen_w, sc_h), Image.LANCZOS)
    screen_h = max(sc_h, CANVAS_H - screen_y)

    mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [screen_x, screen_y, screen_x + screen_w, screen_y + screen_h],
        radius=SCREEN_CORNER_R, fill=255)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        [screen_x, screen_y, screen_x + screen_w, screen_y + screen_h],
        radius=SCREEN_CORNER_R, fill=(0, 0, 0, 255))
    layer.paste(shot, (screen_x, screen_y))
    layer.putalpha(mask)
    canvas = Image.alpha_composite(canvas, layer)

    # device frame overlay, scaled to DEVICE_W
    frame = Image.open(FRAME_FILE).convert("RGBA")
    fw = DEVICE_W
    fh = round(frame.height * fw / frame.width)
    frame = frame.resize((fw, fh), Image.LANCZOS)
    fl = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    fl.paste(frame, (device_x, DEVICE_Y))
    canvas = Image.alpha_composite(canvas, fl)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    canvas.convert("RGB").save(out_path, "PNG")
    im = Image.open(out_path)
    print(f"{out_path}  {im.size[0]}x{im.size[1]}  verb={verb}")
    assert im.size == (CANVAS_W, CANVAS_H)


# 相對於這支腳本自己的位置，不再寫死某台機器的家目錄。
HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "..", "raw")
OUT = HERE
EYEBROW = "揮汗有禮非官方串接"

SET = [
    ("01", "02-login.png", "填一次，免重打",
     "身分證號、生日、手機填一次\n之後登入不用再打一遍"),
    ("02", "03-home.png", "打開就看到重點",
     "本週任務與手上的加碼券\n同一頁看完，不用到處找"),
    ("03", "04-tasks.png", "看懂每一期進度",
     "該上傳、該兌換\n14 期狀態一次標清楚"),
    ("04", "08b-vendor-intro.png", "先看能換什麼",
     "每個通路的可兌換商品分類\n挑定了再送出，不怕換錯"),
    ("05", "06-upload.png", "挑一張截圖送出",
     "從相簿選運動紀錄截圖\n直接送到當期任務"),
    ("06", "09-wallet.png", "加碼券收進券夾",
     "換到的券集中一頁\n要用時打開出示條碼"),
    ("07", "12-profile-security.png", "個資只留在手機",
     "沒有伺服器、不寫紀錄檔\n想刪隨時一鍵清光"),
]

if __name__ == "__main__":
    for num, raw, verb, desc in SET:
        compose(os.path.join(RAW, raw), EYEBROW, verb, desc,
                os.path.join(OUT, f"zh-Hant_{num}.png"))
