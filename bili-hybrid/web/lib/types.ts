/** 与 Rust model.rs / Python models.py 完全一致的单一数据契约（camelCase）。 */

export interface Owner {
  mid: string;
  name: string;
  face: string;
}

export interface Stat {
  view: number;
  danmaku: number;
  reply: number;
  like: number;
  coin: number;
  favorite: number;
  share: number;
}

export interface Video {
  aid: string;
  bvid: string;
  cid: string;
  title: string;
  cover: string;
  duration: number;
  durationText: string;
  owner: Owner;
  stat: Stat;
  pubdate: number;
  desc: string;
  tname: string;
  reason: string;
  source: string;
  score?: number;
  /** Rust 侧已做过 HTML 转义，可安全内联渲染 */
  highlight?: string;
}

export interface VideoListResponse {
  source?: string;
  engine?: string;
  query?: string;
  policy?: Record<string, number>;
  total: number;
  items: Video[];
}

export interface Aggregate {
  count: number;
  totalView: number;
  totalLike: number;
  totalDuration: number;
  avgDuration: number;
  bySource: Record<string, number>;
}

export interface HealthInfo {
  status: string;
  rust: {
    version: string;
    engine: string;
    bindings: string;
    kernel: string;
    parallel: boolean;
    capabilities: string[];
  };
  cache: { entries: number; capacity: number; hits: number; misses: number };
  upstream: { available: boolean; mode: string; feedItems: number; sources: string[] };
}

export interface ApiError {
  error: { code: string; message: string };
  requestId?: string;
}

export type Tab = "feed" | "rank" | "search";
