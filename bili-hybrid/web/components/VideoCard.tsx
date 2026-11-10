import type { Video } from "@/lib/types";
import { compact, escapeHtml, imgProxy, relative } from "@/lib/api";

/** Server Component：标题高亮由 Rust 预先转义，普通标题在前端再转义一次。 */
export function VideoCard({ video, index }: { video: Video; index?: number }) {
  const titleHtml = video.highlight ?? escapeHtml(video.title);
  return (
    <article className="card">
      <a
        className="cover"
        href={`https://www.bilibili.com/video/${video.bvid}`}
        target="_blank"
        rel="noreferrer"
      >
        {/* 走同源代理，避免第三方域与防盗链；不用 next/image 以保持零额外配置 */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={imgProxy(video.cover)} alt="" loading="lazy" />
        <span className="badge dur">{video.durationText}</span>
        {typeof video.score === "number" && (
          <span className="badge score">{video.score.toFixed(2)}</span>
        )}
        {typeof index === "number" && (
          <span className="badge rankno">{index + 1}</span>
        )}
      </a>
      <div className="cardBody">
        <h3 dangerouslySetInnerHTML={{ __html: titleHtml }} />
        <div className="meta">
          <span className="up">{video.owner.name}</span>
          <span>{compact(video.stat.view)} 播放</span>
          <span>{compact(video.stat.like)} 赞</span>
        </div>
        <div className="sub">
          <span className="tag">{video.source}</span>
          {video.reason && <span className="reason">{video.reason}</span>}
          <span className="time">{relative(video.pubdate)}</span>
        </div>
      </div>
    </article>
  );
}
