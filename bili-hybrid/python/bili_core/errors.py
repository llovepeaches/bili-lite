"""Rust 边界错误 → Python 结构化异常。"""
from __future__ import annotations

import json


class BiliCoreError(Exception):
    """Rust 核心抛出的错误，携带机器可读的 code，供 FastAPI 映射 HTTP 状态。"""

    HTTP_STATUS = {
        "INVALID_JSON": 400,
        "INVALID_INPUT": 422,
        "STATE_ERROR": 503,
    }

    def __init__(self, code: str, message: str) -> None:
        self.code = code
        self.message = message
        super().__init__(f"[{code}] {message}")

    @classmethod
    def from_message(cls, raw: str) -> "BiliCoreError":
        try:
            payload = json.loads(raw)
            if isinstance(payload, dict) and "code" in payload:
                return cls(str(payload["code"]), str(payload.get("message", raw)))
        except (ValueError, TypeError):
            pass
        return cls("UNKNOWN", raw)

    @property
    def http_status(self) -> int:
        return self.HTTP_STATUS.get(self.code, 500)
