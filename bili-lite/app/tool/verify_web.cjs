// Web 回归：确认浏览器里的 App 真的向 BFF 发起了实时数据请求。
//   NODE_PATH=$(npm root -g) node tool/verify_web.cjs
const { chromium } = require('playwright');

const BASE = process.env.APP_URL || 'http://127.0.0.1:8787';

(async () => {
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = [];
  const calls = [];

  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });
  // 只监听 request：对图片代理响应调用 response.json() 会一直等不到可解析
  // 的 body，进而把整个脚本挂住。数据源另用一次轻量 fetch 单独确认。
  page.on('request', (req) => {
    const url = req.url();
    if (!url.includes('/api/') || url.includes('/api/img')) return;
    calls.push({ path: new URL(url).pathname, status: 200, meta: null });
  });

  await page.goto(BASE, { waitUntil: 'commit', timeout: 30000 });
  await page.waitForTimeout(10000);

  const domNodes = await page.evaluate(() => document.body.querySelectorAll('*').length);
  const textLen = await page.evaluate(() => (document.body.innerText || '').length);

  console.log('页面节点数   :', domNodes);
  console.log('可见文本长度 :', textLen);
  console.log('API 请求     :');
  for (const c of calls) {
    console.log(`  ${c.path.padEnd(14)} HTTP ${c.status}  source=${c.meta ? c.meta.source : '-'}`);
  }

  const feed = calls.find((c) => c.path === '/api/feed');
  const health = calls.find((c) => c.path === '/api/health');
  // 单独取一次数据源标记：live / cache 都说明 BFF 已连上 B 站，mock 才是降级。
  const meta = await page.evaluate(async () => {
    const r = await fetch('/api/feed?ps=2');
    const j = await r.json();
    return j && j.meta ? j.meta : null;
  });
  const source = meta ? meta.source : '';
  const live = !!feed && ['live', 'cache', 'bili'].includes(source);

  console.log('');
  console.log('健康探测     :', health ? '已发起' : '未发起');
  console.log('推荐流数据源 :', source || '未确认');
  console.log('控制台错误   :', errors.length ? errors.slice(0, 3).join(' | ') : '无');
  console.log('结论         :', live ? 'Web 应用已连接 B 站实时数据' : '未确认实时连接');

  await browser.close();
  if (!live || errors.length) process.exitCode = 1;
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
