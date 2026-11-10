import { PYTHON_API_ORIGIN } from "@/lib/api";

export const dynamic = "force-dynamic";

/** SSE 透传：不解析、不缓冲，把 FastAPI 的字节流原样交给浏览器 EventSource。 */
export async function GET() {
  let upstream: Response;
  try {
    upstream = await fetch(`${PYTHON_API_ORIGIN}/v1/stream/rank`, {
      cache: "no-store",
      signal: AbortSignal.timeout(15000),
    });
  } catch (e) {
    return new Response(`upstream unavailable: ${String(e)}`, { status: 502 });
  }
  if (!upstream.ok || !upstream.body) {
    return new Response("upstream stream unavailable", { status: 502 });
  }
  return new Response(upstream.body, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
}
