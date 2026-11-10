# Bili Hybrid

**Rust 计算内核 + 精简 Python 包 + FastAPI + Next.js** 的四层混合架构示例。业务载体是一份真实 B 站数据快照（2026-11-09，66 条视频，四套不同 schema），用于展示跨语言归一化、并行打分、BM25 检索与 SSE 流式通信。

> 架构设计、接口契约、通信方式、目录结构与构建流程详见 **[ARCHITECTURE.md](./ARCHITECTURE.md)**。

## 一句话调用链

```text
浏览器 → Next.js (SSR / 同源 /api BFF) → FastAPI → bili_core (PyO3) → Rust 内核
                                              ↘ data/upstream/*.json（或真实 BFF）
```

## 快速开始

```bash
# 1. 一次性构建（Rust 单测 → wheel → 安装 → 前端类型检查 + 生产构建）
make all

# 2. 启动两个服务（另开终端，或用 make dev）
make dev
```

- 前端：<http://localhost:3000>
- 后端 API：<http://127.0.0.1:8000/health>
- 交互式文档：<http://127.0.0.1:8000/docs>

不用 `make` 时：

```bash
cargo test -p bili-core
maturin build --release --out dist
pip3 install --force-reinstall dist/*.whl
cd web && npm ci && npm run typecheck && npm run build

# 终端 A
PYTHONPATH=python uvicorn service.main:app --app-dir python --host 0.0.0.0 --port 8000
# 终端 B
cd web && PYTHON_API_ORIGIN=http://127.0.0.1:8000 npm run start
```

容器方式：

```bash
docker compose up --build     # api:8000 + web:3000
```

## 能做什么

| 页面 / 能力 | 说明 |
| --- | --- |
| 推荐流 `/?tab=feed` | SSR 直连 FastAPI，Rust 归一化后的视频网格 |
| 热度榜 `/?tab=rank` | `rayon` 并行加权打分 + 时间半衰期衰减 |
| 搜索 `/?tab=search&q=总决赛` | Rust BM25，标题安全 `<mark>` 高亮 |
| 实时榜单 `LiveRank` | SSE 逐源推送归一化进度，最后推送 Top5 |
| `/api/img` | 同源图片代理，白名单 `*.hdslb.com` + Referer |

## 分层速览

| 层 | 目录 | 职责 |
| --- | --- | --- |
| L1 纯 Rust 内核 | `rust/` | 归一化、打分、检索、聚合、缓存；`rlib`，不依赖 Python |
| L2 PyO3 胶水 | `rust-py/` | `cdylib` → `bili_core._native`；批量 bytes 契约 + 释放 GIL |
| L3a 精简 Python 包 | `python/bili_core/` | 序列化、类型提示、异常映射；**零业务逻辑** |
| L3b FastAPI 服务 | `python/service/` | I/O 编排、REST / SSE、CORS、追踪、错误映射 |
| L4 Next.js | `web/` | SSR 首屏、同源 BFF、SSE 透传、图片代理 |

## 关键接口

| FastAPI | 浏览器同源 BFF | 说明 |
| --- | --- | --- |
| `GET /health` | `/api/health` | 内核 / 缓存 / 上游状态 |
| `GET /v1/videos` | `/api/videos` | 按 source 取归一化列表 |
| `GET /v1/rank` | `/api/rank` | 并行热度榜 |
| `GET /v1/search` | `/api/search` | BM25 检索 |
| `GET /v1/stats` | — | 聚合统计（SSR 使用） |
| `GET /v1/stream/rank` | `/api/stream/rank` | SSE 字节透传 |
| `POST /v1/cache/clear` | — | 清空 Rust 进程内缓存 |
| — | `/api/img` | 图片代理 |

## 常用命令

```bash
make test-rust      # cargo test -p bili-core
make wheel          # maturin build --release --out dist
make install        # pip3 install --force-reinstall dist/*.whl
make typecheck      # tsc --noEmit
make build-web      # next build
make api            # 只启动 FastAPI
make web            # 只启动 Next.js 生产服务
make verify         # curl 端点冒烟
make verify-e2e     # Playwright 端到端 18 项断言 + 截图
make clean          # 清理 target / .next / dist
```

## 验证状态

| 项 | 结果 |
| --- | --- |
| `cargo test -p bili-core` | 7 passed / 0 failed |
| `maturin build --release` | wheel 生成成功 |
| `npm run typecheck` | 0 error |
| `npm run build` | 成功，8 个路由 |
| `python3.11 scripts/verify_e2e.py` | **18/18 通过**，控制台零错误，封面 16/16 加载 |
| `docker compose config -q` | 通过（`api` + `web` 两个服务） |
| `docker compose build` | 配置校验通过；完整镜像构建受沙箱外网限制（Registry / rustup 下载）未实测 |

截图见 `docs/preview/`：`01-home.png`（SSR 首页）、`02-rank.png`（热度榜）、`03-search.png`（BM25 高亮）、`04-mobile.png`、`05-mobile-top.png`（390px 布局）。

## 环境变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `PYTHON_API_ORIGIN` | `http://127.0.0.1:8000` | **仅服务端可见**，刻意不加 `NEXT_PUBLIC_` |
| `CORS_ORIGINS` | `http://localhost:3000,http://127.0.0.1:3000` | FastAPI 允许的来源 |
| `DATA_DIR` | 自动探测 | 上游快照目录 |
| `UPSTREAM_BFF_URL` | 空 | 非空则改为请求真实 BFF，其余层零改动 |
| `CACHE_TTL` | `60` | Rust 侧归一化缓存 TTL（秒） |

## 说明

- 数据来自 B 站公开接口快照，仅用于本地架构演示，非官方应用、不含账号体系、不上传任何数据。
- 快照是真实内容，因此搜索 `Rust` 无命中属正常；试试「总决赛 / 短剧 / 星穹铁道 / 原神 / AI」。
- `/v1/stats` 的 `bySource` 只有 `feed`：四套 fixture 是**同一批 66 条视频的不同 schema**，去重后保留首个来源标记。
