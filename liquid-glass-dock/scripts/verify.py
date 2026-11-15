# -*- coding: utf-8 -*-
"""Liquid Glass Dock 最终验收：覆盖光学 / 分层 / 交互 / 交付 / 兼容 / 禁止项。"""
import json
import os

from PIL import Image, ImageChops, ImageDraw, ImageStat
from playwright.sync_api import sync_playwright

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = os.environ.get("LG_URL", "http://127.0.0.1:4173/")
OUT = os.path.join(BASE, "preview")
os.makedirs(OUT, exist_ok=True)

results = []


def check(name, cond, detail=""):
    ok = bool(cond)
    results.append({"name": name, "ok": ok, "detail": str(detail)})
    print(("PASS " if ok else "FAIL ") + name + ("  | " + str(detail) if detail else ""))
    return ok


def set_range(page, label, value):
    page.locator(f'input[type="range"][aria-label="{label}"]').evaluate(
        """(el, v) => {
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(el, String(v));
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        }""",
        value,
    )
    page.wait_for_timeout(260)


def var(page, selector, name):
    return page.locator(selector).first.evaluate(
        "(el, n) => el.style.getPropertyValue(n).trim()", name
    )


def px(v):
    """CSS 变量可能是 '70px' / '0.72' / ''，统一转 float。"""
    return float(str(v).replace("px", "").strip() or 0)


def img_diff(a, b):
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        ib = ib.resize(ia.size)
    st = ImageStat.Stat(ImageChops.difference(ia, ib))
    return sum(st.mean) / 3


def brightness_std(path):
    return ImageStat.Stat(Image.open(path).convert("L")).stddev[0]


