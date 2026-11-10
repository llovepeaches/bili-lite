// 官方 OAuth 2.0 Web 端到端验收
//   NODE_PATH=$(npm root -g) node tool/verify_oauth_web.cjs
//
// 覆盖：授权页跳转 → 同意授权 → 回调 → 领取 token → 本地持久化 →
//       刷新恢复 → 退出登录清除 → 控制台零错误。
// 前提：BFF 以 BILI_OAUTH_SANDBOX=1 启动（本地自检演示授权，UI 会醒目标注）。
// 真实开放平台凭证模式下，除授权页域名为 account.bilibili.com 外，链路完全一致。
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.APP_URL || 'http://127.0.0.1:8787';
const OUT = path.resolve(__dirname, '../../docs/preview');

const C = {
  settingsNav: [90, 270],
  loginButton: [326, 568],
  logoutButton: [525, 614],
  confirmLogout: [1165, 512],
};

let passed = 0;
let failed = 0;

function check(name, condition, detail) {
  if (condition) {
    passed += 1;
    console.log(`  ✓ ${name}`);
  } else {
    failed += 1;
    console.log(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`);
  }
}

const KEYS = [
  'flutter.bili_lite_oauth_access_token',
  'flutter.bili_lite_oauth_refresh_token',
  'flutter.bili_lite_oauth_expires_at',
  'flutter.bili_lite_oauth_scopes',
  'flutter.bili_lite_oauth_user',
];

async function storage(page) {
  return page.evaluate(() => {
    const out = {};
    for (let i = 0; i < localStorage.length; i += 1) {
      const k = localStorage.key(i);
      out[k] = localStorage.getItem(k);
    }
    return out;
  });
}

async function openSettings(page) {
  await page.mouse.click(...C.settingsNav);
  await page.waitForTimeout(1200);
  await page.mouse.move(800, 500);
  await page.mouse.wheel(0, 700);
  await page.waitForTimeout(900);
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const oauthCalls = [];
  const errors = [];

  page.on('request', (req) => {
    if (req.url().includes('/api/oauth/')) {
      oauthCalls.push(new URL(req.url()).pathname);
    }
  });
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });

  console.log('\n官方 OAuth 2.0 · Web 端到端验收');
  console.log('──────────────────────────────────────────────');

  // 1. 首页 + 设置页账号卡片
  await page.goto(BASE, { waitUntil: 'commit', timeout: 30000 });
  await page.waitForTimeout(9000);
  await openSettings(page);
  await page.screenshot({ path: path.join(OUT, '15-oauth-signedout.png') });
  check('首页与设置页加载完成', (await page.title()).length > 0);

  // 2. 发起授权 → 同页导航到授权页
  await page.mouse.click(...C.loginButton);
  await page.waitForTimeout(2000);
  const consentText = await page.evaluate(() => document.body.innerText || '');
  check('跳转到授权页', page.url().includes('/api/oauth/sandbox/authorize'));
  check('授权页醒目标注「非 B 站官方」（演示模式）',
    consentText.includes('非 B 站官方'));
  check('授权页列出申请的 scope', consentText.includes('USER_INFO'));
  check('授权页不含 client_secret', !consentText.includes('client_secret='));
  await page.screenshot({ path: path.join(OUT, '16-oauth-consent.png') });

  // 3. 同意授权 → 回调 → App 自动领取凭证
  await page.click('button[type=submit]');
  await page.waitForFunction(
    () => !!localStorage.getItem('flutter.bili_lite_oauth_access_token'),
    null,
    { timeout: 30000 }
  );
  await page.waitForTimeout(2500);
  const afterLogin = await storage(page);
  check('回调后回到 App', page.url().includes('127.0.0.1:8787') ||
    page.url().includes('localhost:8787'));
  check('本机写入全部 5 项凭证/资料',
    KEYS.every((k) => Object.prototype.hasOwnProperty.call(afterLogin, k)));
  check('access_token 已本地持久化',
    String(afterLogin[KEYS[0]] || '').includes('sandbox_at_'));
  check('本地不含密码 / Cookie / SESSDATA / bili_jct / client_secret',
    !JSON.stringify(afterLogin).match(/SESSDATA|bili_jct|client_secret|password/i));
  const exp = Number(afterLogin[KEYS[2]]);
  check('过期时间是未来约 2 小时内的绝对时间戳',
    exp > Date.now() && exp < Date.now() + 3 * 3600 * 1000,
    `expiresAt=${exp}`);
  for (const endpoint of ['config', 'begin', 'callback', 'exchange', 'me']) {
    check(`链路调用 /api/oauth/${endpoint}`,
      oauthCalls.some((p) => p.endsWith(`/oauth/${endpoint}`) ||
        (endpoint === 'callback' && p === '/api/oauth/callback')));
  }

  // 4. 刷新页面：登录态从本地恢复，不需要重新授权
  await page.reload({ waitUntil: 'commit' });
  await page.waitForTimeout(9000);
  const afterReload = await storage(page);
  check('刷新后本地凭证仍在（持久化生效）',
    KEYS.every((k) => Object.prototype.hasOwnProperty.call(afterReload, k)));
  check('刷新后凭证值未变化',
    afterReload[KEYS[0]] === afterLogin[KEYS[0]]);
  await openSettings(page);
  await page.screenshot({ path: path.join(OUT, '17-oauth-signedin.png') });

  // 5. 退出登录 → 确认 → 本机凭证清空
  await page.mouse.click(...C.logoutButton);
  await page.waitForTimeout(1000);
  await page.screenshot({ path: path.join(OUT, '18-oauth-signout.png') });
  await page.mouse.click(...C.confirmLogout);
  await page.waitForFunction(
    () => !localStorage.getItem('flutter.bili_lite_oauth_access_token'),
    null,
    { timeout: 10000 }
  );
  const afterLogout = await storage(page);
  check('退出登录后本机凭证全部清除',
    KEYS.every((k) => !Object.prototype.hasOwnProperty.call(afterLogout, k)));
  await page.screenshot({ path: path.join(OUT, '19-oauth-after-signout.png') });

  // 6. 再刷新，仍是未登录状态
  await page.reload({ waitUntil: 'commit' });
  await page.waitForTimeout(9000);
  const finalStorage = await storage(page);
  check('再次刷新仍处于未登录状态',
    !Object.prototype.hasOwnProperty.call(finalStorage, KEYS[0]));

  check('全程控制台零错误', errors.length === 0, errors.slice(0, 3).join(' | '));

  console.log('──────────────────────────────────────────────');
  console.log(`OAuth 请求序列: ${oauthCalls.join(' → ')}`);
  console.log(`截图归档: ${OUT}/15~19-oauth-*.png`);
  console.log(`结果：${passed} 通过 / ${failed} 失败\n`);

  await browser.close();
  if (failed) process.exitCode = 1;
})().catch((e) => {
  console.error('端到端异常：', e);
  process.exitCode = 1;
});
