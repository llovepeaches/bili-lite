#!/usr/bin/env python3
"""端到端验收：同源 BFF / SSR / Tab / 搜索 / SSE / 图片代理 / 控制台错误 / 截图。

前置：FastAPI :8000 与 Next.js :3000 均已启动。
用法：python3.11 scripts/verify_e2e.py
"""
from __future__ import annotations

import json
import os
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from playwright.sync_api import sync_playwright

BASE = os.getenv("WEB_ORIGIN", "http://127.0.0.1:3000")
OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "preview")
os.makedirs(OUT, exist_ok=True)

RESULTS: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    RESULTS.append((name, ok, detail))
    print(f"{'PASS' if ok else 'FAIL'} | {name} | {detail}", flush=True)


def get(path: str, timeout: int = 20):
    try:
        with urlopen(BASE + path, timeout=timeout) as r:
            return r.status, dict(r.headers), r.read()
    except HTTPError as e:
        return e.code, dict(e.headers), e.read()


def get_json(path: str, timeout: int = 20):
    status, headers, raw = get(path, timeout)
    try:
        return status, headers, json.loads(raw)
    except ValueError:
        return status, headers, None


# ---------------------------------------------------------------------------
# 1. 同源 BFF 契约
# ---------------------------------------------------------------------------
print("\n=== 1. 同源 /api/* BFF 契约 ===", flush=True)
status, _, health = get_json("/api/health")
check("GET /api/health", status == 200 and health.get("rust", {}).get("engine") == "rust",
      f"HTTP {status} · kernel={health.get('rust', {}).get('kernel') if health else None}")

status, _, videos = get_json("/api/videos?source=feed&limit=3")
check("GET /api/videos", status == 200 and videos.get("total") == 66
      and len(videos.get("items", [])) == 3,
      f"HTTP {status} · total={videos.get('total') if videos else None}")

status, _, ranked = get_json("/api/rank?limit=5&halfLifeHours=72")
check("GET /api/rank", status == 200 and ranked.get("engine") == "rust/rayon"
      and all("score" in v for v in ranked.get("items", [])),
      f"HTTP {status} · top1={ranked['items'][0]['score']:.2f}" if ranked and ranked.get("items") else f"HTTP {status}")

status, _, found = get_json("/api/search?q=%E6%80%BB%E5%86%B3%E8%B5%9B&limit=3")
hl = found.get("items", [{}])[0].get("highlight", "") if found else ""
check("GET /api/search 高亮", status == 200 and "<mark>" in hl, f"HTTP {status} · {hl[:46]}")

status, _, _ = get_json("/api/search?q=")
check("空 q 返回 422", status == 422, f"HTTP {status}")
status, _, _ = get_json("/api/videos?source=unknown")
check("非法 source 返回 422", status == 422, f"HTTP {status}")

# 图片代理：用真实 cover 验证白名单放行
cover = videos["items"][0]["cover"] if videos and videos.get("items") else ""
if cover:
    from urllib.parse import quote
    status, headers, raw = get("/api/img?url=" + quote(cover, safe=""), timeout=20)
    ctype = headers.get("Content-Type", headers.get("content-type", ""))
    check("GET /api/img 白名单放行", status == 200 and ctype.startswith("image/") and len(raw) > 1000,
          f"HTTP {status} · {ctype} · {len(raw)} bytes")
status, _, _ = get("/api/img?url=https%3A%2F%2Fevil.example.com%2Fa.jpg")
check("GET /api/img 拒绝外部域", status == 403, f"HTTP {status}")

# SSE 透传
status, headers, raw = get("/api/stream/rank", timeout=25)
body = raw.decode("utf-8", "replace")
events = [l[7:] for l in body.splitlines() if l.startswith("event: ")]
check("GET /api/stream/rank SSE 透传",
      status == 200 and events.count("source") == 4 and "result" in events and "done" in events,
      f"HTTP {status} · events={events} · {headers.get('Content-Type', headers.get('content-type', ''))}")

