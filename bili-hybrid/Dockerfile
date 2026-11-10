# syntax=docker/dockerfile:1
# 多阶段：wheel（Rust+maturin）→ api（FastAPI）→ web（Next.js）

# ---------- Stage 1: 编译 PyO3 wheel ----------
FROM python:3.11-bookworm AS wheel
# python:3.11-bookworm 基于 buildpack-deps，自带 curl / gcc / make / strip，无需额外 apt
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.93.0
ENV PATH="/root/.cargo/bin:${PATH}"
RUN pip install --no-cache-dir maturin==1.16.0
WORKDIR /src
COPY Cargo.toml Cargo.lock pyproject.toml ./
COPY rust ./rust
COPY rust-py ./rust-py
# 只拷纯 Python 源文件；.so 由本阶段重新编译产出
COPY python/bili_core/__init__.py python/bili_core/models.py python/bili_core/errors.py python/bili_core/py.typed ./python/bili_core/
RUN maturin build --release --out /wheels

# ---------- Stage 2: FastAPI 服务 ----------
FROM python:3.11-slim-bookworm AS api
WORKDIR /app
COPY --from=wheel /wheels/*.whl /tmp/
RUN pip install --no-cache-dir /tmp/*.whl "fastapi>=0.110" "uvicorn[standard]>=0.27" \
 && rm -f /tmp/*.whl
COPY python/service ./service
COPY data ./data
# 容器里 service 位于 /app/service，需显式指定快照目录
ENV DATA_DIR=/app/data/upstream \
    CORS_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
EXPOSE 8000
CMD ["uvicorn", "service.main:app", "--host", "0.0.0.0", "--port", "8000"]

# ---------- Stage 3: Next.js 构建 ----------
FROM node:22-alpine AS webbuild
WORKDIR /app
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY web/ ./
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# ---------- Stage 4: Next.js 运行时 ----------
FROM node:22-alpine AS web
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PYTHON_API_ORIGIN=http://api:8000
COPY --from=webbuild /app/package.json ./package.json
COPY --from=webbuild /app/node_modules ./node_modules
COPY --from=webbuild /app/.next ./.next
COPY --from=webbuild /app/next.config.mjs ./next.config.mjs
EXPOSE 3000
CMD ["npm", "run", "start"]
