import { NextRequest, NextResponse } from "next/server";
import { serverFetch } from "@/lib/api";
import type { VideoListResponse } from "@/lib/types";

export const dynamic = "force-dynamic";

export async function GET(req: NextRequest) {
  const q = (req.nextUrl.searchParams.get("q") ?? "").trim();
  if (!q) {
    return NextResponse.json(
      { error: { code: "INVALID_INPUT", message: "q is required" } },
      { status: 422 },
    );
  }
  const rawLimit = Number(req.nextUrl.searchParams.get("limit") ?? "20");
  const limit = Number.isFinite(rawLimit) ? Math.min(100, Math.max(1, rawLimit)) : 20;
  try {
    const data = await serverFetch<VideoListResponse>(
      `/v1/search?q=${encodeURIComponent(q)}&limit=${limit}`,
    );
    return NextResponse.json(data);
  } catch (e) {
    return NextResponse.json(
      { error: { code: "UPSTREAM_ERROR", message: String(e) } },
      { status: 502 },
    );
  }
}
