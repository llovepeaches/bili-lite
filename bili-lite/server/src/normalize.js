'use strict';

/**
 * 把 B 站各接口（推荐 / 热门 / 排行榜 / 搜索 / 详情 / 评论）差异极大的字段，
 * 统一收敛成 App 侧唯一的数据模型。客户端只认这里的结构，
 * 上游改字段时只需要改这一个文件。
 */

const { httpsImage } = require('./bili');

const num = (v) => {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : 0;
};
const str = (v) => (v === undefined || v === null ? '' : String(v));

/** 去掉搜索结果里的 <em class="keyword"> 高亮标签，并解码常见 HTML 实体。 */
function cleanText(value) {
  return str(value)
    .replace(/<[^>]+>/g, '')
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .trim();
}

/** "12:34" / "1:02:03" / 74 → 秒 */
function toSeconds(value) {
  if (typeof value === 'number') return Math.max(0, Math.floor(value));
  const parts = str(value).split(':').map((p) => parseInt(p, 10) || 0);
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  return parts[0] || 0;
}

/** 秒 → "01:14" / "1:02:03" */
function durationText(seconds) {
  const s = Math.max(0, Math.floor(seconds || 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const pad = (n) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${pad(m)}:${pad(sec)}`;
}

function ownerFrom(mid, name, face) {
  return {
    mid: str(mid),
    name: cleanText(name) || '未知 UP 主',
    face: httpsImage(face),
  };
}

function statFrom(raw = {}) {
  return {
    view: num(raw.view ?? raw.play),
    danmaku: num(raw.danmaku ?? raw.video_review),
    reply: num(raw.reply ?? raw.review),
    like: num(raw.like),
    coin: num(raw.coin),
    favorite: num(raw.favorite ?? raw.favorites),
    share: num(raw.share),
  };
}

/** 统一的视频卡片模型 */
function video(raw) {
  return {
    aid: str(raw.aid ?? raw.id),
    bvid: str(raw.bvid),
    cid: str(raw.cid),
    title: cleanText(raw.title),
    cover: httpsImage(raw.cover ?? raw.pic),
    duration: raw.durationSeconds ?? toSeconds(raw.duration),
    durationText: durationText(raw.durationSeconds ?? toSeconds(raw.duration)),
    owner: raw.owner || ownerFrom(raw.mid, raw.author ?? raw.uname, raw.uface ?? raw.upic),
    stat: raw.stat || statFrom(raw),
    pubdate: num(raw.pubdate),
    desc: cleanText(raw.desc ?? raw.description),
    tname: cleanText(raw.tname ?? raw.typename),
    reason: cleanText(raw.reason ?? raw.rcmd_reason ?? raw.rec_reason),
  };
}

/* ------------------------- 各接口适配器 ------------------------- */

/** 首页推荐流：/x/web-interface/index/top/feed/rcmd */
function fromFeedItem(item) {
  return video({
    aid: item.id,
    bvid: item.bvid,
    cid: item.cid,
    title: item.title,
    cover: item.pic,
    durationSeconds: num(item.duration),
    owner: ownerFrom(item.owner?.mid, item.owner?.name, item.owner?.face),
    stat: statFrom(item.stat),
    pubdate: item.pubdate,
    tname: item.tname,
    reason: item.rcmd_reason?.content ?? item.rcmd_reason?.reason,
  });
}

function normalizeFeed(data) {
  const items = Array.isArray(data?.item) ? data.item : [];
  return items
    .filter((x) => x && (x.goto === 'av' || x.bvid))
    .map(fromFeedItem)
    .filter((x) => x.bvid);
}

/** 排行榜 / 热门：两者字段结构一致 */
function fromRankItem(item) {
  return video({
    aid: item.aid,
    bvid: item.bvid,
    cid: item.cid,
    title: item.title,
    cover: item.pic,
    durationSeconds: num(item.duration),
    owner: ownerFrom(item.owner?.mid, item.owner?.name, item.owner?.face),
    stat: statFrom(item.stat),
    pubdate: item.pubdate,
    desc: item.desc,
    tname: item.tname,
    reason: item.rcmd_reason,
    score: num(item.score),
  });
}

function normalizeRank(data) {
  const items = Array.isArray(data?.list) ? data.list : [];
  return {
    note: str(data?.note),
    list: items.map(fromRankItem).filter((x) => x.bvid),
  };
}

function normalizePopular(data) {
  const items = Array.isArray(data?.list) ? data.list : [];
  return items.map(fromRankItem).filter((x) => x.bvid);
}

/** 搜索：/x/web-interface/search/type */
function fromSearchItem(item) {
  return video({
    aid: item.aid ?? item.id,
    bvid: item.bvid,
    title: item.title,
    cover: item.pic,
    duration: item.duration, // 字符串 "12:34"
    owner: ownerFrom(item.mid, item.author ?? item.uname, item.upic ?? item.uface),
    stat: statFrom({
      view: item.play,
      danmaku: item.video_review,
      reply: item.review,
      like: item.like,
      favorite: item.favorites,
    }),
    pubdate: item.pubdate,
    desc: item.description ?? item.desc,
    tname: item.typename,
  });
}

function normalizeSearch(data) {
  const items = Array.isArray(data?.result) ? data.result : [];
  return {
    page: num(data?.page) || 1,
    pages: num(data?.numPages),
    total: num(data?.numResults),
    list: items
      .filter((x) => x && x.type === 'video')
      .map(fromSearchItem)
      .filter((x) => x.bvid),
  };
}

/** 视频详情：/x/web-interface/view */
function normalizeView(data) {
  if (!data || !data.bvid) return null;
  const base = video({
    aid: data.aid,
    bvid: data.bvid,
    cid: data.cid,
    title: data.title,
    cover: data.pic,
    durationSeconds: num(data.duration),
    owner: ownerFrom(data.owner?.mid, data.owner?.name, data.owner?.face),
    stat: statFrom(data.stat),
    pubdate: data.pubdate,
    desc: data.desc,
    tname: data.tname,
  });
  return {
    ...base,
    // 多 P 视频的分 P 列表，简洁版只展示、不做播放
    pages: (Array.isArray(data.pages) ? data.pages : []).map((p) => ({
      cid: str(p.cid),
      page: num(p.page),
      part: cleanText(p.part),
      duration: num(p.duration),
      durationText: durationText(p.duration),
    })),
    dynamic: cleanText(data.dynamic),
    // 简洁版不展示标签；保留字段占位，便于后续扩展
    tags: [],
  };
}

/** 评论：/x/v2/reply */
function fromReply(r) {
  return {
    id: str(r.rpid),
    mid: str(r.mid),
    uname: cleanText(r.member?.uname),
    avatar: httpsImage(r.member?.avatar),
    level: num(r.member?.level_info?.current_level),
    message: cleanText(r.content?.message),
    like: num(r.like),
    replyCount: num(r.rcount),
    ctime: num(r.ctime),
    isTop: r.reply_control?.is_top ?? false,
    location: cleanText(r.reply_control?.location),
    replies: (Array.isArray(r.replies) ? r.replies : []).slice(0, 3).map((sub) => ({
      id: str(sub.rpid),
      uname: cleanText(sub.member?.uname),
      message: cleanText(sub.content?.message),
      ctime: num(sub.ctime),
    })),
  };
}

function normalizeReply(data) {
  const list = Array.isArray(data?.replies) ? data.replies : [];
  return {
    count: num(data?.page?.count),
    list: list.map(fromReply),
  };
}

module.exports = {
  cleanText,
  toSeconds,
  durationText,
  video,
  normalizeFeed,
  normalizeRank,
  normalizePopular,
  normalizeSearch,
  normalizeView,
  normalizeReply,
};
