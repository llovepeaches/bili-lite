'use strict';

/**
 * Bili Lite · 官方 OAuth 2.0 接入（BFF 侧，唯一持有 client_secret 的地方）
 * ------------------------------------------------------------------
 * 官方规范（openhome.bilibili.com / open.bilibili.com，2025-03 后授权页已迁移）：
 *
 *   授权页   https://account.bilibili.com/pc/account-pc/auth/oauth
 *            ?client_id=<id>&gourl=<URL-encoded 备案回调域>&state=<防 CSRF 随机串>
 *   换 token POST https://api.bilibili.com/x/account-oauth2/v1/token
 *            ?client_id=&client_secret=&grant_type=authorization_code&code=
 *            Content-Type: application/x-www-form-urlencoded，无 body
 *   续期     POST https://api.bilibili.com/x/account-oauth2/v1/refresh_token
 *            ?client_id=&client_secret=&grant_type=refresh_token&refresh_token=
 *            每个 refresh_token 只能用一次；expires_in 是 UTC 绝对时间戳，不是秒数
 *   用户信息 GET  https://member.bilibili.com/arcopen/fn/user/account/info
 *            Scope USER_INFO，必须带签名 2.0 公共头
 *
 * 设计约束（不可退让）：
 *   1. client_secret 只存在于本进程的环境变量中，绝不写入文件、日志、响应或客户端。
 *   2. code 不落客户端：BFF 收到回调后立即在服务端换 token，再发一次性 ticket。
 *   3. state 一次性 + 5 分钟过期，防 CSRF；ticket 一次性 + 60 秒过期。
 *   4. 不接触密码、Cookie、SESSDATA、bili_jct，不逆向 WBI，不模拟 Web 登录态。
 *   5. token 最终由客户端按用户要求持久化到本地（见 auth_session.dart），
 *      BFF 只在内存里短暂保存待领取的 ticket。
 *
 * 前置条件：开放平台入驻 → 创建应用 → 申请并审核通过 scope → 备案授权回调域。
 * 未配置凭证时 configured=false，App 显示明确的「未配置」状态，绝不伪造登录。
 */

const crypto = require('crypto');
const https = require('https');

const CFG = {
  clientId: (process.env.BILI_CLIENT_ID || '').trim(),
  clientSecret: (process.env.BILI_CLIENT_SECRET || '').trim(),
  redirectUri: (process.env.BILI_REDIRECT_URI || '').trim(),
  scopes: (process.env.BILI_OAUTH_SCOPES || 'USER_INFO')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),
  /** 仅用于本地链路自检：模拟官方授权页与 token 端点，绝不用于生产 */
  sandbox: process.env.BILI_OAUTH_SANDBOX === '1',
};

const AUTHORIZE_HOST = 'account.bilibili.com';
const AUTHORIZE_PATH = '/pc/account-pc/auth/oauth';
const TOKEN_HOST = 'api.bilibili.com';
const TOKEN_PATH = '/x/account-oauth2/v1/token';
const REFRESH_PATH = '/x/account-oauth2/v1/refresh_token';
const OPEN_HOST = 'member.bilibili.com';
const USER_INFO_PATH = '/arcopen/fn/user/account/info';
const USER_SCOPES_PATH = '/arcopen/fn/user/account/scopes';

const STATE_TTL = 5 * 60 * 1000;
const TICKET_TTL = 60 * 1000;

/** state → { platform, createdAt }；一次性 */
const pending = new Map();
/** ticket → { tokens, createdAt }；一次性，只在内存 */
const tickets = new Map();

function now() {
  return Date.now();
}

function rand(bytes) {
  return crypto.randomBytes(bytes).toString('hex');
}

function prune(store, ttl) {
  const cutoff = now() - ttl;
  for (const [key, value] of store) {
    if (value.createdAt < cutoff) store.delete(key);
  }
}

function configured() {
  if (CFG.sandbox) return true;
  return Boolean(CFG.clientId && CFG.clientSecret && CFG.redirectUri);
}

