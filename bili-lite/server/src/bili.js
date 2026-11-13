'use strict';

/**
 * 哔哩哔哩公开 Web 接口的薄封装。
 *
 * 要点：
 *  1. B 站对无 Cookie 的请求会返回风控 HTML 页（不是 JSON），因此启动时通过
 *     /x/frontend/finger/spi 换取一份真实 buvid3/buvid4，并在每次请求中带上。
 *  2. 统一 UA / Referer / Origin，避免上游返回拦截页。
 *  3. 所有响应都做「必须是 JSON 且 code === 0」的校验，风控页会被当成错误抛出，
 *     由上层缓存层决定是降级还是返回错误。
 *  4. 内存缓存 + stale-on-error：上游抽风时优先返回上一次成功的数据。
 */

const BILI_API = 'https://api.bilibili.com';
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const REFERER = 'https://www.bilibili.com/';
const TIMEOUT_MS = Number(process.env.UPSTREAM_TIMEOUT || 10000);

/** 视频流是长连接，超时要单独放宽，否则拖动进度条会被中途掐断。 */
const STREAM_TIMEOUT_MS = Number(process.env.STREAM_TIMEOUT || 120000);

// 实测可用的兜底身份，仅当 spi 接口不可达时使用。
const FALLBACK_COOKIE =
  'buvid3=CB62BB7E-D5EA-B569-B6C2-60BFEF7FB92D13930infoc; ' +
  'buvid4=C44E6D04-3F20-97E8-3414-5084AEC6B50313930-026110919-hfNN70iV4anbGzHTbpMRFQ==';

let cookie = FALLBACK_COOKIE;
let identitySource = 'fallback';

const cache = new Map();
const CACHE_MAX = 300;

function baseHeaders() {
  return {
    'User-Agent': UA,
    Referer: REFERER,
    Origin: 'https://www.bilibili.com',
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    Cookie: cookie,
  };
}

/** 启动时换取真实访客身份；失败不影响服务，自动使用兜底身份。 */
async function initIdentity() {
  try {
    const res = await fetch(`${BILI_API}/x/frontend/finger/spi`, {
      headers: baseHeaders(),
      signal: AbortSignal.timeout(8000),
    });
    const body = await res.json();
    const b3 = body?.data?.b_3;
    const b4 = body?.data?.b_4;
    if (b3 && b4) {
      cookie = `buvid3=${b3}; buvid4=${b4}`;
      identitySource = 'spi';
    }
  } catch (_) {
    /* 静默降级 */
  }
  return { identitySource, cookie: cookie.slice(0, 24) + '…' };
}

/**
 * 请求上游接口并做严格校验。
 * @returns {Promise<any>} B 站响应里的 data 字段
 */
async function biliGet(path, params = {}) {
  const url = new URL(path, BILI_API);
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, String(v));
  }
  const res = await fetch(url, {
    headers: baseHeaders(),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const text = await res.text();
  // 风控页 / CDN 错误页会返回 HTML，不能当成接口结果交给客户端。
  if (!text.trim().startsWith('{')) {
    throw new UpstreamError(`上游返回非 JSON（HTTP ${res.status}），疑似风控`, 502);
  }
  let json;
  try {
    json = JSON.parse(text);
  } catch (_) {
    throw new UpstreamError('上游返回内容无法解析', 502);
  }
  if (json.code !== 0) {
    throw new UpstreamError(`B 站返回 code=${json.code}: ${json.message || '未知错误'}`, 502);
  }
  return json.data ?? json;
}

/**
 * 请求上游的**二进制**接口（弹幕）。
 *
 * 弹幕接口返回的是 deflate(raw) 压缩的 XML，不是 JSON，所以不能走
 * `biliGet`。这里单独提供一个二进制通道，沿用同样的 UA / Referer / 访客身份。
 */
async function biliGetBinary(path, params = {}) {
  const url = new URL(path, BILI_API);
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, String(v));
  }
  const res = await fetch(url, {
    headers: baseHeaders(),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) {
    throw new UpstreamError(`上游返回 HTTP ${res.status}`, 502);
  }
  return Buffer.from(await res.arrayBuffer());
}

class UpstreamError extends Error {
  constructor(message, status) {
    super(message);
    this.name = 'UpstreamError';
    this.status = status;
  }
}

/**
 * 带缓存的取数包装。命中新鲜缓存直接返回；请求失败时若存在陈旧缓存则返回陈旧值。
 * @param {string} key 缓存键
 * @param {number} ttl 毫秒
 * @param {() => Promise<any>} producer
 * @param {any} fallback producer 失败且无缓存时的兜底数据
 * @param {boolean} skipCache 强制绕过缓存重新取数（用户手动刷新时用）
 */
