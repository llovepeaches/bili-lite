'use strict';

/**
 * Bili Lite · BFF
 * ------------------------------------------------------------------
 * 零第三方依赖，Node 18+ 直接运行：  node src/index.js
 *
 * 职责：
 *   - 转发并规范化 B 站公开 Web 接口，给 Flutter 多端一个稳定的统一 API
 *   - 统一注入访客身份 / UA / Referer，规避上游风控页
 *   - 内存缓存 + 上游异常自动降级到真实数据快照
 *   - 图片反向代理（Web 端防盗链 / 混合内容）
 *   - 顺带托管 app/build/web，一条命令即可打开完整 App
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const {
  biliGet,
  biliGetBinary,
  cached,
  initIdentity,
  fetchImage,
  fetchStream,
  resolvePlayStreamUrl,
  UpstreamError,
  cache,
} = require('./bili');
const N = require('./normalize');
const mock = require('./mock');
const oauth = require('./oauth');
const qrProxy = require('./qr_proxy');
const passportProxy = require('./passport_proxy');

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || '0.0.0.0';
const MOCK_MODE = process.env.MOCK_MODE === '1';
const WEB_DIR = path.resolve(
  process.env.WEB_DIR || path.join(__dirname, '../../app/build/web')
);

const TTL = {
  feed: 60_000,
  rank: 5 * 60_000,
  popular: 3 * 60_000,
  search: 2 * 60_000,
  video: 10 * 60_000,
  reply: 60_000,
  playurl: 5 * 60_000,
  danmaku: 5 * 60_000,
};

/** 排行榜分区（rid = B 站分区 id） */
const PARTITIONS = [
  { rid: 0, name: '全站' },
  { rid: 1, name: '动画' },
  { rid: 168, name: '国创' },
  { rid: 3, name: '音乐' },
  { rid: 129, name: '舞蹈' },
  { rid: 4, name: '游戏' },
  { rid: 36, name: '知识' },
  { rid: 188, name: '科技' },
  { rid: 234, name: '运动' },
  { rid: 223, name: '汽车' },
  { rid: 160, name: '生活' },
  { rid: 211, name: '美食' },
  { rid: 217, name: '动物圈' },
  { rid: 119, name: '鬼畜' },
  { rid: 155, name: '时尚' },
  { rid: 202, name: '资讯' },
  { rid: 5, name: '娱乐' },
  { rid: 181, name: '影视' },
  { rid: 177, name: '纪录片' },
  { rid: 23, name: '电影' },
  { rid: 11, name: '电视剧' },
];

/* ------------------------------------------------------------------ */
/* HTTP 基础工具                                                       */
/* ------------------------------------------------------------------ */

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
}

function sendJson(res, status, payload) {
  cors(res);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(payload));
}

function ok(res, data, meta = {}) {
  sendJson(res, 200, {
    code: 0,
    message: 'ok',
    data,
    meta: { source: 'live', stale: false, ts: Date.now(), ...meta },
  });
}

/** 把 cached() 的结果转成统一响应，附带数据来源标记，方便 App 展示「离线/缓存」状态 */
function sendCached(res, result) {
  const source = result.fromMock ? 'mock' : result.fromCache ? 'cache' : 'live';
  ok(res, result.value, { source, stale: !!result.stale });
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.map': 'application/json',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

function serveStatic(pathname, res) {
  if (!fs.existsSync(WEB_DIR)) {
    cors(res);
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(
      'Web 构建产物尚未生成。\n请先执行：cd app && flutter build web\n' +
        '然后重新打开本地址。\n'
    );
    return;
  }
  let rel;
  try {
    rel = decodeURIComponent(pathname);
  } catch (_) {
    rel = pathname;
  }
  if (rel === '/' || rel === '') rel = '/index.html';

  const root = path.resolve(WEB_DIR);
  const full = path.resolve(root, '.' + rel);
  if (full !== root && !full.startsWith(root + path.sep)) {
    cors(res);
    res.writeHead(403).end('Forbidden');
    return;
  }

  let file = full;
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    // SPA fallback
    file = path.join(root, 'index.html');
  }
  if (!fs.existsSync(file)) {
    cors(res);
    res.writeHead(404).end('Not Found');
    return;
  }
  cors(res);
  res.writeHead(200, {
    'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
    'Cache-Control': path.basename(file) === 'index.html' ? 'no-cache' : 'public, max-age=3600',
  });
  fs.createReadStream(file).pipe(res);
}

/* ------------------------------------------------------------------ */
/* API 路由                                                            */
/* ------------------------------------------------------------------ */