function configView() {
  const ready = configured();
  const missing = [];
  if (!CFG.clientId) missing.push('BILI_CLIENT_ID');
  if (!CFG.clientSecret) missing.push('BILI_CLIENT_SECRET');
  if (!CFG.redirectUri) missing.push('BILI_REDIRECT_URI');
  return {
    configured: ready,
    sandbox: CFG.sandbox,
    clientId: CFG.sandbox ? 'sandbox-app' : CFG.clientId,
    redirectUri: CFG.redirectUri,
    scopes: CFG.scopes,
    // 演示模式不要求真实凭证，missing 清空避免 UI 误报「待配置」
    missing: CFG.sandbox ? [] : missing,
    /** 明确告诉 UI：真实链路必须走官方授权页，不能由客户端自签 */
    authorizeHost: CFG.sandbox ? '' : AUTHORIZE_HOST,
    note: ready
      ? CFG.sandbox
        ? '演示授权已开启：仅用于本地自检，不是 B 站官方授权，请勿用于生产。'
        : '已配置官方开放平台凭证，授权将在 B 站官方页面完成。'
      : '未配置官方开放平台凭证，登录入口已停用。',
  };
}

/* ------------------------------------------------------------------ */
/* 官方签名 2.0                                                        */
/* ------------------------------------------------------------------ */

/**
 * canonical string 由 6 个 x-bili-* 公共头按 ASCII 字典序组成，
 * 每行 "key:value"，用 \n 连接，无尾随换行；密钥为 app_secret(client_secret)。
 * 该拼接规则已用 B 站官方公开签名样例验证：
 *   k5imtTt9JOI8o3ifp1bbbfIYOXP1iC + 样例 6 行
 *   → 0f0aed7b7e0a7b1283a2318805b0b05a4ef2918feb60828575ed2e554be0eccd
 * 见 tool/verify_oauth_sign.js。
 */
function buildCanonical(parts) {
  const pairs = [
    ['x-bili-accesskeyid', parts.accessKeyId],
    ['x-bili-content-md5', parts.contentMd5],
    ['x-bili-signature-method', 'HMAC-SHA256'],
    ['x-bili-signature-nonce', parts.nonce],
    ['x-bili-signature-version', parts.version || '2.0'],
    ['x-bili-timestamp', parts.timestamp],
  ];
  return pairs.map(([k, v]) => `${k}:${v}`).join('\n');
}

function signatureFor(secret, canonical) {
  return crypto.createHmac('sha256', secret).update(canonical).digest('hex');
}

/** 供自检脚本复用：给定输入直接算出 Authorization，不读环境变量 */
function signCanonical(secret, accessKeyId, contentMd5, nonce, timestamp, version) {
  return signatureFor(
    secret,
    buildCanonical({ accessKeyId, contentMd5, nonce, timestamp, version })
  );
}

function signedHeaders(accessToken, body) {
  const payload = body || '';
  const contentMd5 = crypto.createHash('md5').update(payload).digest('hex');
  const timestamp = String(Math.floor(now() / 1000));
  const nonce = rand(12);
  const canonical = buildCanonical({
    accessKeyId: CFG.clientId,
    contentMd5,
    nonce,
    timestamp,
  });
  const authorization = signatureFor(CFG.clientSecret, canonical);
  return {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'access-token': accessToken,
    'x-bili-accesskeyid': CFG.clientId,
    'x-bili-content-md5': contentMd5,
    'x-bili-signature-method': 'HMAC-SHA256',
    'x-bili-signature-nonce': nonce,
    'x-bili-signature-version': '2.0',
    'x-bili-timestamp': timestamp,
    Authorization: authorization,
  };
}

/* ------------------------------------------------------------------ */
/* 零依赖 HTTPS 请求                                                   */
/* ------------------------------------------------------------------ */

