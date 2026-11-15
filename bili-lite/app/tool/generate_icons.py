#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Bili Lite 应用图标生成器（v0.1.0 品牌重绘）。

设计：粉色→紫色对角渐变的 squircle，中央白色粗体「bi」字标，
左上玻璃光晕 + 内描边。与应用内 AppLogo（粉色圆 + 白 bi）保持一致，
替换掉原先六端共用的 Flutter 默认蓝色「F」。

输出：
  Android  legacy mipmap ×5 + adaptive foreground ×5 + anydpi-v26 XML + 背景色
  iOS      AppIcon.appiconset 全尺寸（按 Contents.json 自动换算）
  macOS    app_icon_16/32/64/128/256/512/1024.png
  Windows  app_icon.ico（多尺寸）
  Web      favicon.png / Icon-192 / Icon-512 / maskable ×2
  预览      docs/preview/app-icon-v0.1.0.png、app-icon-preview.png

用法：python3 app/tool/generate_icons.py
依赖：Pillow、numpy（沙箱已预装）。幂等，可重复运行。
"""
import glob
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(APP)
S = 2048  # 超采样画布，最后用 LANCZOS 缩到目标尺寸

PINK = (251, 114, 153)      # #FB7299 品牌粉
LIGHT = (255, 166, 201)
VIOLET = (120, 78, 214)


def _font_path():
    patterns = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/**/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/**/LiberationSans-Bold.ttf",
        "/usr/share/fonts/**/*Sans-Bold.ttf",
    ]
    for pat in patterns:
        hit = glob.glob(pat, recursive=True)
        if hit:
            return hit[0]
    raise RuntimeError("找不到粗体无衬线字体，无法绘制字标")


FONT = _font_path()


def _gradient():
    """对角线性渐变 + 左上玻璃光晕。"""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    t = (xx + yy) / (2.0 * (S - 1))
    rgb = np.zeros((S, S, 3), dtype=np.float32)
    stops = [(0.0, LIGHT), (0.46, PINK), (1.0, VIOLET)]
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        sel = (t >= t0) & (t <= t1)
        w = ((t[sel] - t0) / (t1 - t0))[:, None]
        rgb[sel] = np.asarray(c0, dtype=np.float32) * (1 - w) + np.asarray(c1, dtype=np.float32) * w
    dist = np.sqrt((xx - S * 0.26) ** 2 + (yy - S * 0.16) ** 2) / S
    glow = (np.clip(1 - dist / 0.85, 0, 1) ** 1.7 * 0.22)[:, :, None]
    rgb = rgb * (1 - glow) + 255.0 * glow
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")


def _squircle_mask(radius_ratio=0.225):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, S - 1, S - 1), radius=int(S * radius_ratio), fill=255
    )
    return m


def _wordmark(scale=1.0, shadow=True):
    """白色「bi」字标，宽度锚定到画布的 60% * scale。"""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    target_w = S * 0.60 * scale
    size = int(S * 0.60 * scale)
    font = ImageFont.truetype(FONT, size)
    box = d.textbbox((0, 0), "bi", font=font, anchor="lt")
    w = max(1, box[2] - box[0])
    if abs(w - target_w) / target_w > 0.01:
        size = max(8, int(size * target_w / w))
        font = ImageFont.truetype(FONT, size)
    cx, cy = S / 2, S / 2 - S * 0.012
    if shadow:
        d.text((cx + S * 0.011, cy + S * 0.017), "bi", font=font,
               fill=(78, 28, 108, 96), anchor="mm")
    d.text((cx, cy), "bi", font=font, fill=(255, 255, 255, 255), anchor="mm")
    return layer


def _down(img, size):
    if size >= 256:
        return img.resize((size, size), Image.LANCZOS)
    mid = img.resize((256, 256), Image.LANCZOS)
    return mid.resize((size, size), Image.LANCZOS)


_GRAD = _gradient()
_MASK = _squircle_mask()


def render(size, kind="app"):
    """kind: app（圆角方形）/ maskable（满幅方形）/ foreground（透明底字标）"""
    if kind == "foreground":
        # adaptive icon 的 108dp 画布里，可视安全区约 66dp（≈61%），
        # 字标取 60% 画布宽正好落在安全区内，不会被厂商遮罩裁掉。
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        layer.alpha_composite(_wordmark(scale=1.0, shadow=False))
        return _down(layer, size)

    base = _GRAD.copy().convert("RGBA")
    if kind == "maskable":
        base.putalpha(255)
        base.alpha_composite(_wordmark(scale=0.85))
    else:
        base.putalpha(_MASK)
        base.alpha_composite(_wordmark(scale=1.0))
        # 内描边单独合成，避免直接改 base 的 alpha 把渐变挖成半透明
        w = max(2, int(S * 0.006))
        edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(edge).rounded_rectangle(
            (w, w, S - 1 - w, S - 1 - w),
            radius=int(S * 0.225) - w,
            outline=(255, 255, 255, 52),
            width=w,
        )
        base.alpha_composite(edge)
    return _down(base, size)


def write(path, img, **kw):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, **kw)
    return path


def main():
    made = []
    res = os.path.join(APP, "android", "app", "src", "main", "res")

    # ---- Android legacy + adaptive foreground ----
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for dpi, px in legacy.items():
        made.append(write(os.path.join(res, f"mipmap-{dpi}", "ic_launcher.png"), render(px)))
        made.append(write(
            os.path.join(res, f"mipmap-{dpi}", "ic_launcher_foreground.png"),
            render(int(108 * densities[dpi]), kind="foreground"),
        ))
    anydpi = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, "ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    with open(os.path.join(res, "values", "ic_launcher_background.xml"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<resources>\n'
                '    <color name="ic_launcher_background">#FB7299</color>\n'
                '</resources>\n')
    made.append(os.path.join(anydpi, "ic_launcher.xml"))

    # ---- iOS：按 Contents.json 自动换算 size × scale ----
    icon_dir = os.path.join(APP, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    with open(os.path.join(icon_dir, "Contents.json"), encoding="utf-8") as f:
        ios = json.load(f)
    for item in ios["images"]:
        w = float(item["size"].split("x")[0])
        scale = int(item["scale"].rstrip("x"))
        px = int(round(w * scale))
        made.append(write(os.path.join(icon_dir, item["filename"]), render(px)))

    # ---- macOS ----
    mac_dir = os.path.join(APP, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for px in (16, 32, 64, 128, 256, 512, 1024):
        made.append(write(os.path.join(mac_dir, f"app_icon_{px}.png"), render(px)))

    # ---- Windows ICO ----
    ico = os.path.join(APP, "windows", "runner", "resources", "app_icon.ico")
    os.makedirs(os.path.dirname(ico), exist_ok=True)
    big = render(256)
    big.save(ico, format="ICO",
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    made.append(ico)

    # ---- Web ----
    web = os.path.join(APP, "web")
    made.append(write(os.path.join(web, "favicon.png"), render(64)))
    made.append(write(os.path.join(web, "icons", "Icon-192.png"), render(192)))
    made.append(write(os.path.join(web, "icons", "Icon-512.png"), render(512)))
    made.append(write(os.path.join(web, "icons", "Icon-maskable-192.png"),
                      render(192, kind="maskable")))
    made.append(write(os.path.join(web, "icons", "Icon-maskable-512.png"),
                      render(512, kind="maskable")))

    # ---- 预览图 ----
    preview_dir = os.path.join(ROOT, "docs", "preview")
    os.makedirs(preview_dir, exist_ok=True)
    write(os.path.join(preview_dir, "app-icon-v0.1.0.png"), render(1024))

    # 深浅两种桌面底色 + 多尺寸并列，验证小尺寸识别度
    canvas = Image.new("RGB", (980, 520), "#eef1f8")
    d = ImageDraw.Draw(canvas)
    d.text((28, 18), "Bili Lite  ·  app icon v0.1.0", fill="#20263f")
    for row, bg in enumerate(("#eef1f8", "#14182c")):
        y = 62 + row * 230
        d.rounded_rectangle((20, y - 12, 960, y + 200), radius=18, fill=bg)
        x = 44
        for px in (168, 96, 48, 24):
            icon = render(px)
            canvas.paste(icon, (x, y + (168 - px) // 2), icon)
            x += px + 46
    canvas.save(os.path.join(preview_dir, "app-icon-preview.png"))
    made.append(os.path.join(preview_dir, "app-icon-preview.png"))

    print(f"字体：{FONT}")
    print(f"已生成/更新 {len(made)} 个图标资源，主预览：docs/preview/app-icon-v0.1.0.png")
    for p in made[:6]:
        print("  ", os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
