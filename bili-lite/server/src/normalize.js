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

/**
 * 上游的 `rcmd_reason` / `reason` 有三种形态：字符串、对象
 *（`{ content: '已关注', reason_id: 1 }`）、以及对象数组。直接 String(v)
 * 会得到 "[object Object]" 这种脏字符串塞进卡片，所以这里统一收敛成纯文本。
 */
function reasonText(value) {
  if (value === undefined || value === null) return '';
  if (typeof value === 'string') return cleanText(value);
  if (Array.isArray(value)) {
    for (const item of value) {
      const text = reasonText(item);
      if (text) return text;
    }
    return '';
  }
  if (typeof value === 'object') {
    return (
      reasonText(value.content) ||
      reasonText(value.reason) ||
      reasonText(value.text) ||
      reasonText(value.name) ||
      ''
    );
  }
  return cleanText(String(value));
}

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
    reason: reasonText(raw.reason ?? raw.rcmd_reason ?? raw.rec_reason),
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
    reason: reasonText(item.rcmd_reason),
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
    reason: reasonText(item.rcmd_reason),
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

/**
 * 播放地址归一化。
 *
 * B 站的 playurl 有两种形态：
 *   * `durl` —— 单文件 mp4，兼容性最好，桌面与移动端都能直接播
 *   * `dash` —— 音视频分离的 m4s，需要 MSE / ExoPlayer 才能合流
 *
 * 应用内播放统一取 `durl`：它是**渐进式单文件**，可以边下边播、不需要
 * 合流逻辑，六端行为一致。DASH 分辨率更高但对播放端要求高得多，
 * 这里只保留清晰度信息供 UI 展示。
 */
function normalizePlayurl(data) {
  const durl = Array.isArray(data?.durl) ? data.durl : [];
  const first = durl[0] || {};
  return {
    // 完整地址：客户端要能直接用，所以保留 query（里面有鉴权签名）
    url: str(first.url),
    size: num(first.size),
    // 备用地址：主 CDN 抽风时可以让客户端换一个
    backupUrl: str(first.backup_url || (Array.isArray(first.backup_url) ? first.backup_url[0] : '')),
    quality: num(data?.quality),
    acceptQuality: Array.isArray(data?.accept_quality) ? data.accept_quality.map(num) : [],
    acceptDescription: Array.isArray(data?.accept_description) ? data.accept_description : [],
    format: str(data?.format),
    timelength: num(data?.timelength),
    // 清晰度名称：quality → accept_description 的对应文案
    qualityLabel: qualityLabel(data),
  };
}

function qualityLabel(data) {
  const q = num(data?.quality);
  const list = Array.isArray(data?.accept_description) ? data.accept_description : [];
  const names = {
    120: '4K 超清',
    116: '1080P 60帧',
    112: '1080P 高码率',
    80: '1080P',
    74: '720P 60帧',
    64: '720P',
    32: '480P',
    16: '360P 流畅',
  };
  if (names[q]) return names[q];
  const hit = list.find((x) => num(x?.value) === q);
  return str(hit?.value_desc || hit?.desc) || `${q}`;
}

/**
 * 弹幕 XML → 结构化数组。
 *
 * B 站的 `x/v1/dm/list.so` 返回的是 **deflate(raw) 压缩的 XML**，不是
 * protobuf，也不是未压缩的 JSON。先解压再解析 `<d p="...">` 节点。
 *
 * `p` 字段的格式是：`时间(秒),模式,字号,颜色,发送时间,随机种子,用户ID,行ID`
 * 模式：1=滚动、4=底部、5=顶部。
 */
function parseDanmakuXml(xml) {
  const out = [];
  const re = /<d\s+p="([^"]*)"[^>]*>([\s\S]*?)<\/d>/g;
  let m;
  while ((m = re.exec(xml)) !== null) {
    const attrs = m[1].split(',');
    const time = Number(attrs[0]);
    if (!Number.isFinite(time)) continue;
    out.push({
      time: Math.round(time * 1000), // 毫秒，客户端直接按时间轴对齐
      mode: Number(attrs[1]) || 1,
      size: Number(attrs[2]) || 25,
      color: Number(attrs[3]) || 0xffffff,
      text: decodeXml(m[2]),
    });
  }
  return out;
}

/**
 * 解 XML / HTML 实体。
 *
 * 弹幕文字显示错误的三个根因（均已在本函数修掉）：
 *  1. 数字实体经常是 BMP 之外的码点（emoji，如 `&#128512;`）。
 *     `String.fromCharCode` 只取低 16 位，会把 😀 解成私用区的 ``，
 *     必须用 `String.fromCodePoint`；
 *  2. B 站弹幕里十六进制实体 `&#x1F602;` 很常见，旧正则只认十进制，
 *     结果把实体字符串原样画到屏幕上；
 *  3. `&nbsp;` 等 HTML 命名实体没有还原，也会变成可见的 `&nbsp;` 字面量。
 *
 * `&amp;` 刻意放在最后解：`&amp;lt;` 应当解成字面的 `&lt;`，
 * 不能二次解码成 `<`。
 */
function decodeXml(s) {
  const fromCodePoint = (value, radix) => {
    const n = Number.parseInt(value, radix);
    // 代理区（0xD800~0xDFFF）不是合法 Unicode 标量值，
    // fromCodePoint 会原样吐出一个孤立代理字符，画到屏幕上仍是乱码。
    if (!Number.isFinite(n) || n < 0 || n > 0x10ffff ||
        (n >= 0xd800 && n <= 0xdfff)) return '';
    try {
      return String.fromCodePoint(n);
    } catch (_) {
      // 代理区等非法码点不让弹幕整体挂掉，直接丢弃该实体。
      return '';
    }
  };
  return String(s ?? '')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => fromCodePoint(hex, 16))
    .replace(/&#(\d+);/g, (_, dec) => fromCodePoint(dec, 10))
    .replace(/&amp;/g, '&');
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
  normalizePlayurl,
  parseDanmakuXml,
};
