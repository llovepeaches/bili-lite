'use strict';

/**
 * 官方 OAuth 2.0 授权码链路端到端自检（零第三方依赖）
 * ------------------------------------------------------------------
 * 起两个独立的 BFF 进程：
 *   A. BILI_OAUTH_SANDBOX=1 —— 走完整授权码 → ticket → token → 刷新 → 用户信息链路，
 *      并验证 state / ticket 一次性、防重放、secret 不出现在任何响应里。
 *   B. 无凭证 —— 验证「未配置」时不伪造登录，begin 返回 503 且列出缺失项。
 *
 * 演示模式不连接 B 站，不产生真实凭证；生产链路的代码路径与之相同，
 * 只是把授权页与 token 端点换成官方域名（见 src/oauth.js）。
 */

const { spawn } = require('child_process');
const http = require('http');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SECRET_CANARY = 'DO_NOT_LEAK_TEST_SECRET_123';

let passed = 0;
let failed = 0;
const responses = [];

function check(name, condition, detail) {
  if (condition) {
    passed += 1;
    console.log(`  ✓ ${name}`);
  } else {
    failed += 1;
    console.log(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`);
  }
}

function request(port, method, pathname, body) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : JSON.stringify(body);
    const req = http.request(
      {
        host: '127.0.0.1',
        port,
        path: pathname,
        method,
        headers: payload
          ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }
          : {},
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          responses.push(text);
          let json = null;
          try {
            json = JSON.parse(text);
          } catch (_) {
            /* HTML 或 302 空体 */
          }
          resolve({ status: res.statusCode, headers: res.headers, text, json });
        });
      }
    );
    req.on('error', reject);
    req.setTimeout(10000, () => req.destroy(new Error('请求超时')));
    if (payload) req.write(payload);
    req.end();
  });
}

function start(port, extraEnv) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['src/index.js'], {
      cwd: ROOT,
      env: Object.assign({}, process.env, {
        PORT: String(port),
        HOST: '127.0.0.1',
        MOCK_MODE: '1',
        BILI_OAUTH_SANDBOX: '0',
        BILI_CLIENT_ID: '',
        BILI_CLIENT_SECRET: '',
        BILI_REDIRECT_URI: '',
        PUBLIC_BASE_URL: `http://127.0.0.1:${port}`,
      }, extraEnv || {}),
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let log = '';
    child.stdout.on('data', (d) => { log += d.toString(); });
    child.stderr.on('data', (d) => { log += d.toString(); });
    child.on('error', reject);

    const deadline = Date.now() + 20000;
    const poll = async () => {
      try {
        const r = await request(port, 'GET', '/api/health');
        if (r.status === 200) return resolve({ child, log: () => log });
      } catch (_) {
        /* 还没起来 */
      }
      if (Date.now() > deadline) {
        child.kill('SIGTERM');
        return reject(new Error(`BFF 启动超时（端口 ${port}）\n${log}`));
      }
      setTimeout(poll, 200);
    };
    poll();
  });
}

function stop(server) {
  return new Promise((resolve) => {
    if (!server || !server.child || server.child.killed) return resolve();
    server.child.once('exit', resolve);
    server.child.kill('SIGTERM');
    setTimeout(resolve, 2000);
  });
}

