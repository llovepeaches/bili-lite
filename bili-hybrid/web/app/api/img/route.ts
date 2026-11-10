import { NextRequest } from "next/server";

/** 同源图片代理：白名单校验 + 注入 Referer，解决 B 站图床防盗链与混合内容。 */
export async function GET(req: NextRequest) {
  const raw = req.nextUrl.searchParams.get("url") ?? "";
  let target: URL;
  try {
    target = new URL(raw);
  } catch {
    return new Response("bad url", { status: 400 });
  }
  if (target.protocol !== "https:" || !/(^|\.)hdslb\.com$/.test(target.hostname)) {
    return new Response("forbidden host", { status: 403 });
  }
  try {
    const upstream = await fetch(target.toString(), {
      headers: {
        Referer: "https://www.bilibili.com/",
        "User-Agent": "Mozilla/5.0 (compatible; BiliHybrid/0.1)",
      },
      signal: AbortSignal.timeout(8000),
    });
    if (!upstream.ok || !upstream.body) {
      return new Response(null, { status: 502 });
    }
    return new Response(upstream.body, {
      headers: {
        "Content-Type": upstream.headers.get("content-type") ?? "image/jpeg",
        "Cache-Control": "public, max-age=86400, immutable",
      },
    });
  } catch {
    return new Response(null, { status: 502 });
  }
}
