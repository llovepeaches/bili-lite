"""bili_core —— Rust 计算核心的**精简** Python 包（PyO3 绑定）。

这一层刻意保持很薄，只做三件事，绝不复制业务逻辑：

1. 把 Python 的 list/dict 序列化成 JSON bytes 交给 Rust；
2. 把 Rust 返回的 bytes 反序列化回 Python；
3. 把 PyValueError 里携带的结构化错误码翻译成 ``BiliCoreError``。

所有计算都在 Rust 内完成，并通过 ``py.allow_threads`` 释放 GIL。
调用方（FastAPI 服务）只 import 本包，不直接接触 ``_native`` 扩展模块。
"""
from __future__ import annotations

import json
from typing import Any

from . import _native  # type: ignore[attr-defined]  # PyO3 编译产物
from .errors import BiliCoreError
from .models import Aggregate, CacheStats, Owner, Stat, Video

__version__: str = getattr(_native, "__version__", "0.0.0")

__all__ = [
    "BiliCoreError",
    "Video",
    "Owner",
    "Stat",
    "Aggregate",
    "CacheStats",
    "normalize_batch",
    "rank",
    "search",
    "dedupe",
    "aggregate",
    "core_info",
    "cache_get",
    "cache_put",
    "cache_get_json",
    "cache_set_json",
    "cache_stats",
    "cache_clear",
]


def _call(fn: Any, *args: Any) -> Any:
    try:
        return fn(*args)
    except ValueError as exc:  # Rust 侧统一以 PyValueError + JSON 载荷传递错误
        raise BiliCoreError.from_message(str(exc)) from None


def _dumps(data: Any) -> bytes:
    return json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def _as_bytes(data: Any) -> bytes:
    return data if isinstance(data, (bytes, bytearray)) else _dumps(data)


def _loads(raw: bytes | None) -> Any:
    return json.loads(raw) if raw else None


# ---------------------------------------------------------------------------
# 业务函数：全部是「一批数据进、一批数据出」的批量语义
# ---------------------------------------------------------------------------

def normalize_batch(source: str, payload: Any) -> list[Video]:
    """把某套上游原始 JSON 归一成统一 Video 列表。

    source ∈ {feed, rank, popular, search, detail}；payload 可为 bytes / list / dict。
    """
    return _loads(_call(_native.normalize_batch, source, _as_bytes(payload)))


def rank(
    videos: Any,
    weights: dict[str, float] | None = None,
    limit: int = 0,
) -> list[Video]:
    """并行加权打分并降序排序；limit=0 不截断。"""
    return _loads(
        _call(
            _native.rank_videos,
            _as_bytes(videos),
            _dumps(weights) if weights else b"",
            int(limit),
        )
    )


def search(videos: Any, query: str, limit: int = 0) -> list[Video]:
    """BM25 检索，结果带 score 与已 HTML 转义的 highlight。"""
    return _loads(_call(_native.search_videos, _as_bytes(videos), query, int(limit)))


def dedupe(videos: Any) -> list[Video]:
    return _loads(_call(_native.dedupe_videos, _as_bytes(videos)))


def aggregate(videos: Any) -> Aggregate:
    return _loads(_call(_native.aggregate_videos, _as_bytes(videos)))


def core_info() -> dict[str, Any]:
    return json.loads(_native.core_info())


# ---------------------------------------------------------------------------
# Rust 侧进程内缓存（跨 Python 线程安全，GIL 外命中）
# ---------------------------------------------------------------------------

def cache_get(key: str) -> bytes | None:
    return _call(_native.cache_get, key)


def cache_put(key: str, value: bytes, ttl_secs: int = 60) -> None:
    _call(_native.cache_put, key, bytes(value), int(ttl_secs))


def cache_get_json(key: str) -> Any:
    raw = cache_get(key)
    return _loads(raw) if raw is not None else None


def cache_set_json(key: str, value: Any, ttl_secs: int = 60) -> None:
    cache_put(key, _dumps(value), ttl_secs)


def cache_stats() -> CacheStats:
    return _loads(_call(_native.cache_stats))


def cache_clear() -> None:
    _call(_native.cache_clear)