async function sandboxFlow() {
  console.log('\n[A] 演示授权模式 · 完整授权码链路');
  console.log('──────────────────────────────────────────────');
  const port = 8799;
  const server = await start(port, {
    BILI_OAUTH_SANDBOX: '1',
    // 故意注入一个假 secret，用来验证它绝不会出现在任何响应里
    BILI_CLIENT_SECRET: SECRET_CANARY,
    BILI_CLIENT_ID: 'sandbox-canary-client',
    BILI_REDIRECT_URI: `http://127.0.0.1:${port}/api/oauth/callback`,
  });

  try {
    const cfg = await request(port, 'GET', '/api/oauth/config');
    check('config 返回 configured=true', cfg.json && cfg.json.data.configured === true);
    check('config 标注 sandbox=true', cfg.json && cfg.json.data.sandbox === true);
    check('config 返回 scope 列表', Array.isArray(cfg.json.data.scopes) && cfg.json.data.scopes.length > 0);
    check('config 不返回 clientSecret 字段',
      cfg.json && !Object.prototype.hasOwnProperty.call(cfg.json.data, 'clientSecret'));

    const begun = await request(port, 'POST', '/api/oauth/begin', { platform: 'web' });
    const beginData = begun.json && begun.json.data;
    check('begin 返回 authorizeUrl', begun.status === 200 && !!beginData.authorizeUrl);
    check('begin 返回一次性 state', !!beginData.state && beginData.state.length >= 32);
    check('演示授权页指向本服务而非 B 站',
      beginData.authorizeUrl.includes(`127.0.0.1:${port}`) &&
      !beginData.authorizeUrl.includes('bilibili.com'));

    // 打开演示授权页，解析出 code（等价于官方授权页同意后的回调）
    const authPath = new URL(beginData.authorizeUrl).pathname +
      new URL(beginData.authorizeUrl).search;
    const page = await request(port, 'GET', authPath);
    check('演示授权页明确标注「非 B 站官方」', page.text.includes('非 B 站官方'));
    const codeMatch = page.text.match(/name="code" value="([^"]+)"/);
    check('演示授权页携带 code', !!codeMatch);

    const state = beginData.state;
    const cb = await request(
      port, 'GET',
      `/api/oauth/callback?code=${encodeURIComponent(codeMatch[1])}&state=${encodeURIComponent(state)}`
    );
    check('官方回调返回 302 回 App', cb.status === 302);
    const ticketMatch = (cb.headers.location || '').match(/oauth_ticket=([a-f0-9]+)/);
    check('302 携带一次性 ticket', !!ticketMatch);
    const ticket = ticketMatch && ticketMatch[1];

    const exchanged = await request(port, 'POST', '/api/oauth/exchange', { ticket });
    const tokens = exchanged.json && exchanged.json.data;
    check('exchange 返回 accessToken', !!tokens && !!tokens.accessToken);
    check('exchange 返回 refreshToken', !!tokens && !!tokens.refreshToken);
    check('expiresAt 是绝对毫秒时间戳', !!tokens && tokens.expiresAt > 1e12);
    check(
      'expiresAt 落在约 2 小时后（正确解析官方秒级 UTC 时间戳）',
      !!tokens &&
        tokens.expiresAt > Date.now() &&
        tokens.expiresAt < Date.now() + 3 * 3600 * 1000
    );
    check('exchange 不返回 client_secret', !exchanged.text.includes(SECRET_CANARY));

    const replay = await request(port, 'POST', '/api/oauth/exchange', { ticket });
    check('ticket 二次使用被拒绝', replay.status === 400);

    const badState = await request(
      port, 'GET', `/api/oauth/callback?code=x&state=${encodeURIComponent(state)}`
    );
    check('state 重放被拒绝', badState.text.includes('授权已失效'));

    const refreshed = await request(port, 'POST', '/api/oauth/refresh', {
      refreshToken: tokens.refreshToken,
      scopes: tokens.scopes,
    });
    check('refresh 返回新的 accessToken',
      refreshed.status === 200 &&
      !!refreshed.json.data.accessToken &&
      refreshed.json.data.accessToken !== tokens.accessToken);
    check('refresh 轮换 refreshToken',
      refreshed.json.data.refreshToken !== tokens.refreshToken);

    const me = await request(port, 'POST', '/api/oauth/me', {
      accessToken: tokens.accessToken,
    });
    check('me 返回用户信息（USER_INFO）',
      me.status === 200 && !!me.json.data.openid && !!me.json.data.name);
    check('me 标注 sandbox', me.json.data.sandbox === true);

    const health = await request(port, 'GET', '/api/health');
    check('health 暴露 oauth 状态但不含密钥',
      health.json.data.oauth.configured === true &&
      !health.text.includes(SECRET_CANARY));

    check('全程响应未泄漏 client_secret',
      responses.every((r) => !r.includes(SECRET_CANARY)));
  } finally {
    await stop(server);
  }
}

async function unconfiguredFlow() {
  console.log('\n[B] 未配置官方凭证 · 不得伪造登录');
  console.log('──────────────────────────────────────────────');
  const port = 8800;
  const server = await start(port, {});
  try {
    const cfg = await request(port, 'GET', '/api/oauth/config');
    check('config 返回 configured=false', cfg.json.data.configured === false);
    check('config 列出缺失的环境变量',
      Array.isArray(cfg.json.data.missing) && cfg.json.data.missing.length === 3);
    check('config 不暴露任何 secret 值', !cfg.text.includes('secret='));

    const begun = await request(port, 'POST', '/api/oauth/begin', { platform: 'web' });
    check('begin 返回 503 而非伪造授权页', begun.status === 503);
    check('begin 不返回 authorizeUrl',
      !begun.json.data || !begun.json.data.authorizeUrl);

    const cb = await request(port, 'GET', '/api/oauth/callback?code=fake&state=fake');
    check('伪造回调被拒绝', cb.text.includes('授权已失效'));
  } finally {
    await stop(server);
  }
}

(async () => {
  try {
    await sandboxFlow();
    await unconfiguredFlow();
  } catch (err) {
    failed += 1;
    console.error('\n自检异常：', err.message);
  }
  console.log('\n──────────────────────────────────────────────');
  console.log(`结果：${passed} 通过 / ${failed} 失败\n`);
  process.exit(failed ? 1 : 0);
})();