const endpoints = {
  /** 服务状态 / 数据来源 / 缓存条目数 */
  async '/api/health'(url) {
    const identity = require('./bili').identity;
    return {
      data: {
        status: 'ok',
        version: '1.0.0',
        mockMode: MOCK_MODE,
        identity: identity.identitySource,
        snapshotAt: mock.snapshotAt,
        cacheEntries: cache.size,
        webBuild: fs.existsSync(WEB_DIR),
        uptime: Math.floor(process.uptime()),
        // 只暴露公开配置与是否就绪，绝不返回 client_secret
        oauth: {
          configured: oauth.configured(),
          sandbox: oauth.CFG.sandbox,
          scopes: oauth.CFG.scopes,
        },
      },
      meta: {},
    };
  },

  /** 静态配置：分区、排序方式 */
  async '/api/meta'() {
    return {
      data: {
        partitions: PARTITIONS,
        replySorts: [
          { value: 2, label: '热门' },
          { value: 0, label: '按时间' },
        ],
      },
      meta: { source: 'static' },
    };
  },

  /** 首页推荐流 */
  async '/api/feed'(url) {
    const ps = Math.min(40, Math.max(1, Number(url.searchParams.get('ps')) || 20));
    const freshIdx = Number(url.searchParams.get('fresh_idx')) || 1;
    // 用户手动刷新 / 换一批时绕过缓存，否则 60 秒 TTL 内拿到的是同一批数据。
    const skipCache = url.searchParams.get('skip_cache') === '1';
    if (MOCK_MODE) {
      return { data: mock.feed(), meta: { source: 'mock' } };
    }
    const result = await cached(
      `feed:${ps}:${freshIdx}`,
      TTL.feed,
      () =>
        biliGet('/x/web-interface/index/top/feed/rcmd', {
          ps,
          fresh_type: 3,
          fresh_idx: freshIdx,
          fresh_idx_1h: freshIdx,
        }).then(N.normalizeFeed),
      mock.feed(),
      skipCache
    );
    return { result };
  },

  /** 全站 / 分区排行榜 */
  async '/api/rank'(url) {
    const rid = Number(url.searchParams.get('rid')) || 0;
    const skipCache = url.searchParams.get('skip_cache') === '1';
    if (MOCK_MODE) {
      return { data: mock.rank(), meta: { source: 'mock' } };
    }
    const result = await cached(
      `rank:${rid}`,
      TTL.rank,
      () =>
        biliGet('/x/web-interface/ranking/v2', { rid, type: 'all' }).then(N.normalizeRank),
      mock.rank(),
      skipCache
    );
    return { result };
  },

  /** 热门（综合热门） */
  async '/api/popular'(url) {
    const pn = Math.min(10, Math.max(1, Number(url.searchParams.get('pn')) || 1));
    const ps = Math.min(50, Math.max(1, Number(url.searchParams.get('ps')) || 20));
    const skipCache = url.searchParams.get('skip_cache') === '1';
    if (MOCK_MODE) {
      return { data: mock.popular(), meta: { source: 'mock' } };
    }
    const result = await cached(
      `popular:${pn}:${ps}`,
      TTL.popular,
      () => biliGet('/x/web-interface/popular', { pn, ps }).then(N.normalizePopular),
      mock.popular(),
      skipCache
    );
    return { result };
  },

  /** 视频搜索 */
  async '/api/search'(url) {
    const keyword = (url.searchParams.get('keyword') || '').trim().slice(0, 60);
    const page = Math.min(20, Math.max(1, Number(url.searchParams.get('page')) || 1));
    if (!keyword) {
      return { data: { page: 1, pages: 0, total: 0, list: [], keyword }, meta: { source: 'empty' } };
    }
    if (MOCK_MODE) {
      return { data: mock.search(keyword), meta: { source: 'mock' } };
    }
    const result = await cached(
      `search:${keyword}:${page}`,
      TTL.search,
      () =>
        biliGet('/x/web-interface/search/type', {
          search_type: 'video',
          keyword,
          page,
        }).then(N.normalizeSearch),
      mock.search(keyword)
    );
    return { result };
  },

  /** 视频详情 */
  async '/api/video'(url) {
    const bvid = (url.searchParams.get('bvid') || '').trim();
    const aid = (url.searchParams.get('aid') || '').trim();
    if (!bvid && !aid) {
      const err = new UpstreamError('缺少 bvid 或 aid 参数', 400);
      throw err;
    }
    if (MOCK_MODE) {
      return { data: mock.detail(bvid), meta: { source: 'mock' } };
    }
    const result = await cached(
      `video:${bvid || aid}`,
      TTL.video,
      () =>
        biliGet('/x/web-interface/view', bvid ? { bvid } : { aid }).then(N.normalizeView),
      mock.detail(bvid)
    );
    return { result };
  },

  /** 播放地址（应用内播放用） */
  async '/api/playurl'(url) {
    const bvid = (url.searchParams.get('bvid') || '').trim();
    const cid = (url.searchParams.get('cid') || '').trim();
    const qn = Math.min(120, Math.max(16, Number(url.searchParams.get('qn')) || 64));
    if (!bvid || !cid) {
      throw new UpstreamError('缺少 bvid 或 cid 参数', 400);
    }
    if (MOCK_MODE) {
      return { data: { url: '', quality: 0, qualityLabel: '离线快照', list: [] }, meta: { source: 'mock' } };
    }
    const result = await cached(
      `playurl:${bvid}:${cid}:${qn}`,
      TTL.playurl,
      () =>
        biliGet('/x/player/playurl', {
          bvid,
          cid,
          qn,
          // fnval=1 只返回 durl（单文件 mp4），不要 DASH。
          // DASH 是音视频分离的 m4s，需要合流器才能播，六端行为不一致。
          fnval: 1,
          fourk: 1,
          platform: 'html5',
          high_quality: 1,
        }).then(N.normalizePlayurl),
      null
    );
    return { result };
  },

  /** 弹幕列表（应用内播放器叠加层用） */
  async '/api/danmaku'(url) {
    const oid = (url.searchParams.get('oid') || url.searchParams.get('cid') || '').trim();
    if (!oid) {
      throw new UpstreamError('缺少 oid 参数', 400);
    }
    if (MOCK_MODE) {
      return { data: { count: 0, list: [] }, meta: { source: 'mock' } };
    }
    const result = await cached(
      `danmaku:${oid}`,
      TTL.danmaku,
      async () => {
        const raw = await biliGetBinary('/x/v1/dm/list.so', { oid });
        // 上游返回的是 deflate(raw) 压缩的 XML。
        const zlib = require('zlib');
        let xml;
        try {
          xml = zlib.inflateRawSync(raw).toString('utf8');
        } catch (_) {
          // 少数情况下上游会直接返回未压缩的 XML。
          xml = raw.toString('utf8');
        }
        const list = N.parseDanmakuXml(xml);
        return { count: list.length, list };
      },
      null
    );
    return { result };
  },

  /** 评论列表 */
  async '/api/reply'(url) {
    const aid = (url.searchParams.get('aid') || '').trim();
    const pn = Math.min(50, Math.max(1, Number(url.searchParams.get('pn')) || 1));
    const ps = Math.min(30, Math.max(1, Number(url.searchParams.get('ps')) || 20));
    const sort = [0, 2].includes(Number(url.searchParams.get('sort')))
      ? Number(url.searchParams.get('sort'))
      : 2;
    if (!aid) throw new UpstreamError('缺少 aid 参数', 400);
    if (MOCK_MODE) {
      return { data: mock.reply(), meta: { source: 'mock' } };
    }
    const result = await cached(
      `reply:${aid}:${pn}:${ps}:${sort}`,
      TTL.reply,
      () =>
        biliGet('/x/v2/reply', { type: 1, oid: aid, pn, ps, sort }).then(N.normalizeReply),
      mock.reply()
    );
    return { result };
  },
};

