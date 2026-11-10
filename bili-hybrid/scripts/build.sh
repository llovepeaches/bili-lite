#!/usr/bin/env bash
# 一键构建：Rust 内核单测 → PyO3 wheel → 安装 → 前端依赖/类型检查/生产构建
# 用法：bash scripts/build.sh [--rust-only]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PYTHON="${PYTHON:-python3.11}"
SKIP_FRONTEND=0
[[ "${1:-}" == "--rust-only" ]] && SKIP_FRONTEND=1

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }

log "1/6 Rust 内核单元测试（纯 rlib，不链接 libpython）"
cargo test -p bili-core

log "2/6 maturin 构建 PyO3 wheel"
maturin build --release --out dist

log "3/6 安装 wheel 到当前 Python 环境"
"$PYTHON" -m pip install --force-reinstall dist/*.whl

if [[ "$SKIP_FRONTEND" -eq 1 ]]; then
  log "已跳过前端（--rust-only）"
  exit 0
fi

log "4/6 安装前端依赖"
(cd web && npm ci --no-audit --no-fund)

log "5/6 TypeScript 类型检查"
(cd web && npm run typecheck)

log "6/6 Next.js 生产构建"
(cd web && npm run build)

log "构建完成。启动：make dev"