# ---------------------------------------------------------------------------
# 2. 浏览器端到端
# ---------------------------------------------------------------------------
print("\n=== 2. Playwright 浏览器验收 ===", flush=True)
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, args=["--no-sandbox"])
    page = browser.new_page(viewport={"width": 1440, "height": 1000}, device_scale_factor=1)
    console_errors: list[str] = []
    page_errors: list[str] = []
    page.on("console", lambda m: console_errors.append(m.text) if m.type == "error" else None)
    page.on("pageerror", lambda e: page_errors.append(str(e)))

    resp = page.goto(BASE + "/", wait_until="domcontentloaded", timeout=30000)
    page.wait_for_selector(".card", timeout=15000)
    cards = page.locator(".card").count()
    health_text = page.locator(".healthBar").inner_text()
    check("SSR 首页渲染", resp.status == 200 and cards == 16,
          f"HTTP {resp.status} · 卡片 {cards} 张")
    check("健康条显示 Rust 内核", "rust" in health_text and "pyo3" in health_text,
          health_text.replace("\n", " ")[:96])

    # SSE 客户端消费
    try:
        page.wait_for_function(
            "document.querySelector('.liveStatus')?.textContent?.trim() === 'done'",
            timeout=20000,
        )
    except Exception:
        pass
    live_status = page.locator(".liveStatus").inner_text()
    rows = page.locator(".liveRow").count()
    tops = page.locator(".liveTop li").count()
    check("SSE 客户端消费完成", live_status == "done" and rows == 4 and tops == 5,
          f"status={live_status} · source 行 {rows} · Top {tops}")

    # 图片：滚动触发 lazy 加载后统计
    page.evaluate("""() => {
      document.querySelectorAll('img[loading="lazy"]').forEach(i => i.loading = 'eager');
      window.scrollTo(0, document.body.scrollHeight);
    }""")
    page.wait_for_timeout(3500)
    img_stats = page.evaluate("""() => {
      const imgs = [...document.querySelectorAll('.card img')];
      return {total: imgs.length, loaded: imgs.filter(i => i.complete && i.naturalWidth > 0).length};
    }""")
    check("封面图片加载", img_stats["loaded"] > 0,
          f"{img_stats['loaded']}/{img_stats['total']} 张（图床可达性取决于外网）")
    page.evaluate("window.scrollTo(0, 0)")
    page.wait_for_timeout(400)
    page.screenshot(path=os.path.join(OUT, "01-home.png"), full_page=True)

    # Tab：热度榜
    page.get_by_role("link", name="热度榜").click()
    page.wait_for_selector(".card", timeout=15000)
    head = page.locator(".sectionHead h2").inner_text()
    scores = page.locator(".badge.score").count()
    check("Tab 切换热度榜", "Rust 并行热度榜" in head and scores > 0,
          f"标题={head} · score 徽标 {scores}")
    page.screenshot(path=os.path.join(OUT, "02-rank.png"), full_page=True)

    # 搜索表单
    page.locator('input[name="q"]').fill("总决赛")
    page.get_by_role("button", name="搜索").click()
    page.wait_for_selector(".card", timeout=15000)
    marks = page.locator(".card h3 mark").count()
    check("搜索表单 + 安全高亮", marks > 0,
          f"URL={page.url.split('?')[-1]} · <mark> {marks} 处")
    page.screenshot(path=os.path.join(OUT, "03-search.png"), full_page=True)

    # 移动端布局
    mobile = browser.new_page(viewport={"width": 390, "height": 844}, device_scale_factor=1)
    mobile.goto(BASE + "/", wait_until="domcontentloaded", timeout=30000)
    mobile.wait_for_selector(".card", timeout=15000)
    mobile.wait_for_timeout(2500)
    cols = mobile.evaluate("""() => getComputedStyle(document.querySelector('.grid')).gridTemplateColumns.split(' ').length""")
    check("390px 响应式单列", cols == 1, f"grid-template-columns 列数={cols}")
    overflow = mobile.evaluate("""() => {
      const c = document.querySelector('.chain');
      return {
        doc: document.documentElement.scrollWidth - innerWidth,
        chain: c.scrollWidth - c.clientWidth,
        chainH: Math.round(c.getBoundingClientRect().height),
      };
    }""")
    check("390px 无横向溢出 / 调用链单行",
          overflow["doc"] <= 1 and overflow["chain"] <= 1 and overflow["chainH"] < 40,
          f"doc 溢出={overflow['doc']}px · chain 溢出={overflow['chain']}px · chain 高={overflow['chainH']}px")
    mobile.screenshot(path=os.path.join(OUT, "05-mobile-top.png"))
    mobile.screenshot(path=os.path.join(OUT, "04-mobile.png"), full_page=True)
    mobile.close()

    check("控制台零错误", not console_errors and not page_errors,
          f"console={len(console_errors)} · pageerror={len(page_errors)}"
          + (f" · {console_errors[:2]}" if console_errors else ""))
    browser.close()

# ---------------------------------------------------------------------------
print("\n=== 汇总 ===", flush=True)
passed = sum(1 for _, ok, _ in RESULTS if ok)
for name, ok, detail in RESULTS:
    if not ok:
        print(f"  FAILED: {name} — {detail}", flush=True)
print(f"{passed}/{len(RESULTS)} 通过", flush=True)
print(f"截图目录：{os.path.abspath(OUT)}", flush=True)
sys.exit(0 if passed == len(RESULTS) else 1)
