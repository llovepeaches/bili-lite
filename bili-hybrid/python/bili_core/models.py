"""跨语言共享的数据契约（与 Rust model.rs 的 camelCase 输出一一对应）。"""
from __future__ import annotations

from typing import NotRequired, TypedDict


class Owner(TypedDict):
    mid: str
    name: str
    face: str


class Stat(TypedDict):
    view: int
    danmaku: int
    reply: int
    like: int
    coin: int
    favorite: int
    share: int


class Video(TypedDict):
    aid: str
    bvid: str
    cid: str
    title: str
    cover: str
    duration: int
    durationText: str
    owner: Owner
    stat: Stat
    pubdate: int
    desc: str
    tname: str
    reason: str
    source: str
    score: NotRequired[float]
    highlight: NotRequired[str]


class Aggregate(TypedDict):
    count: int
    totalView: int
    totalLike: int
    totalDuration: int
    avgDuration: int
    bySource: dict[str, int]


class CacheStats(TypedDict):
    entries: int
    capacity: int
    hits: int
    misses: int
