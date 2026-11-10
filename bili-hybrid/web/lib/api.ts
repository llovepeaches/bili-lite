import { randomUUID } from "node:crypto";

/** 仅服务端可见的上游地址；浏览器永远走同源 /api/*。 */
export const PYTHON_API_ORIGIN =
  process.env.PYTHON_API_ORIGIN ?? "http://127.0.0.1:8000";

/** 服务端 → FastAPI 的统一出口：追踪 ID、超时、错误归一化。 */
export async function serverFetch<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const requestId = randomUUID().slice(0, 12);
  const res = await fetch(`${PYTHON_API_ORIGIN}${path}`, {
    ...init,
    cache: "no-store",
    headers: {
      Accept: "application/json",
      "X-Request-Id": requestId,
      ...(init.headers ?? {}),
    },
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`upstream ${res.status}: ${text.slice(0, 200)}`);
  }
  return (await res.json()) as T;
}

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** 同源图片代理，绕过 B 站防盗链，也避免把第三方域暴露给浏览器。 */
export function imgProxy(url: string): string {
  return `/api/img?url=${encodeURIComponent(url)}`;
}

export function compact(n: number): string {
  if (n >= 1e8) return `${(n / 1e8).toFixed(1)}亿`;
  if (n >= 1e4) return `${(n / 1e4).toFixed(1)}万`;
  return String(n);
}

export function relative(ts: number): string {
  const diff = Math.max(0, Math.floor(Date.now() / 1000) - ts);
  if (diff < 3600) return `${Math.max(1, Math.floor(diff / 60))}分钟前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}小时前`;
  if (diff < 86400 * 30) return `${Math.floor(diff / 86400)}天前`;
  return new Date(ts * 1000).toISOString().slice(0, 10);
}