function requestJson(host, pathWithQuery, options = {}) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        host,
        path: pathWithQuery,
        method: options.method || 'GET',
        headers: Object.assign(
          {
            'User-Agent': 'BiliLite/1.2.0 (+official-oauth-client)',
            Accept: 'application/json',
          },
          options.headers || {}
        ),
        timeout: 12000,
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let json;
          try {
            json = JSON.parse(text);
          } catch (_) {
            reject(new Error(`上游返回非 JSON（HTTP ${res.statusCode}）`));
            return;
          }
          resolve({ status: res.statusCode, body: json });
        });
      }
    );
    req.on('timeout', () => req.destroy(new Error('请求上游超时')));
    req.on('error', reject);
    if (options.body) req.write(options.body);
    req.end();
  });
}

function assertOfficial(body, fallbackMessage) {
  if (!body || body.code !== 0) {
    const code = body && body.code !== undefined ? body.code : '?';
    const message = (body && body.message) || fallbackMessage;
    throw new Error(`B 站开放平台返回 code=${code}: ${message}`);
  }
  return body.data || {};
}

/* ------------------------------------------------------------------ */
/* 授权流程                                                            */
/* ------------------------------------------------------------------ */

/**
 * 构造官方授权页 URL。gourl 必须与开放平台备案的回调域一致，且需要 URL encode。
 * state 一次性存于服务端；platform 只影响回调页呈现，不写进 gourl（避免破坏备案匹配）。
 */
function begin(platform, localBase) {
  if (!configured()) {
    return { error: 'NOT_CONFIGURED', config: configView() };
  }
  prune(pending, STATE_TTL);
  const state = rand(24);
  pending.set(state, { platform: platform === 'web' ? 'web' : 'native', createdAt: now() });

  const gourl = CFG.sandbox
    ? `${localBase}/api/oauth/callback`
    : CFG.redirectUri;

  const authorizeUrl = CFG.sandbox
    ? `${localBase}/api/oauth/sandbox/authorize?client_id=sandbox-app` +
      `&gourl=${encodeURIComponent(gourl)}&state=${encodeURIComponent(state)}`
    : `https://${AUTHORIZE_HOST}${AUTHORIZE_PATH}` +
      `?client_id=${encodeURIComponent(CFG.clientId)}` +
      `&gourl=${encodeURIComponent(gourl)}` +
      `&state=${encodeURIComponent(state)}`;

  return {
    data: {
      state,
      authorizeUrl,
      expiresAt: now() + STATE_TTL,
      redirectUri: gourl,
      scopes: CFG.scopes,
      sandbox: CFG.sandbox,
    },
    config: configView(),
  };
}

async function exchangeCode(code) {
  if (CFG.sandbox) {
    // 演示模式：不请求 B 站，token 带 sandbox_ 前缀，任何真实接口都不会接受
    return {
      access_token: `sandbox_at_${rand(16)}`,
      refresh_token: `sandbox_rt_${rand(16)}`,
      expires_in: Math.floor(now() / 1000) + 7200,
      scopes: CFG.scopes,
    };
  }
  const query = new URLSearchParams({
    client_id: CFG.clientId,
    client_secret: CFG.clientSecret,
    grant_type: 'authorization_code',
    code,
  });
  const res = await requestJson(TOKEN_HOST, `${TOKEN_PATH}?${query}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  });
  return assertOfficial(res.body, '换取 access_token 失败');
}

async function refreshToken(refresh) {
  if (CFG.sandbox) {
    if (!String(refresh || '').startsWith('sandbox_rt_')) {
      throw new Error('演示模式的 refresh_token 无效');
    }
    return {
      access_token: `sandbox_at_${rand(16)}`,
      refresh_token: `sandbox_rt_${rand(16)}`,
      expires_in: Math.floor(now() / 1000) + 7200,
    };
  }
  const query = new URLSearchParams({
    client_id: CFG.clientId,
    client_secret: CFG.clientSecret,
    grant_type: 'refresh_token',
    refresh_token: refresh,
  });
  const res = await requestJson(TOKEN_HOST, `${REFRESH_PATH}?${query}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  });
  return assertOfficial(res.body, '续期 access_token 失败');
}