/* ------------------------------------------------------------------ */
/* 服务器                                                              */
/* ------------------------------------------------------------------ */

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    cors(res);
    res.writeHead(204).end();
    return;
  }

  let parsed;
  try {
    parsed = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  } catch (_) {
    sendJson(res, 400, { code: 400, message: 'Bad Request', data: null });
    return;
  }
  const pathname = parsed.pathname.replace(/\/+$/, '') || '/';

  // 图片代理走二进制响应
  if (pathname === '/api/img') {
    try {
      const { body, contentType } = await fetchImage(parsed.searchParams.get('url') || '');
      cors(res);
      res.writeHead(200, {
        'Content-Type': contentType,
        'Cache-Control': 'public, max-age=86400',
      });
      res.end(body);
    } catch (err) {
      sendJson(res, err.status || 502, { code: err.status || 502, message: err.message, data: null });
    }
    return;
  }

  // 视频流代理：二进制 + 流式响应，必须在通用 JSON 分支之前处理。
  if (pathname === '/api/stream') {
    const bvid = (parsed.searchParams.get('bvid') || '').trim();
    const cid = (parsed.searchParams.get('cid') || '').trim();
    const qn = Math.min(120, Math.max(16, Number(parsed.searchParams.get('qn')) || 64));
    if (!bvid || !cid) {
      sendJson(res, 400, { code: 400, message: '缺少 bvid 或 cid 参数', data: null });
      return;
    }
    try {
      // 直链本身有有效期（十几分钟），这里缓存 5 分钟足够覆盖一次观看。
      const streamUrl = await cached(
        `streamurl:${bvid}:${cid}:${qn}`,
        TTL.playurl,
        () => resolvePlayStreamUrl(bvid, cid, qn),
        null
      );
      const up = await fetchStream(streamUrl.value, req.headers.range);
      cors(res);
      res.writeHead(up.status, up.headers);
      if (up.stream) {
        const reader = up.stream.getReader();
        // 客户端断开时立刻停掉上游，避免带宽空转。
        req.on('close', () => {
          reader.cancel().catch(() => {});
        });
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          if (!res.write(Buffer.from(value))) {
            await new Promise((resolve) => res.once('drain', resolve));
          }
        }
        res.end();
      } else {
        res.end();
      }
      console.log(`  GET ${pathname} → ${up.status}`);
    } catch (err) {
      const status = err.status || 502;
      sendJson(res, status, { code: status, message: err.message || '上游错误', data: null });
      console.log(`  GET ${pathname} → ${status} ${err.message}`);
    }
    return;
  }

  // 扫码登录代理：Web 端受 CORS 限制不能直连 passport.bilibili.com，
  // 由同源 BFF 转发。Cookie 只在响应里回给浏览器，不落盘、不进日志。
  if (pathname.startsWith('/api/qr/')) {
    const out = await qrProxy.handle(req, parsed);
    sendJson(res, out.status || 200, out.json);
    console.log(`  ${req.method} ${pathname} → ${out.status || 200}`);
    return;
  }

  // 账号密码 / 短信验证码登录代理：同样只做协议转发。
  // 日志只记路径与 HTTP 状态，绝不打印请求体（含 RSA 密文）、响应 Cookie
  // 或上游业务消息，避免登录态与敏感参数进日志。
  if (pathname.startsWith('/api/passport/')) {
    const out = await passportProxy.handle(req, parsed);
    sendJson(res, out.status || 200, out.json);
    console.log(`  ${req.method} ${pathname} → ${out.status || 200}`);
    return;
  }

  // 官方 OAuth 2.0：独立分支，因为回调会返回 302 / HTML，且需要读 POST body。
  if (pathname.startsWith('/api/oauth/')) {
    const localBase = (
      process.env.PUBLIC_BASE_URL || `http://${req.headers.host || 'localhost'}`
    ).replace(/\/+$/, '');
    const out = await oauth.handle(req, parsed, localBase);
    if (out.redirect) {
      res.writeHead(302, { Location: out.redirect, 'Cache-Control': 'no-store' });
      res.end();
      return;
    }
    if (out.html) {
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      res.end(out.html);
      return;
    }
    sendJson(res, out.status || 200, out.json);
    console.log(`  ${req.method} ${pathname} → ${out.status || 200}`);
    return;
  }

  if (pathname.startsWith('/api/')) {
    const handler = endpoints[pathname];
    if (!handler) {
      sendJson(res, 404, { code: 404, message: `未知接口 ${pathname}`, data: null });
      return;
    }
    try {
      const out = await handler(parsed);
      if (out.result) {
        sendCached(res, out.result);
      } else {
        ok(res, out.data, out.meta || {});
      }
      console.log(`  ${req.method} ${pathname} → 200`);
    } catch (err) {
      const status = err.status || 502;
      sendJson(res, status, { code: status, message: err.message || '上游错误', data: null });
      console.log(`  ${req.method} ${pathname} → ${status} ${err.message}`);
    }
    return;
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    sendJson(res, 405, { code: 405, message: 'Method Not Allowed', data: null });
    return;
  }
  serveStatic(pathname, res);
});

