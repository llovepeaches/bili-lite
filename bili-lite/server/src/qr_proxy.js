'use strict';

/**
 * B 站 Web 扫码登录的 **Web 端同源代理**。
 *
 * 为什么需要它：
 *   原生端（Android / iOS / 桌面）可以直接请求 passport.bilibili.com，没有
 *   CORS 限制；浏览器里不行——B 站登录域不给第三方站点下发 CORS 头。
 *   所以 Web 端由同源 BFF 转发三步请求，原生端完全不走这里。
 *
 * 边界：
 *   * 服务端只做协议转发，**不落盘、不缓存、不打印**任何登录 Cookie；
 *   * 登录 Cookie 最终只保存在用户浏览器 localStorage（见 qr_session.dart）；
 *   * 这条链路拿的是 B 站 Web 登录态（SESSDATA 等），不是开放平台 token。
 */

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const REFERER = 'https://www.bilibili.com/';
const PASSPORT = 'https://passport.bilibili.com';
const API = 'https://api.bilibili.com';
const TIMEOUT = 12000;

const WANTED = [
  'SESSDATA',
  'bili_jct',
  'DedeUserID',
  'DedeUserID__ckMd5',
  'sid',
  'buvid3',
  'buvid4',
];

function headers(extra = {}) {
  return {
    'User-Agent': UA,
    Referer: REFERER,
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    ...extra,
  };
}

async function getJson(url, extraHeaders = {}) {
  const res = await fetch(url, {
    headers: headers(extraHeaders),
    signal: AbortSignal.timeout(TIMEOUT),
  });
  const text = await res.text();
  if (!text.trim().startsWith('{')) {
    throw new Error(`上游返回非 JSON（HTTP ${res.status}），疑似风控`);
  }
  let json;
  try {
    json = JSON.parse(text);
  } catch (_) {
    throw new Error('上游返回内容无法解析');
  }
  return { res, json };
}

/** Set-Cookie 可能有多段，Node 22 的 Headers.getSetCookie() 能正确拆开。 */
function setCookies(res) {
  if (typeof res.headers.getSetCookie === 'function') {
    return res.headers.getSetCookie();
  }
  const raw = res.headers.get('set-cookie');
  return raw ? [raw] : [];
}

/** 与 Dart 端 QrLoginApi.buildCookie 保持同样的字段集合与优先级。 */
function buildCookie(cookieHeaders, rawUrl) {
  const values = new Map();
  for (const line of cookieHeaders) {
    const first = String(line).split(';')[0];
    const i = first.indexOf('=');
    if (i <= 0) continue;
    const key = first.slice(0, i).trim();
    if (WANTED.includes(key)) values.set(key, first.slice(i + 1).trim());
  }
  if (rawUrl) {
    try {
      const u = new URL(rawUrl);
      // 不能用 searchParams.get()：它会自动 URL 解码，把 SESSDATA 里的
      // %2C / %2A 还原成逗号 / 星号，Cookie 值就坏了。切原始 query 保留编码。
      for (const pair of u.search.replace(/^\?/, '').split('&')) {
        const i = pair.indexOf('=');
        if (i <= 0) continue;
        const key = decodeURIComponent(pair.slice(0, i));
        if (WANTED.includes(key)) values.set(key, pair.slice(i + 1));
      }
    } catch (_) {
      /* 回调 URL 不是合法 URL 时忽略 */
    }
  }
  if (!values.has('SESSDATA') || !values.has('bili_jct')) return '';
  return [...values.entries()].map(([k, v]) => `${k}=${v}`).join('; ');
}

function stateOf(code) {
  switch (Number(code)) {
    case 86101: return 'waiting';
    case 86090: return 'scanned';
    case 86038:
    case 86039: return 'expired';
    case 0: return 'success';
    default: return 'failed';
  }
}

const MESSAGES = {
  waiting: '请用 B 站 App 扫描二维码',
  scanned: '已扫码，请在手机上点「确认登录」',
  expired: '二维码已失效，请重新生成',
  success: '登录成功',
  failed: '扫码状态异常，请重新生成二维码',
};

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > 16 * 1024) {
        reject(new Error('请求体过大'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      const text = Buffer.concat(chunks).toString('utf8');
      if (!text) return resolve({});
      try {
        resolve(JSON.parse(text));
      } catch (_) {
        reject(new Error('请求体不是合法 JSON'));
      }
    });
    req.on('error', reject);
  });
}

/**
 * 返回 { status?, json }。由 index.js 统一写响应（CORS / no-store 一致）。
 * 响应统一成 { code, message, data }，与客户端 QrLoginApi 的解析约定对齐。
 */
async function handle(req, url) {
  const p = url.pathname.replace(/\/+$/, '');
  const method = req.method || 'GET';
  try {
    if (p === '/api/qr/generate' && method === 'GET') {
      const target = new URL('/x/passport-login/web/qrcode/generate', PASSPORT);
      target.searchParams.set('source', 'main_web');
      const { json } = await getJson(target);
      if (json.code !== 0 || !json.data?.url || !json.data?.qrcode_key) {
        throw new Error(`获取二维码失败：${json.message || `code=${json.code}`}`);
      }
      return {
        json: {
          code: 0,
          message: 'ok',
          data: { url: json.data.url, qrcodeKey: json.data.qrcode_key },
        },
      };
    }

    if (p === '/api/qr/poll' && method === 'GET') {
      const key = url.searchParams.get('key') || '';
      if (!key) return { status: 400, json: { code: 400, message: '缺少 key' } };
      const target = new URL('/x/passport-login/web/qrcode/poll', PASSPORT);
      target.searchParams.set('qrcode_key', key);
      target.searchParams.set('source', 'main_web');
      const { res, json } = await getJson(target);
      const data = json.data || {};
      const state = stateOf(data.code);
      const rawUrl = String(data.url || '');
      return {
        json: {
          code: 0,
          message: 'ok',
          data: {
            state,
            message: String(data.message || MESSAGES[state]),
            cookie: state === 'success' ? buildCookie(setCookies(res), rawUrl) : '',
            url: rawUrl,
          },
        },
      };
    }

    if (p === '/api/qr/nav' && method === 'POST') {
      const body = await readBody(req);
      const cookie = String(body.cookie || '');
      if (!cookie) {
        return { status: 400, json: { code: 400, message: '缺少 cookie' } };
      }
      const target = new URL('/x/web-interface/nav', API);
      const { json } = await getJson(target, { Cookie: cookie });
      if (json.code !== 0) {
        throw new Error(`读取账号资料失败：${json.message || `code=${json.code}`}`);
      }
      const d = json.data || {};
      return {
        json: {
          code: 0,
          message: 'ok',
          data: {
            mid: String(d.mid || ''),
            name: String(d.uname || d.name || ''),
            face: String(d.face || ''),
            vipLabel: Number(d.vipStatus) > 0 ? '大会员' : '',
          },
        },
      };
    }

    return { status: 404, json: { code: 404, message: `未知扫码接口 ${p}` } };
  } catch (err) {
    return {
      status: 502,
      json: { code: 502, message: err.message || '扫码代理上游错误', data: null },
    };
  }
}

module.exports = { handle, buildCookie, stateOf };