function normalizeTokens(raw, previous) {
  const expiresIn = Number(raw.expires_in) || 0;
  // 官方 expires_in 是 UTC 绝对时间戳（秒），不是「还有多少秒过期」。
  // 依次兼容：毫秒绝对时间戳 / 秒绝对时间戳（官方）/ 相对秒数（少数实现）。
  const expiresAt = expiresIn > 1e12
    ? expiresIn
    : expiresIn > 1e9
        ? expiresIn * 1000
        : now() + expiresIn * 1000;
  return {
    accessToken: String(raw.access_token || ''),
    refreshToken: String(raw.refresh_token || (previous && previous.refreshToken) || ''),
    expiresAt,
    scopes: Array.isArray(raw.scopes)
      ? raw.scopes.map(String)
      : (previous && previous.scopes) || [],
  };
}

/** 官方回调：校验 state → 换 token → 生成一次性 ticket → 引导回 App */
async function callback(query, localBase) {
  const state = query.get('state') || '';
  const code = query.get('code') || '';
  const error = query.get('error') || '';
  const record = pending.get(state);
  pending.delete(state);

  if (error) {
    return { html: resultPage('授权未完成', `官方授权页返回：${escapeHtml(error)}`, null, localBase) };
  }
  if (!record || record.createdAt < now() - STATE_TTL) {
    return { html: resultPage('授权已失效', 'state 校验失败或已过期，请回到应用重新发起登录。', null, localBase) };
  }
  if (!code) {
    return { html: resultPage('授权未完成', '回调缺少 code 参数。', null, localBase) };
  }

  try {
    const raw = await exchangeCode(code);
    const tokens = normalizeTokens(raw, null);
    prune(tickets, TICKET_TTL);
    const ticket = rand(24);
    tickets.set(ticket, { tokens, createdAt: now() });

    // Web：直接带 ticket 回 App；原生：展示一次性码 + 深链，供粘贴或跳回
    if (record.platform === 'web') {
      return { redirect: `/?oauth_ticket=${ticket}` };
    }
    return {
      html: resultPage(
        '授权成功',
        '请回到 Bili Lite，粘贴下面的一次性授权码完成登录。该码 60 秒内有效，且只能使用一次。',
        ticket,
        localBase
      ),
    };
  } catch (err) {
    return { html: resultPage('换取凭证失败', escapeHtml(err.message), null, localBase) };
  }
}

/** 用一次性 ticket 领取 token。领取后立刻删除，不留存服务端会话。 */
function claim(ticket) {
  const record = tickets.get(String(ticket || ''));
  if (!record) return { error: 'ticket 无效或已被使用' };
  tickets.delete(String(ticket));
  if (record.createdAt < now() - TICKET_TTL) {
    return { error: 'ticket 已过期，请重新登录' };
  }
  return { data: record.tokens };
}

/** 用 access_token + 官方签名 2.0 调用 USER_INFO，获取昵称 / 头像 / openid */
async function userInfo(accessToken) {
  if (CFG.sandbox) {
    return {
      openid: 'sandbox-openid-0001',
      name: '演示账号（非 B 站真实用户）',
      face: '',
      scopes: CFG.scopes,
      sandbox: true,
    };
  }
  if (!CFG.clientId || !CFG.clientSecret) {
    throw new Error('未配置开放平台凭证');
  }
  const headers = signedHeaders(accessToken, '');
  const res = await requestJson(OPEN_HOST, USER_INFO_PATH, { headers });
  const data = assertOfficial(res.body, '获取用户信息失败');
  return {
    openid: String(data.openid || data.mid || ''),
    name: String(data.name || data.uname || ''),
    face: String(data.face || ''),
    scopes: Array.isArray(data.scopes) ? data.scopes.map(String) : CFG.scopes,
    sandbox: false,
  };
}

async function authorizedScopes(accessToken) {
  if (CFG.sandbox) return { scopes: CFG.scopes };
  const headers = signedHeaders(accessToken, '');
  const res = await requestJson(OPEN_HOST, USER_SCOPES_PATH, { headers });
  const data = assertOfficial(res.body, '查询已授权权限失败');
  return { scopes: Array.isArray(data.scopes) ? data.scopes.map(String) : [] };
}

