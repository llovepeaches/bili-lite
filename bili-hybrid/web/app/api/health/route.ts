import { NextResponse } from "next/server";
import { serverFetch } from "@/lib/api";
import type { HealthInfo } from "@/lib/types";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const data = await serverFetch<HealthInfo>("/health");
    return NextResponse.json(data, { headers: { "X-Engine": "rust-pyo3" } });
  } catch (e) {
    return NextResponse.json(
      { status: "unavailable", error: String(e) },
      { status: 502 },
    );
  }
}
