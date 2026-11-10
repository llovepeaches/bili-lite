"""I/O 编排层 —— **只负责取数据，不做任何业务计算**。

这是分层里刻意保留在 Python 的部分：网络 / 磁盘 / 超时 / 重试 / 上游拼装，
这些是 I/O 密集而非 CPU 密集，用 Python 写最省事；一旦拿到原始字节，
立刻整体交给 bili_core（Rust）做归一化、打分、检索。

默认读取 ``data/upstream/*.json`` 离线快照；配置 ``UPSTREAM_BFF_URL`` 后
改为向真实上游发 HTTP 请求，其余各层完全不用改动。
"""
from __future__ import annotations

import json
import os
import urllib.request
from pathlib import Path

import bili_core

def _default_data_dir() -> Path:
    """自动兼容两种部署布局：源码树 python/service/ 与容器 /app/service/。"""
    here = Path(__file__).resolve()
    for base in (here.parents[2], here.parents[1]):
        candidate = base / "data" / "upstream"
        if candidate.is_dir():
            return candidate
    return here.parents[2] / "data" / "upstream"


DATA_DIR = Path(os.getenv("DATA_DIR", str(_default_data_dir())))
BFF_URL = os.getenv("UPSTREAM_BFF_URL", "").rstrip("/")
UPSTREAM_TIMEOUT = float(os.getenv("UPSTREAM_TIMEOUT", "8"))
CACHE_TTL = int(os.getenv("CACHE_TTL", "60"))

SOURCES = ("feed", "rank", "popular", "search")

# 真实上游的可选端点；返回的 JSON 结构由 Rust 归一化层统一兼容。
LIVE_ENDPOINTS = {
    "feed": "/api/feed",
    "rank": "/api/rank",
    "popular": "/api/popular",
    "search": "/api/search?keyword=Flutter",
}


def read_raw(source: str) -> bytes:
    """取某套上游的原始 JSON 字节。"""
    if source not in SOURCES:
        raise ValueError(f"unknown source: {source}")
    if BFF_URL:
        endpoint = LIVE_ENDPOINTS.get(source)
        if endpoint:
            req = urllib.request.Request(
                BFF_URL + endpoint,
                headers={"User-Agent": "bili-hybrid/0.1", "Accept": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=UPSTREAM_TIMEOUT) as resp:
                return resp.read()
    path = DATA_DIR / f"{source}.json"
    if not path.exists():
        raise FileNotFoundError(f"missing upstream fixture: {path}")
    return path.read_bytes()


def load_videos(source: str) -> list[dict]:
    """raw bytes → Rust 归一化 → Rust 去重 → Rust 缓存。"""
    key = f"norm:{source}"
    hit = bili_core.cache_get_json(key)
    if hit is not None:
        return hit
    videos = bili_core.dedupe(bili_core.normalize_batch(source, read_raw(source)))
    bili_core.cache_set_json(key, videos, CACHE_TTL)
    return videos


def all_videos() -> list[dict]:
    """合并四个数据源，按 bvid 去重，得到打分 / 检索的统一候选池。"""
    merged: list[dict] = []
    for source in SOURCES:
        merged.extend(load_videos(source))
    return bili_core.dedupe(merged)


def snapshot_meta() -> dict:
    """快照元信息，仅用于 /health 展示。"""
    path = DATA_DIR / "feed.json"
    try:
        data = json.loads(path.read_bytes())
    except (OSError, ValueError):
        return {"available": False}
    return {
        "available": True,
        "mode": "live" if BFF_URL else "snapshot",
        "feedItems": len(data) if isinstance(data, list) else 0,
        "sources": list(SOURCES),
    }