/** 本地自检用的模拟授权页：协议与官方一致（client_id / gourl / state → code） */
function sandboxAuthorize(query) {
  const gourl = query.get('gourl') || '';
  const state = query.get('state') || '';
  if (!pending.has(state)) {
    return '<h1>演示授权</h1><p>state 无效或已过期，请回到应用重新发起。</p>';
  }
  // 只允许回调到本服务，避免被用作开放重定向
  let safe = '/api/oauth/callback';
  try {
    const u = new URL(gourl);
    safe = u.pathname + u.search;
  } catch (_) {
    /* 保持默认 */
  }
  const code = `sandbox_code_${rand(16)}`;
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>演示授权（非 B 站官方）</title>
<style>body{font-family:system-ui,-apple-system,"PingFang SC",sans-serif;background:#f6f7fb;color:#1b1c22;
display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.box{background:#fff;border-radius:20px;padding:32px;max-width:420px;width:calc(100% - 40px);
box-shadow:0 18px 50px rgba(20,22,40,.12)}
.tag{display:inline-block;background:#fff0e6;color:#c2601a;border-radius:999px;padding:4px 10px;font-size:12px;font-weight:600}
h1{font-size:20px;margin:14px 0 8px}p{font-size:13px;line-height:1.7;color:#62636b}
button{margin-top:18px;width:100%;border:0;border-radius:12px;padding:13px;font-size:15px;font-weight:600;
color:#fff;background:#fb7299;cursor:pointer}small{display:block;margin-top:14px;color:#9a9ba3;font-size:11px}
</style></head><body><div class="box">
<span class="tag">演示授权 · 非 B 站官方</span>
<h1>同意授权 Bili Lite？</h1>
<p>这是<strong>本地自检用的模拟授权页</strong>，用于验证「授权码 → 换取 token → 本地持久化 → 续期 → 退出登录」全链路。
它不会连接 B 站，也不会产生真实账号凭证。生产环境请关闭 <code>BILI_OAUTH_SANDBOX</code> 并配置真实开放平台凭证。</p>
<p>申请的权限：<strong>${escapeHtml(CFG.scopes.join(', '))}</strong></p>
<form method="get" action="${escapeHtml(safe)}">
<input type="hidden" name="code" value="${code}">
<input type="hidden" name="state" value="${escapeHtml(state)}">
<button type="submit">同意授权</button></form>
<small>state=${escapeHtml(state.slice(0, 16))}… · 一次性</small>
</div></body></html>`;
}

/* ------------------------------------------------------------------ */
/* 回调结果页                                                          */
/* ------------------------------------------------------------------ */

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function resultPage(title, message, ticket, localBase) {
  const codeBlock = ticket
    ? `<div class="code" id="code">${escapeHtml(ticket)}</div>
       <button id="copy">复制一次性授权码</button>
       <a class="link" href="bililite://oauth?ticket=${encodeURIComponent(ticket)}">返回 Bili Lite</a>
       <p>也可以回到应用，在「B 站账号」卡片里点「粘贴授权码」。</p>`
    : `<a class="link" href="/">返回应用</a>`;
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title>
<style>body{font-family:system-ui,-apple-system,"PingFang SC",sans-serif;background:#f6f7fb;color:#1b1c22;
display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.box{background:#fff;border-radius:20px;padding:32px;max-width:440px;width:calc(100% - 40px);
box-shadow:0 18px 50px rgba(20,22,40,.12);text-align:center}
h1{font-size:20px;margin:0 0 10px}p{font-size:13px;line-height:1.75;color:#62636b}
.code{margin:18px 0;padding:14px;background:#f4f5fa;border-radius:12px;font-family:ui-monospace,monospace;
font-size:13px;word-break:break-all;user-select:all}
button,.link{display:block;margin-top:10px;width:100%;box-sizing:border-box;border:0;border-radius:12px;
padding:12px;font-size:14px;font-weight:600;text-decoration:none;cursor:pointer}
button{color:#fff;background:#fb7299}.link{color:#fb7299;background:#fff0f5}
small{display:block;margin-top:16px;color:#9a9ba3;font-size:11px}</style></head>
<body><div class="box"><h1>${escapeHtml(title)}</h1><p>${message}</p>${codeBlock}
<small>Bili Lite · 官方 OAuth 2.0 授权码流程 · ${escapeHtml(localBase)}</small></div>
<script>var b=document.getElementById('copy');if(b){b.onclick=function(){navigator.clipboard.writeText(
document.getElementById('code').textContent).then(function(){b.textContent='已复制'})}}</script>
</body></html>`;
}

/* ------------------------------------------------------------------ */
/* 路由分发                                                            */
/* ------------------------------------------------------------------ */

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
 * 返回 { status, json } 或 { html } 或 { redirect }。
 * 由 index.js 统一写响应，保证 CORS / no-store 一致。
 */
async function handle(req, url, localBase) {
  const p = url.pathname.replace(/\/+$/, '');
  const method = req.method || 'GET';

  try {
    if (p === '/api/oauth/config' && method === 'GET') {
      return { json: { code: 0, message: 'ok', data: configView() } };
    }

    if (p === '/api/oauth/begin' && method === 'POST') {
      const body = await readBody(req);
      const out = begin(body.platform, localBase);
      if (out.error) {
        return {
          status: 503,
          json: {
            code: 503,
            message: '尚未配置官方开放平台凭证',
            data: out.config,
          },
        };
      }
      return { json: { code: 0, message: 'ok', data: out.data } };
    }

    if (p === '/api/oauth/sandbox/authorize' && method === 'GET') {
      if (!CFG.sandbox) {
        return { status: 404, json: { code: 404, message: '演示授权未开启' } };
      }
      return { html: sandboxAuthorize(url.searchParams) };
    }

    if (p === '/api/oauth/callback' && method === 'GET') {
      return await callback(url.searchParams, localBase);
    }

    if (p === '/api/oauth/exchange' && method === 'POST') {
      const body = await readBody(req);
      const out = claim(body.ticket);
      if (out.error) {
        return { status: 400, json: { code: 400, message: out.error, data: null } };
      }
      return { json: { code: 0, message: 'ok', data: out.data } };
    }

    if (p === '/api/oauth/refresh' && method === 'POST') {
      const body = await readBody(req);
      if (!body.refreshToken) {
        return { status: 400, json: { code: 400, message: '缺少 refreshToken' } };
      }
      const raw = await refreshToken(String(body.refreshToken));
      const data = normalizeTokens(raw, {
        refreshToken: String(body.refreshToken),
        scopes: Array.isArray(body.scopes) ? body.scopes.map(String) : [],
      });
      return { json: { code: 0, message: 'ok', data } };
    }

    if (p === '/api/oauth/me' && method === 'POST') {
      const body = await readBody(req);
      if (!body.accessToken) {
        return { status: 400, json: { code: 400, message: '缺少 accessToken' } };
      }
      const data = await userInfo(String(body.accessToken));
      return { json: { code: 0, message: 'ok', data } };
    }

    if (p === '/api/oauth/scopes' && method === 'POST') {
      const body = await readBody(req);
      if (!body.accessToken) {
        return { status: 400, json: { code: 400, message: '缺少 accessToken' } };
      }
      const data = await authorizedScopes(String(body.accessToken));
      return { json: { code: 0, message: 'ok', data } };
    }

    return { status: 404, json: { code: 404, message: `未知 OAuth 接口 ${p}` } };
  } catch (err) {
    return {
      status: 502,
      json: { code: 502, message: err.message || 'OAuth 上游错误', data: null },
    };
  }
}

module.exports = {
  CFG,
  configView,
  configured,
  signCanonical,
  buildCanonical,
  signatureFor,
  handle,
  // 供自检脚本使用
  _pending: pending,
  _tickets: tickets,
};
