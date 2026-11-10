import { LiveRank } from "@/components/LiveRank";
import { VideoCard } from "@/components/VideoCard";
import { serverFetch } from "@/lib/api";
import type { Aggregate, HealthInfo, Tab, VideoListResponse } from "@/lib/types";

// 页面依赖实时后端，禁止构建期静态预渲染。
export const dynamic = "force-dynamic";

type SearchParams = { tab?: string; q?: string };

const TABS: { key: Tab; label: string }[] = [
  { key: "feed", label: "推荐" },
  { key: "rank", label: "热度榜" },
  { key: "search", label: "搜索" },
];

export default async function Home({ searchParams }: { searchParams: SearchParams }) {
  const tab: Tab = TABS.some((t) => t.key === searchParams.tab)
    ? (searchParams.tab as Tab)
    : "feed";
  const q = (searchParams.q ?? "").trim();

  const path =
    tab === "rank"
      ? "/v1/rank?limit=16"
      : tab === "search" && q
        ? `/v1/search?q=${encodeURIComponent(q)}&limit=16`
        : "/v1/videos?source=feed&limit=16";

  let data: VideoListResponse | null = null;
  let error = "";
  try {
    // SSR 路径：Server Component 直接调 FastAPI（服务端到服务端，少一跳）
    data = await serverFetch<VideoListResponse>(path);
  } catch (e) {
    error = String(e);
  }

  let stats: Aggregate | null = null;
  let health: HealthInfo | null = null;
  try {
    [stats, health] = await Promise.all([
      serverFetch<Aggregate>("/v1/stats"),
      serverFetch<HealthInfo>("/health"),
    ]);
  } catch {
    // 统计/健康信息失败不阻塞主体内容
  }

  return (
    <main className="wrap">
      <header className="hero">
        <div className="heroTop">
          <div>
            <h1>
              Bili <em>Hybrid</em>
            </h1>
            <p>四层混合架构 · 一次请求贯穿 Rust / Python / Next.js</p>
          </div>
          <div className="chain" aria-label="调用链">
            <span>Next.js</span><i>→</i><span>FastAPI</span><i>→</i>
            <span>bili_core</span><i>→</i><span>Rust</span>
          </div>
        </div>
        <div className="healthBar">
          <span className={`dot ${health ? "ok" : "bad"}`} />
          <span>
            {health
              ? `内核 ${health.rust.engine} ${health.rust.version} · ${health.rust.bindings} · ${health.rust.kernel}`
              : "后端未连接"}
          </span>
          {health && (
            <>
              <span className="mono">缓存 {health.cache.entries}/{health.cache.capacity} · 命中 {health.cache.hits}</span>
              <span className="mono">数据源 {health.upstream.mode}</span>
            </>
          )}
        </div>
      </header>

      <nav className="tabs">
        {TABS.map((t) => (
          <a key={t.key} href={`/?tab=${t.key}`} className={tab === t.key ? "active" : ""}>
            {t.label}
          </a>
        ))}
        <form className="searchForm" action="/" method="get">
          <input type="hidden" name="tab" value="search" />
          <input name="q" defaultValue={q} placeholder="搜索标题 / UP 主…" aria-label="搜索" />
          <button type="submit">搜索</button>
        </form>
      </nav>

      {stats && (
        <section className="stats">
          <div><b>{stats.count}</b><span>候选视频</span></div>
          <div><b>{(stats.totalView / 1e4).toFixed(1)}万</b><span>总播放</span></div>
          <div><b>{stats.avgDuration}s</b><span>平均时长</span></div>
          <div><b>{health?.upstream.sources.length ?? Object.keys(stats.bySource).length}</b><span>上游源</span></div>
          <div className="engineTag">{data?.engine ?? "rust / normalize"}</div>
        </section>
      )}

      <section className="content">
        <div className="sectionHead">
          <h2>
            {tab === "rank"
              ? "Rust 并行热度榜"
              : tab === "search" && q
                ? `“${q}” 的 BM25 结果`
                : "推荐流"}
          </h2>
          <span>{data ? `${data.total} 条` : "—"}</span>
        </div>

        {error && <div className="errorBox">后端连接失败：{error}</div>}
        {data && data.items.length === 0 && (
          <div className="empty">没有匹配结果，换个关键词试试。</div>
        )}

        <div className="grid">
          {data?.items.map((v, i) => (
            <VideoCard
              key={`${v.bvid}-${i}`}
              video={v}
              index={tab === "rank" ? i : undefined}
            />
          ))}
        </div>
      </section>

      <LiveRank />

      <footer className="foot">
        <span>SSR 直连 FastAPI · 浏览器交互走同源 /api BFF · SSE 流式透传</span>
        <span>非官方示例 · 数据源为 2026-11-09 真实快照</span>
      </footer>
    </main>
  );
}
