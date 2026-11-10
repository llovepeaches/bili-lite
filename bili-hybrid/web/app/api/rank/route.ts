import { NextRequest, NextResponse } from "next/server";
import { serverFetch } from "@/lib/api";
import type { VideoListResponse } from "@/lib/types";

export const dynamic = "force-dynamic";

export async function GET(req: NextRequest) {
  const rawLimit = Number(req.nextUrl.searchParams.get("limit") ?? "20");
  const limit = Number.isFinite(rawLimit) ? Math.min(100, Math.max(1, rawLimit)) : 20;
  const rawHl = Number(req.nextUrl.searchParams.get("halfLifeHours") ?? "72");
  const halfLifeHours = Number.isFinite(rawHl) ? Math.min(8760, Math.max(0.1, rawHl)) : 72;
  try {
    const data = await serverFetch<VideoListResponse>(
      `/v1/rank?limit=${limit}&halfLifeHours=${halfLifeHours}`,
    );
    return NextResponse.json(data);
  } catch (e) {
    return NextResponse.json(
      { error: { code: "UPSTREAM_ERROR", message: String(e) } },
      { status: 502 },
    );
  }
}
