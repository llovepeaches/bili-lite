"""从 B 站真实数据快照生成 4 套**字段命名互不相同**的上游原始 JSON。

目的：让 Rust 归一化层有真实的多 schema 负载可验证，且整个工程离线可复现。
数据源是 /workspace/bili-lite/server/src/mock-data.json（2026-11-09 抓取的真实快照）。

    python3 scripts/gen_fixtures.py
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = Path("/workspace/bili-lite/server/src/mock-data.json")
OUT = ROOT / "data" / "upstream"


def clock(seconds: int) -> str:
    h, m, s = seconds // 3600, (seconds % 3600) // 60, seconds % 60
    return f"{h:02d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def main() -> None:
    src = json.loads(SRC.read_text(encoding="utf-8"))
    pool: list[dict] = []
    for key in ("feed", "popular"):
        pool.extend(src.get(key, []))
    for key in ("rank", "search"):
        pool.extend(src.get(key, {}).get("list", []))

    seen: set[str] = set()
    uniq: list[dict] = []
    for v in pool:
        bvid = v.get("bvid")
        if bvid and bvid not in seen:
            seen.add(bvid)
            uniq.append(v)
    OUT.mkdir(parents=True, exist_ok=True)

    def owner(v: dict) -> dict:
        o = v.get("owner", {})
        return {"mid": o.get("mid", ""), "name": o.get("name", ""), "face": o.get("face", "")}

    def stat(v: dict) -> dict:
        return v.get("stat", {})

    # ① 推荐流：pic + owner 对象 + stat 对象 + rcmd_reason 对象
    feed = [
        {
            "aid": v["aid"], "bvid": v["bvid"], "cid": v.get("cid", ""),
            "pic": v["cover"], "title": v["title"], "duration": v["duration"],
            "owner": owner(v), "stat": stat(v), "pubdate": v["pubdate"],
            "rcmd_reason": {"content": v.get("reason") or "为你推荐"},
        }
        for v in uniq
    ]
    (OUT / "feed.json").write_text(json.dumps(feed, ensure_ascii=False), encoding="utf-8")

    # ② 排行榜：嵌套 {note, list:[...]}，多出 score / rank / tname
    rank = {
        "note": "根据稿件内容质量、近期的数据综合展示，动态更新",
        "list": [
            {
                "bvid": v["bvid"], "aid": v["aid"], "pic": v["cover"],
                "title": v["title"], "duration": v["duration"],
                "owner": owner(v), "stat": stat(v), "pubdate": v["pubdate"],
                "score": 10000 - i * 7, "rank": i + 1, "tname": v.get("tname", ""),
            }
            for i, v in enumerate(uniq)
        ],
    }
    (OUT / "rank.json").write_text(json.dumps(rank, ensure_ascii=False), encoding="utf-8")

    # ③ 热门：rcmd_reason 对象 + desc 长文本 + typename
    popular = [
        {
            "bvid": v["bvid"], "aid": v["aid"], "pic": v["cover"],
            "title": v["title"], "duration": v["duration"],
            "owner": owner(v), "stat": stat(v), "pubdate": v["pubdate"],
            "desc": v.get("desc", ""), "typename": v.get("tname", ""),
            "rcmd_reason": {"content": "综合热门"},
        }
        for v in uniq
    ]
    (OUT / "popular.json").write_text(json.dumps(popular, ensure_ascii=False), encoding="utf-8")

    # ④ 搜索：字段差异最大 —— author/mid 扁平、play/review/favorites 扁平、
    #    duration 是 "MM:SS" 字符串、标题里带 <em class="keyword"> 高亮标签
    search_list = []
    for v in uniq:
        title = v["title"]
        tagged = f'<em class="keyword">{title[:2]}</em>{title[2:]}' if len(title) > 2 else title
        s = stat(v)
        o = owner(v)
        search_list.append({
            "bvid": v["bvid"], "aid": v["aid"], "pic": v["cover"],
            "title": tagged, "author": o["name"], "mid": o["mid"], "face": o["face"],
            "play": s.get("view", 0), "danmaku": s.get("danmaku", 0),
            "review": s.get("reply", 0), "like": s.get("like", 0),
            "favorites": s.get("favorite", 0), "coins": s.get("coin", 0),
            "duration": clock(v["duration"]), "pubdate": v["pubdate"],
            "description": v.get("desc", ""), "tag": v.get("tname", ""), "type": "video",
        })
    search = {"page": 1, "pages": 1, "total": len(search_list), "list": search_list}
    (OUT / "search.json").write_text(json.dumps(search, ensure_ascii=False), encoding="utf-8")

    print(f"pool={len(uniq)} 生成 4 套 schema 到 {OUT}")
    for name in ("feed", "rank", "popular", "search"):
        p = OUT / f"{name}.json"
        print(f"  {p.name}: {p.stat().st_size} bytes")


if __name__ == "__main__":
    main()
