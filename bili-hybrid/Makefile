SHELL := /bin/bash
PYTHON ?= python3.11
API ?= http://127.0.0.1:8000

.PHONY: all test-rust wheel install deps typecheck build-web dev api web verify verify-e2e clean

all: test-rust wheel install deps typecheck build-web

test-rust:
	cargo test -p bili-core

wheel:
	maturin build --release --out dist

install:
	$(PYTHON) -m pip install --force-reinstall dist/*.whl

deps:
	cd web && npm ci --no-audit --no-fund

typecheck:
	cd web && npm run typecheck

build-web:
	cd web && npm run build

# Ctrl+C 会同时停掉两个前台服务
dev:
	@echo "启动 API :8000 与 Web :3000（Ctrl+C 结束）"
	@$(MAKE) -j2 api web

api:
	PYTHONPATH=python uvicorn service.main:app --app-dir python --host 0.0.0.0 --port 8000

web:
	cd web && PYTHON_API_ORIGIN=$(API) npm run start

verify:
	@set -e; \
	for p in "/health" "/v1/videos?source=feed&limit=1" "/v1/rank?limit=3" "/v1/search?q=%E6%80%BB%E5%86%B3%E8%B5%9B" "/v1/stats"; do \
	  printf "%-48s" "$$p"; \
	  curl -sS -o /dev/null -w "HTTP %{http_code}\n" "$(API)$$p"; \
	done; \
	printf "%-48s" "SSE /v1/stream/rank"; \
	curl -sS -N --max-time 10 "$(API)/v1/stream/rank" | grep -c '^event:' | xargs -I{} echo "{} events"

verify-e2e:
	$(PYTHON) scripts/verify_e2e.py

clean:
	rm -rf target web/.next dist/*.whl
	@echo "已清理 target / .next / dist wheel；node_modules 保留"
