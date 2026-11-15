'use strict';

/**
 * B 站 Web 登录（账号密码 / 短信验证码）的 **Web 端同源代理**。
 *
 * 为什么需要它：与扫码登录的 `/api/qr/*` 完全同一个理由——浏览器里
 * passport.bilibili.com 不给第三方站点下发 CORS 头，原生端可以直连，
 * Web 端只能由同源 BFF 转发。原生端（Android / iOS / 桌面）不走这里。
 *
 * 与 qr_proxy 的两个关键差异：
 *   1. **业务码必须原样透传**。扫码轮询的业务码藏在 data.code 里，所以
 *      qr_proxy 统一包成 code=0；密码 / 短信登录的业务码就在顶层
 *      （-105 人机验证、-629 密码错误、2406 短信验证码错误……），
 *      客户端 PassportApi 靠它决定提示文案和「需要人机验证」标记。
 *      一律包成 0 会让客户端永远看不到验证要求，进而误报登录结果。
 *   2. 成功时把 Set-Cookie + data.url 合成好的 Cookie 放进 data.cookie，
 *      与原生端 QrLoginApi.buildCookie 的产物对齐，上层只认这一个字段。
 *
 * 边界（与 qr_proxy 一致，必须严守）：
 *   * 服务端只做协议转发，**不落盘、不缓存、不打印**任何登录 Cookie；
 *   * 请求体里含 RSA 加密后的密码，**不写日志、不进任何持久化结构**；
 *   * 上游的 validate / seccode 由浏览器里极验 JS 产生，代理不伪造、不补全；
 *   * 登录 Cookie 最终只保存在用户浏览器 localStorage（见 qr_session.dart）。
 *
 * 注意：Cookie 登录本身不需要代理——它由 QrLoginApi.profile() 走现成的
 * `/api/qr/nav` 校验，校验通过后才写入本机。
 */

const { buildCookie } = require('./qr_proxy');

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const REFERER = 'https://www.bilibili.com/';
const PASSPORT = 'https://passport.bilibili.com';
const TIMEOUT = 12000;

/** 允许转发的表单字段白名单：杜绝把任意字段打到 B 站登录域。 */
const ALLOWED_FIELDS = [
  'source',
  'username',
  'password',
  'keep',
  'token',
  'challenge',
  'validate',
  'seccode',
  'tel',
  'cid',
  'code',
  'captcha_key',
];

/** POST 路由 → 上游路径。 */
const POST_ROUTES = {
  '/api/passport/password': '/x/passport-login/web/login',
  '/api/passport/sms/send': '/x/passport-login/web/sms/send',
  '/api/passport/sms/login': '/x/passport-login/web/login/sms',
};

function headers(extra = {}) {
  return {
    'User-Agent': UA,
    Referer: REFERER,
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    ...extra,
  };
}

/** Set-Cookie 可能有多段，Node 22 的 Headers.getSetCookie() 能正确拆开。 */
function setCookies(res) {
  if (typeof res.headers.getSetCookie === 'function') {
    return res.headers.getSetCookie();
  }
  const raw = res.headers.get('set-cookie');
  return raw ? [raw] : [];
}

async function parseUpstream(res, what) {
  const text = await res.text();
  if (!text.trim().startsWith('{')) {
    throw new Error(`${what} 上游返回非 JSON（HTTP ${res.status}），疑似风控`);
  }
  let json;
  try {
    json = JSON.parse(text);
  } catch (_) {
    throw new Error(`${what} 上游返回内容无法解析`);
  }
  return { res, json };
}

async function getJson(target, what) {
  // 必须先 await fetch：parseUpstream 拿的是 Response，不是 Promise，
  // 否则 res.text() 会抛 "is not a function"，代理一律降级成 502。
  const res = await fetch(target, {
    headers: headers(),
    signal: AbortSignal.timeout(TIMEOUT),
  });
  return parseUpstream(res, what);
}

async function postForm(target, form, what) {
  // URLSearchParams 会把 base64 密码里的 '+' 编成 %2B、'/' 编成 %2F，
  // 直接字符串拼接会破坏密文。这里必须走标准编码。
  const res = await fetch(target, {
    method: 'POST',
    headers: headers({
      'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
    }),
    body: new URLSearchParams(form).toString(),
    signal: AbortSignal.timeout(TIMEOUT),
  });
  return parseUpstream(res, what);
}

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

function reply(code, message, data = {}) {
  return { json: { code, message: String(message || ''), data } };
}

/**
 * 返回 { status?, json }，由 index.js 统一写响应（CORS / no-store 一致）。
 * 响应形状恒为 { code, message, data }，与客户端 PassportApi._decode 对齐。
 */
async function handle(req, url) {
  const p = url.pathname.replace(/\/+$/, '');
  const method = req.method || 'GET';
  try {
    if (p === '/api/passport/key' && method === 'GET') {
      const { json } = await getJson(
        new URL('/x/passport-login/web/key', PASSPORT),
        '获取登录密钥'
      );
      const d = json.data || {};
      return reply(Number(json.code ?? -1), json.message, {
        hash: String(d.hash || ''),
        key: String(d.key || ''),
      });
    }

    if (p === '/api/passport/captcha' && method === 'GET') {
      const target = new URL('/x/passport-login/captcha', PASSPORT);
      target.searchParams.set('source', 'main_web');
      target.searchParams.set('t', (Date.now() / 1000).toFixed(3));
      const { json } = await getJson(target, '获取人机验证参数');
      const d = json.data || {};
      const g = d.geetest || {};
      return reply(Number(json.code ?? -1), json.message, {
        type: String(d.type || ''),
        token: String(d.token || ''),
        geetest: {
          gt: String(g.gt || ''),
          challenge: String(g.challenge || ''),
        },
      });
    }

    if (POST_ROUTES[p] && method === 'POST') {
      const body = await readBody(req);
      const form = {};
      for (const key of ALLOWED_FIELDS) {
        const v = body[key];
        if (v === undefined || v === null || v === '') continue;
        form[key] = String(v);
      }
      const { res, json } = await postForm(
        new URL(POST_ROUTES[p], PASSPORT),
        form,
        '提交登录请求'
      );
      const d = json.data || {};
      const code = Number(json.code ?? -1);
      // 只回传客户端真正需要的字段，不把含 Cookie 的回调 URL 整串吐回去。
      const data = {};
      if (d.captcha_key) data.captcha_key = String(d.captcha_key);
      if (code === 0) {
        data.cookie = buildCookie(setCookies(res), String(d.url || ''));
      }
      return reply(code, json.message, data);
    }

    return {
      status: 404,
      json: { code: 404, message: `未知登录接口 ${p}`, data: {} },
    };
  } catch (err) {
    return {
      status: 502,
      json: {
        code: 502,
        message: err.message || '登录代理上游错误',
        data: {},
      },
    };
  }
}

module.exports = { handle, POST_ROUTES, ALLOWED_FIELDS };
