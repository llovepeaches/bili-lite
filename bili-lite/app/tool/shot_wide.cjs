// 宽屏侧栏 + 设置页导航配置分组的视觉自检。
//
// 注意：Flutter Web 用 canvas 渲染，文字不在 DOM 里，
// 所以**不能**用 getByText 定位，一律走坐标点击。
//   NODE_PATH=$(npm root -g) node tool/shot_wide.cjs
const { chromium } = require('playwright');
const fs = require('fs');

const BASE = process.env.APP_URL || 'http://127.0.0.1:8899';
const OUT = process.env.OUT_DIR || '/tmp/dock-shots';

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const errors = [];

  // ---- 宽屏：侧栏 ----
  const wide = await browser.newPage({
    viewport: { width: 1100, height: 800 },
    deviceScaleFactor: 2,
  });
  wide.on('pageerror', (e) => errors.push('wide: ' + (e.stack || String(e))));
  await wide.goto(BASE, { waitUntil: 'commit', timeout: 60000 });
  await wide.waitForTimeout(10000);
  await wide.screenshot({ path: `${OUT}/wide-01-sidebar.png` });
  await wide.close();

  // ---- 窄屏：进设置页看导航配置分组 ----
  const narrow = await browser.newPage({
    viewport: { width: 420, height: 860 },
    deviceScaleFactor: 2,
  });
  narrow.on('pageerror', (e) => errors.push('narrow: ' + (e.stack || String(e))));
  await narrow.goto(BASE, { waitUntil: 'commit', timeout: 60000 });
  // Flutter Web 首屏要下载 main.dart.js 再启动，给足时间。
  await narrow.waitForTimeout(18000);

  // 点底栏胶囊里的「设置」（第三个标签）。
  // 注意：deviceScaleFactor=2，mouse 坐标用的是 CSS 像素，截图是 2 倍图。
  // 从 01-home.png 实测：设置齿轮图标在图上 x≈535-569 / y≈1587-1625，
  // 换算成 CSS 像素就是 x=276 / y=803。
  await narrow.mouse.click(276, 803);
  await narrow.waitForTimeout(1600);
  await narrow.screenshot({ path: `${OUT}/narrow-01-settings-top.png` });

  // 往下滑，找到「导航入口」配置区（在「外观」卡片里）。
  // 设置页很长，这里分几步滚并逐张截图，避免一次滚过头。
  for (let step = 1; step <= 5; step++) {
    await narrow.mouse.move(210, 500);
    await narrow.mouse.wheel(0, 700);
    await narrow.waitForTimeout(500);
    await narrow.screenshot({ path: `${OUT}/narrow-scroll-${step}.png` });
  }

  await narrow.close();

  console.log('页面错误 :', errors.length ? errors.slice(0, 3).join(' | ') : '无');
  console.log('截图目录 :', OUT);
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
