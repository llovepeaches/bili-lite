import { NextRequest, NextResponse } from "next/server";
import { serverFetch } from "@/lib/api";
import type { VideoListResponse } from "@/lib/types";

export const dynamic = "force-dynamic";

const SOURCES = new Set(["feed", "rank", "popular", "search"]);

export async function GET(req: NextRequest) {
  const source = req.nextUrl.searchParams.get("source") ?? "feed";
  if (!SOURCES.has(source)) {
    return NextResponse.json(
      { error: { code: "INVALID_INPUT", message: "unknown source" } },
      { status: 422 },
    );
  }
  const rawLimit = Number(req.nextUrl.searchParams.get("limit") ?? "0");
  const limit = Number.isFinite(rawLimit) ? Math.min(200, Math.max(0, rawLimit)) : 0;
  try {
    const data = await serverFetch<VideoListResponse>(
      `/v1/videos?source=${source}&limit=${limit}`,
    );
    return NextResponse.json(data);
  } catch (e) {
    return NextResponse.json(
      { error: { code: "UPSTREAM_ERROR", message: String(e) } },
      { status: 502 },
    );
  }
}
