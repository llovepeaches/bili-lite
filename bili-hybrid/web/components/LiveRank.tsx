"use client";

import { useEffect, useState } from "react";

interface SourceRow {
  source: string;
  count: number;
  elapsedMs: number;
}
interface StreamResult {
  total: number;
  top: { title: string; score: number | null; bvid: string }[];
}

/** SSE 消费端：浏览器 → Next.js BFF → FastAPI → Rust，字节流全程透传。 */
export function LiveRank() {
  const [rows, setRows] = useState<SourceRow[]>([]);
  const [result, setResult] = useState<StreamResult | null>(null);
  const [status, setStatus] = useState<"idle" | "streaming" | "done" | "error">(
    "idle",
  );

  useEffect(() => {
    const es = new EventSource("/api/stream/rank");
    setStatus("streaming");
    const onSource = (e: Event) => {
      try {
        setRows((prev) => [...prev, JSON.parse((e as MessageEvent).data)]);
      } catch {
        /* 忽略单条脏数据 */
      }
    };
    const onResult = (e: Event) => {
      try {
        setResult(JSON.parse((e as MessageEvent).data));
      } catch {
        /* 同上 */
      }
    };
    const onDone = () => {
      setStatus("done");
      es.close();
    };
    const onError = () => {
      setStatus("error");
      es.close();
    };
    es.addEventListener("source", onSource);
    es.addEventListener("result", onResult);
    es.addEventListener("done", onDone);
    es.addEventListener("error", onError);
    return () => es.close();
  }, []);

  return (
    <section className="live">
      <div className="liveHead">
        <h2>SSE 实时流水线</h2>
        <span className={`liveStatus ${status}`}>{status}</span>
      </div>
      <p className="liveHint">
        浏览器 EventSource → Next.js Route Handler 透传 → FastAPI StreamingResponse →
        Rust 归一化/打分
      </p>
      <div className="liveRows">
        {rows.length === 0 && <div className="liveEmpty">等待上游事件…</div>}
        {rows.map((r) => (
          <div className="liveRow" key={r.source}>
            <b>{r.source}</b>
            <span>{r.count} 条</span>
            <span className="mono">{r.elapsedMs} ms</span>
          </div>
        ))}
      </div>
      {result && (
        <ol className="liveTop">
          {result.top.map((v, i) => (
            <li key={v.bvid + i}>
              <span className="topNo">{i + 1}</span>
              <span className="topTitle">{v.title}</span>
              <span className="mono">{v.score?.toFixed(2) ?? "—"}</span>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}