async function main() {
  const id = await initIdentity();
  server.listen(PORT, HOST, () => {
    console.log('');
    console.log('  ┌───────────────────────────────────────────────┐');
    console.log('  │  Bili Lite · BFF 已启动                        │');
    console.log('  └───────────────────────────────────────────────┘');
    console.log(`  API      http://localhost:${PORT}/api/health`);
    console.log(`  Web App  http://localhost:${PORT}/`);
    console.log(`  访客身份 ${id.identitySource}`);
    console.log(`  数据模式 ${MOCK_MODE ? '离线快照 (MOCK_MODE=1)' : 'B 站实时接口 + 异常自动降级'}`);
    console.log(`  Web 产物 ${WEB_DIR} ${fs.existsSync(WEB_DIR) ? '✓' : '（尚未构建）'}`);
    const oc = oauth.configView();
    console.log(
      `  官方登录 ${oc.configured ? (oc.sandbox ? '演示授权（非官方，仅自检）' : '已配置') : '未配置凭证（登录入口停用）'}` +
        ` scope=${oauth.CFG.scopes.join(',')}`
    );
    console.log('');
  });
}

process.on('SIGINT', () => {
  console.log('\n  正在关闭…');
  server.close(() => process.exit(0));
});

main().catch((err) => {
  console.error('启动失败:', err);
  process.exit(1);
});