async function cached(key, ttl, producer, fallback = null, skipCache = false) {
  const hit = cache.get(key);

  if (skipCache) {
    // 手动刷新：忽略新鲜缓存重新取数，但请求失败时仍可退回陈旧缓存，
    // 不让用户因为一次上游抖动就看到空列表。
    try {
      const value = await producer();
      if (cache.size >= CACHE_MAX) {
        const oldest = cache.keys().next().value;
        cache.delete(oldest);
      }
      cache.set(key, { value, expireAt: Date.now() + ttl, stale: false });
      return { value, expireAt: 0, stale: false, fromCache: false, refreshed: true };
    } catch (err) {
      if (hit) return { ...hit, stale: true, fromCache: true };
      if (fallback !== null) {
        return { value: fallback, expireAt: 0, stale: true, fromCache: true, fromMock: true };
      }
      throw err;
    }
  }
  if (hit && hit.expireAt > Date.now()) return { ...hit, stale: false, fromCache: true };

  try {
    const value = await producer();
    if (cache.size >= CACHE_MAX) {
      const oldest = cache.keys().next().value;
      cache.delete(oldest);
    }
    cache.set(key, { value, expireAt: Date.now() + ttl, stale: false });
    return { value, expireAt: 0, stale: false, fromCache: false };
  } catch (err) {
    if (hit) return { ...hit, stale: true, fromCache: true };
    if (fallback !== null) {
      return { value: fallback, expireAt: 0, stale: true, fromCache: true, fromMock: true };
    }
    throw err;
  }
}

/** 把 B 站的图片地址规范化为 https 绝对地址。 */
function httpsImage(url) {
  if (!url || typeof url !== 'string') return '';
  if (url.startsWith('//')) return 'https:' + url;
  if (url.startsWith('http://')) return 'https://' + url.slice(7);
  return url;
}

/** 图片反向代理，规避 Web 端 referer 防盗链与混合内容限制。 */
async function fetchImage(rawUrl) {
  const target = httpsImage(rawUrl);
  // 白名单：只允许 B 站图床，避免被当成任意 URL 代理（SSRF）。
  const allow = /(^|\.)hdslb\.com$/i;
  let host;
  try {
    host = new URL(target).hostname;
  } catch (_) {
    throw new UpstreamError('非法图片地址', 400);
  }
  if (!allow.test(host)) throw new UpstreamError('图片域名不在白名单内', 400);

  const res = await fetch(target, {
    headers: { 'User-Agent': UA, Referer: REFERER },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new UpstreamError(`图片上游 HTTP ${res.status}`, 502);
  return {
    body: Buffer.from(await res.arrayBuffer()),
    contentType: res.headers.get('content-type') || 'image/jpeg',
  };
}

/**
 * 视频流反向代理。
 *
 * 为什么需要它：
 *   1. B 站 CDN（*.bilivideo.com）有 referer 防盗链，浏览器直接 <video src>
 *      会被 403；video_player 的 Web 实现也没法给 <video> 元素加请求头。
 *   2. 跨域直连会被 CORS 拦掉。
 *   3. 原生端直连时同一个地址在部分机型上也会 403，需要统一由服务端带
 *      正确 UA / Referer 取流。
 * 所以客户端统一播放 `/api/stream?bvid=&cid=`，由这里换到真实 mp4。
 *
 * 支持 Range 请求（拖动进度条必须有），并透传 206 / Content-Range。
 */
async function fetchStream(rawUrl, rangeHeader) {
  const target = httpsImage(rawUrl);
  const allow = /(^|\.)bilivideo\.com$/i;
  let host;
  try {
    host = new URL(target).hostname;
  } catch (_) {
    throw new UpstreamError('非法视频地址', 400);
  }
  if (!allow.test(host)) {
    throw new UpstreamError('视频域名不在白名单内', 400);
  }

  const headers = {
    'User-Agent': UA,
    Referer: REFERER,
    Origin: 'https://www.bilibili.com',
    Cookie: cookie,
    Accept: '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9',
  };
  if (rangeHeader) headers.Range = rangeHeader;

  const res = await fetch(target, {
    headers,
    // 视频流是长连接，不能用普通接口那种 10 秒超时。
    signal: AbortSignal.timeout(STREAM_TIMEOUT_MS),
  });
  if (!res.ok && res.status !== 206) {
    throw new UpstreamError(`视频上游 HTTP ${res.status}`, 502);
  }
  return {
    status: res.status,
    headers: {
      'Content-Type': res.headers.get('content-type') || 'video/mp4',
      'Content-Length': res.headers.get('content-length') || '',
      'Content-Range': res.headers.get('content-range') || '',
      'Accept-Ranges': res.headers.get('accept-ranges') || 'bytes',
    },
    // 视频动辄上百 MB，必须流式转发，不能整段读进内存。
    stream: res.body,
  };
}

/** 取某视频的可播放直链（durl[0]），供 /api/stream 使用。 */
async function resolvePlayStreamUrl(bvid, cid, qn) {
  const data = await biliGet('/x/player/playurl', {
    bvid,
    cid,
    qn,
    fnval: 1,
    fourk: 1,
    platform: 'html5',
    high_quality: 1,
  });
  const durl = Array.isArray(data?.durl) ? data.durl : [];
  const url = durl[0]?.url || '';
  if (!url) throw new UpstreamError('上游未返回可播放地址', 502);
  return url;
}

module.exports = {
  biliGet,
  biliGetBinary,
  cached,
  initIdentity,
  fetchImage,
  fetchStream,
  resolvePlayStreamUrl,
  httpsImage,
  UpstreamError,
  cache,
  get identity() {
    return { identitySource };
  },
};
