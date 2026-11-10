"""FastAPI 服务：把 Rust 核心能力暴露成 HTTP/JSON，并演示 SSE 流式进度。

启动：
    uvicorn service.main:app --app-dir python --host 0.0.0.0 --port 8000
"""
from __future__ import annotations

import json
import os
import time
import uuid

import bili_core
from fastapi import FastAPI, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

from service import upstream

app = FastAPI(
    title="Bili Hybrid API",
    version="0.1.0",
    description="Next.js → FastAPI → bili_core(PyO3) → Rust 计算核心",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        o.strip()
        for o in os.getenv(
            "CORS_ORIGINS", "http://localhost:3000,http://127.0.0.1:3000"
        ).split(",")
        if o.strip()
    ],
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Request-Id", "X-Engine", "Server-Timing"],
)


@app.middleware("http")
async def trace(request: Request, call_next):
    """链路追踪：Next.js BFF 传入 X-Request-Id，全程透传并回写耗时。"""
    rid = request.headers.get("X-Request-Id") or uuid.uuid4().hex[:12]
    started = time.perf_counter()
    response = await call_next(request)
    response.headers["X-Request-Id"] = rid
    response.headers["X-Engine"] = "rust-pyo3"
    response.headers["Server-Timing"] = (
        f"api;dur={(time.perf_counter() - started) * 1000:.1f}"
    )
    return response


@app.exception_handler(bili_core.BiliCoreError)
async def on_core_error(request: Request, exc: bili_core.BiliCoreError):
    return JSONResponse(
        status_code=exc.http_status,
        content={
            "error": {"code": exc.code, "message": exc.message},
            "requestId": request.headers.get("X-Request-Id"),
        },
    )


@app.get("/health")
def health():
    return {
        "status": "ok",
        "rust": bili_core.core_info(),
        "cache": bili_core.cache_stats(),
        "upstream": upstream.snapshot_meta(),
    }


@app.get("/v1/videos")
def videos(
    source: str = Query("feed", pattern="^(feed|rank|popular|search)$"),
    limit: int = Query(0, ge=0, le=200),
):
    items = upstream.load_videos(source)
    return {
        "source": source,
        "total": len(items),
        "items": items[:limit] if limit else items,
    }


@app.get("/v1/rank")
def rank(
    limit: int = Query(20, ge=1, le=100),
    halfLifeHours: float = Query(72.0, gt=0, le=8760),
):
    """热度榜：66 条候选在 Rust 侧 rayon 并行打分后排序。"""
    weights = {"halfLifeHours": halfLifeHours}
    items = bili_core.rank(upstream.all_videos(), weights=weights, limit=limit)
    return {"engine": "rust/rayon", "policy": weights, "total": len(items), "items": items}


@app.get("/v1/search")
def search(
    q: str = Query(..., min_length=1, max_length=80),
    limit: int = Query(20, ge=1, le=100),
):
    items = bili_core.search(upstream.all_videos(), q, limit)
    return {"query": q, "engine": "rust/bm25", "total": len(items), "items": items}


@app.get("/v1/stats")
def stats():
    return bili_core.aggregate(upstream.all_videos())


@app.get("/v1/stream/rank")
def stream_rank():
    """SSE：按数据源逐个推送归一化进度，最后推送 Rust 打分 Top5。

    用来演示长任务 / 流式通信：Next.js Route Handler 只做字节透传，
    浏览器用 EventSource 消费，不需要轮询。
    """

    def events():
        started = time.perf_counter()
        total = 0
        for source in upstream.SOURCES:
            items = upstream.load_videos(source)
            total += len(items)
            payload = json.dumps(
                {
                    "source": source,
                    "count": len(items),
                    "elapsedMs": round((time.perf_counter() - started) * 1000, 1),
                },
                ensure_ascii=False,
            )
            yield f"event: source\ndata: {payload}\n\n"
        top = bili_core.rank(upstream.all_videos(), limit=5)
        yield "event: result\ndata: %s\n\n" % json.dumps(
            {
                "total": total,
                "top": [
                    {"title": v["title"], "score": v.get("score"), "bvid": v["bvid"]}
                    for v in top
                ],
            },
            ensure_ascii=False,
        )
        yield "event: done\ndata: {}\n\n"

    return StreamingResponse(
        events(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.post("/v1/cache/clear")
def clear_cache():
    bili_core.cache_clear()
    return {"ok": True, "cache": bili_core.cache_stats()}