errors = []
with sync_playwright() as p:
    browser = p.chromium.launch(
        headless=True,
        args=["--force-color-profile=srgb", "--disable-lcd-text", "--font-render-hinting=none"],
    )
    ctx = browser.new_context(
        viewport={"width": 1680, "height": 1080},
        device_scale_factor=1,
        reduced_motion="no-preference",
        permissions=["clipboard-read", "clipboard-write"],
    )
    page = ctx.new_page()
    page.on("pageerror", lambda e: errors.append("pageerror: " + str(e)))
    page.on(
        "console",
        lambda m: errors.append("console.error: " + m.text) if m.type == "error" else None,
    )
    page.goto(URL, wait_until="networkidle")
    page.wait_for_timeout(1100)

    # ---------- A. 光学：SDF + feDisplacementMap ----------
    optical = page.evaluate(
        """() => {
          const root = document.querySelector('.app-dock');
          const q = s => root.querySelector(s);
          const rf = q('.lg__refraction'), fr = q('.lg__frost'),
                ed = q('.lg__edge'), ct = q('.lg__content');
          const dm = document.querySelector('feDisplacementMap');
          const f  = document.querySelector('filter[id^="lg-refrac-"]');
          const cs = e => getComputedStyle(e);
          return {
            rootClass: root.className,
            refBF: cs(rf).backdropFilter,
            frostBF: cs(fr).backdropFilter,
            rootFilter: cs(root).filter, rootBF: cs(root).backdropFilter,
            rootOpacity: cs(root).opacity,
            contentFilter: cs(ct).filter, contentBF: cs(ct).backdropFilter,
            contentOpacity: cs(ct).opacity,
            z: [rf, fr, ed, ct].map(e => cs(e).zIndex),
            dm: dm && { x: dm.getAttribute('xChannelSelector'),
                        y: dm.getAttribute('yChannelSelector'),
                        scale: dm.getAttribute('scale') },
            cif: f && f.getAttribute('color-interpolation-filters'),
            feImage: !!document.querySelector('feImage'),
            feColorMatrix: !!document.querySelector('feColorMatrix'),
            feGaussianBlur: !!document.querySelector('feGaussianBlur'),
            feBlend: document.querySelector('feBlend') && document.querySelector('feBlend').getAttribute('mode'),
          };
        }"""
    )
    check("Chromium 走 SVG 折射路径", "url(" in optical["refBF"] and "lg-refrac" in optical["refBF"], optical["refBF"])
    check("feDisplacementMap 使用 R/G 通道", optical["dm"] and optical["dm"]["x"] == "R" and optical["dm"]["y"] == "G", optical["dm"])
    check("distortionScale 映射到 filter scale", optical["dm"] and abs(float(optical["dm"]["scale"]) - 78) < 0.01, optical["dm"]["scale"] if optical["dm"] else None)
    check("color-interpolation-filters=sRGB", optical["cif"] == "sRGB", optical["cif"])
    check("滤镜链完整 feImage→displace→colorMatrix→blur→blend", all([optical["feImage"], optical["feColorMatrix"], optical["feGaussianBlur"], optical["feBlend"] == "screen"]), optical["feBlend"])
    check("磨砂层使用函数式 backdrop-filter", "blur(" in optical["frostBF"] and "saturate" in optical["frostBF"], optical["frostBF"])

    # ---------- B. SDF 通道编码 ----------
    sdf = page.evaluate(
        """() => [...document.querySelectorAll('.sdf-preview canvas')].map(c => {
             const x = c.getContext('2d'), w = c.width, h = c.height;
             const px = (a,b) => { const d = x.getImageData(a,b,1,1).data; return [d[0],d[1],d[2]]; };
             return { w, h, mid: px(Math.floor(w/2), Math.floor(h/2)), edge: px(3, Math.floor(h/2)) };
           })"""
    )
    mid = sdf[0]["mid"]
    center_neutral = max(abs(v - 128) for v in mid) <= 10
    edge_deviates = max(abs(a - b) for a, b in zip(sdf[0]["edge"], mid)) > 12
    check("SDF 中央为中性 128", center_neutral, mid)
    check("SDF 轮廓一圈有位移/高光偏差", edge_deviates, sdf[0]["edge"])
    check("R/G/B 三张通道预览均生成", len(sdf) == 4 and all(s["w"] > 0 for s in sdf), [s["w"] for s in sdf])
    profile = page.evaluate(
        """() => {
             const c = document.querySelector('.sdf-preview canvas');
             const x = c.getContext('2d'), w = c.width, h = c.height;
             const dev = (a,b) => { const d = x.getImageData(a,b,1,1).data;
               return Math.max(Math.abs(d[0]-128), Math.abs(d[1]-128), Math.abs(d[2]-128)); };
             return { center: dev(Math.floor(w/2), Math.floor(h/2)),
                      quarter: dev(Math.floor(w/2), Math.floor(h/4)),
                      edge: dev(2, Math.floor(h/2)) };
           }"""
    )
    check("位移剖面从中心向轮廓递增", profile["center"] < profile["quarter"] < profile["edge"], profile)

    # ---------- C. 分层：内容层不被滤镜影响 ----------
    clean_root = optical["rootFilter"] == "none" and optical["rootBF"] == "none" and optical["rootOpacity"] == "1"
    clean_content = optical["contentFilter"] == "none" and optical["contentBF"] == "none" and optical["contentOpacity"] == "1"
    check("根元素无 filter/backdrop-filter/opacity", clean_root, (optical["rootFilter"], optical["rootBF"], optical["rootOpacity"]))
    check("内容层无 filter/backdrop-filter/opacity", clean_content, (optical["contentFilter"], optical["contentBF"], optical["contentOpacity"]))
    check("四层 z-index 严格 1/2/3/4", optical["z"] == ["1", "2", "3", "4"], optical["z"])

    # ---------- 初始截图 ----------
    page.screenshot(path=f"{OUT}/01-full-svg.png", full_page=True)
    page.locator(".app-dock").screenshot(path=f"{OUT}/02-dock-svg.png")
    page.locator(".panel").screenshot(path=f"{OUT}/03-panel-sdf.png")
    page.locator(".fusion-area").screenshot(path=f"{OUT}/04-fusion.png")

    # ---------- D. 交付：滑块 / 复制 / 示例 ----------
    labels = page.locator('.panel input[type="range"]').evaluate_all(
        "els => els.map(e => e.getAttribute('aria-label'))"
    )
    check("四个光学参数滑块齐全", len(labels) == 4, labels)

    page.locator(".copy-btn").click()
    page.wait_for_timeout(250)
    clip = page.evaluate("() => navigator.clipboard.readText()")
    copied_label = page.locator(".copy-btn").inner_text()
    wanted = ["distortionScale={78}", "blur={4}", 'tint="#bfe4ff"', "glow={0.72}"]
    check("复制当前参数含四个 props", all(s in clip for s in wanted), " / ".join(wanted))
    check("复制按钮给出成功反馈", "已复制" in copied_label, copied_label)

    page.locator(".panel__code summary").click()
    code = page.locator(".panel__code").inner_text()
    check("使用示例含组件与四层结构说明", "LiquidGlass" in code and "lg__content" in code and "draggable" in code)

    # ---------- E. 内容层可点 / 键盘 ----------
    before_active = page.locator(".dock-btn.is-active").get_attribute("aria-label")
    page.locator('.dock-btn[aria-label="消息"]').click()
    after_active = page.locator(".dock-btn.is-active").get_attribute("aria-label")
    check("底栏按钮原生可点击且状态更新", before_active != after_active and after_active == "消息", f"{before_active} → {after_active}")
    page.locator('.dock-btn[aria-label="发现"]').focus()
    page.keyboard.press("Enter")
    check("底栏按钮键盘 Enter 可激活", page.locator(".dock-btn.is-active").get_attribute("aria-label") == "发现")

    # ---------- F. 交互：指针高光 / 按压 / 拖拽 / 键盘 / 融合 ----------
    dock = page.locator(".app-dock")
    box = dock.bounding_box()
    page.mouse.move(box["x"] + 12, box["y"] + 10)
    page.wait_for_timeout(180)
    mx1 = var(page, ".app-dock", "--lg-mx")
    page.mouse.move(box["x"] + box["width"] - 12, box["y"] + box["height"] - 10)
    page.wait_for_timeout(180)
    mx2 = var(page, ".app-dock", "--lg-mx")
    check("指针跟随高光（写 CSS 变量，不重渲染）", bool(mx1) and mx1 != mx2, f"{mx1} → {mx2}")

    page.mouse.down()
    page.wait_for_timeout(140)
    press = var(page, ".app-dock", "--lg-press")
    page.mouse.up()
    page.wait_for_timeout(140)
    release = var(page, ".app-dock", "--lg-press")
    check("按压缩放 0.954 并回弹到 1", abs(float(press) - 0.954) < 0.01 and abs(float(release) - 1) < 0.01, f"{press} → {release}")

    blob_a = page.locator(".fusion-blob--a")
    blob_a.scroll_into_view_if_needed()
    page.wait_for_timeout(160)
    ba = blob_a.bounding_box()
    tx0 = var(page, ".fusion-blob--a", "--lg-tx")
    page.mouse.move(ba["x"] + ba["width"] / 2, ba["y"] + ba["height"] / 2)
    page.mouse.down()
    page.mouse.move(ba["x"] + ba["width"] / 2 + 70, ba["y"] + ba["height"] / 2 + 34, steps=12)
    page.mouse.up()
    page.wait_for_timeout(320)
    tx1 = var(page, ".fusion-blob--a", "--lg-tx")
    ty1 = var(page, ".fusion-blob--a", "--lg-ty")
    check("指针拖拽改变玻璃位置", px(tx1) - px(tx0) > 40 and abs(px(ty1)) > 20, f"tx {tx0} → {tx1}, ty {ty1}")

    merge_after_drag = sum(
        px(var(page, s, "--lg-merge"))
        for s in [".fusion-blob--a", ".fusion-blob--b", ".fusion-blob--c"]
    )
    bridges = page.locator(".fusion-bridge").count()
    check("多玻璃靠近时融合形变 + 高光连接带", merge_after_drag > 0 and bridges > 0, f"merge 合计 {merge_after_drag:.3f}, bridge {bridges}")
    page.locator(".fusion-area").screenshot(path=f"{OUT}/05-fusion-merged.png")

    blob_a.focus()
    before_key = var(page, ".fusion-blob--a", "--lg-tx")
    page.keyboard.press("ArrowRight")
    page.wait_for_timeout(200)
    after_key = var(page, ".fusion-blob--a", "--lg-tx")
    page.keyboard.press("Home")
    page.wait_for_timeout(200)
    home_tx = var(page, ".fusion-blob--a", "--lg-tx")
    check("方向键移动 / Home 复位", px(after_key) > px(before_key) and abs(px(home_tx)) < 0.01, f"{before_key} → {after_key} → {home_tx}")

    # ---------- G. 折射弯折像素证据 ----------
    set_range(page, "distortionScale", 0)
    dock.screenshot(path=f"{OUT}/06-refraction-off.png")
    set_range(page, "distortionScale", 140)
    dock.screenshot(path=f"{OUT}/07-refraction-max.png")
    delta = img_diff(f"{OUT}/06-refraction-off.png", f"{OUT}/07-refraction-max.png")
    check("scale 0→140 真的弯折背后内容（像素差）", delta > 1.0, f"平均 RGB 差 {delta:.2f}")
    set_range(page, "distortionScale", 78)

    a = Image.open(f"{OUT}/06-refraction-off.png").convert("RGB")
    b = Image.open(f"{OUT}/07-refraction-max.png").convert("RGB")
    canvas = Image.new("RGB", (a.width * 2 + 24, a.height + 46), "#0b1020")
    canvas.paste(a, (0, 46))
    canvas.paste(b, (a.width + 24, 46))
    d = ImageDraw.Draw(canvas)
    d.text((10, 16), "distortionScale = 0   (no displacement)", fill="#9fb4d8")
    d.text((a.width + 34, 16), "distortionScale = 140  (SDF displacement)", fill="#9fb4d8")
    canvas.save(f"{OUT}/08-refraction-compare.png")

    # ---------- H. 兼容：Safari / Firefox 兜底不空白 ----------
    page.locator(".seg button", has_text="强制兜底").click()
    page.wait_for_timeout(450)
    fb = page.evaluate(
        """() => {
             const root = document.querySelector('.app-dock');
             const rf = root.querySelector('.lg__refraction');
             const fr = root.querySelector('.lg__frost');
             return {
               dmCount: document.querySelectorAll('feDisplacementMap').length,
               refBF: getComputedStyle(rf).backdropFilter,
               frostBF: getComputedStyle(fr).backdropFilter,
               mode: root.getAttribute('data-mode')
             };
           }"""
    )
    dock.screenshot(path=f"{OUT}/09-dock-fallback.png")
    std = brightness_std(f"{OUT}/09-dock-fallback.png")
    check("兜底路径关闭 SVG 位移滤镜", fb["dmCount"] == 0 and fb["refBF"] == "none", fb)
    check("兜底仍保留函数式 backdrop-filter", "blur(" in fb["frostBF"], fb["frostBF"])
    check("兜底不出现空白玻璃", std > 8, f"亮度 std {std:.2f}")
    page.locator(".seg button", has_text="自动").click()
    page.wait_for_timeout(350)

    # ---------- I. reduced-motion 降级 ----------
    page.locator(".toggle input[type=checkbox]").check()
    page.wait_for_timeout(300)
    rm = page.evaluate(
        """() => {
             const r = document.querySelector('.app-dock');
             return { data: r.getAttribute('data-reduced'),
                      boost: r.style.getPropertyValue('--lg-spec-boost').trim(),
                      transition: getComputedStyle(r).transitionDuration };
           }"""
    )
    check("prefers-reduced-motion 降级生效", rm["data"] is not None and rm["boost"] == "0", rm)
    page.locator(".toggle input[type=checkbox]").uncheck()
    page.wait_for_timeout(200)

    # ---------- J. 禁止项 ----------
    forbidden = page.evaluate(
        """() => {
             const cards = [...document.querySelectorAll('.content-card')];
             return {
               lgTotal: document.querySelectorAll('.lg').length,
               dockGlass: document.querySelectorAll('.app-dock .lg').length,
               cardBF: cards.map(c => getComputedStyle(c).backdropFilter),
               cardHasGlass: cards.filter(c => c.querySelector('.lg')).length,
               panelBF: getComputedStyle(document.querySelector('.panel')).backdropFilter
             };
           }"""
    )
    check("没有玻璃叠玻璃（底栏内部无嵌套 .lg）", forbidden["dockGlass"] == 0, forbidden["dockGlass"])
    check("列表 / 正文卡片是普通材质", all(v in ("none", "") for v in forbidden["cardBF"]) and forbidden["cardHasGlass"] == 0, forbidden["cardBF"])
    check("调试面板不用玻璃", forbidden["panelBF"] in ("none", ""), forbidden["panelBF"])
    check("玻璃只用于底栏 + 融合实验区", forbidden["lgTotal"] == 4, forbidden["lgTotal"])

    check("控制台 / 页面零错误", len(errors) == 0, errors[:5])
    browser.close()

summary = {
    "url": URL,
    "total": len(results),
    "passed": sum(1 for r in results if r["ok"]),
    "failed": [r for r in results if not r["ok"]],
    "page_errors": errors,
    "optical": optical,
    "sdf_center_pixel": mid,
    "scale_0_vs_140_mean_rgb_delta": round(delta, 3),
    "fallback_brightness_std": round(std, 2),
    "checks": results,
}
with open(f"{OUT}/verification.json", "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=2)

print("\n==== 汇总 ====")
print(f"{summary['passed']}/{summary['total']} 通过；失败 {len(summary['failed'])} 项")
for r in summary["failed"]:
    print("  -", r["name"], r["detail"])
print("截图输出:", OUT)
