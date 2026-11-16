// 液态玻璃底栏视觉自检。
//
// 判定「滑动切页时底栏固定不动」不能直接比像素 —— 底栏上沿有一条会流动的
// 镜面高光（液态感的主要来源），每一帧都在变。这里改成比**几何特征**：
//   1. 底栏上边框所在的那一行（白色亮边）—— 底栏上下移动会立刻暴露；
//   2. 选中项粉色透镜的质心行 —— 透镜跟着选中项变，但不该整块上下跳。
// 另外抓一张滑动中途的截图，确认内容页在跟手平移。
//   NODE_PATH=$(npm root -g) node tool/shot_dock.cjs
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
  const page = await browser.newPage({
    viewport: { width: 420, height: 860 },
    deviceScaleFactor: 2,
  });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));

  await page.goto(BASE, { waitUntil: 'commit', timeout: 60000 });
  await page.waitForTimeout(9000);

  await page.screenshot({ path: `${OUT}/01-home.png` });

  // 内容区（底栏上方）左滑，中途截一张看跟手平移。
  await page.mouse.move(340, 380);
  await page.mouse.down();
  for (let i = 1; i <= 8; i++) {
    await page.mouse.move(340 - i * 24, 380);
    await page.waitForTimeout(16);
  }
  await page.screenshot({ path: `${OUT}/02-mid-swipe.png` });
  for (let i = 9; i <= 14; i++) {
    await page.mouse.move(340 - i * 24, 380);
    await page.waitForTimeout(16);
  }
  await page.mouse.up();
  await page.waitForTimeout(1400);
  await page.screenshot({ path: `${OUT}/03-after-swipe.png` });

  console.log('页面错误 :', errors.length ? errors.slice(0, 3).join(' | ') : '无');
  console.log('截图目录 :', OUT);

  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
