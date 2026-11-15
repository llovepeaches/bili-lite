/**
 * 静态验收：不依赖 Android SDK，直接对交付源码做白名单 / 黑名单 / 规范断言。
 * 运行： node scripts/verify.mjs
 * 说明：检查前会剥离 Kotlin 注释，避免「注释里提到旧 API 名」被误判为实际使用。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ktDir = path.join(root, 'app/src/main/kotlin/com/example/glassdock');
const ktNames = fs.readdirSync(ktDir).filter((f) => f.endsWith('.kt'));
const raw = Object.fromEntries(
  ktNames.map((n) => [n, fs.readFileSync(path.join(ktDir, n), 'utf8')]),
);
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .map((line) => {
      const i = line.indexOf('//');
      return i >= 0 ? line.slice(0, i) : line;
    })
    .join('\n');
}

const appGradleRaw = fs.readFileSync(path.join(root, 'app/build.gradle.kts'), 'utf8');
const rootGradleRaw = fs.readFileSync(path.join(root, 'build.gradle.kts'), 'utf8');
const propsRaw = fs.readFileSync(path.join(root, 'gradle.properties'), 'utf8');
const wrapperRaw = fs.readFileSync(path.join(root, 'gradle/wrapper/gradle-wrapper.properties'), 'utf8');
// Gradle 脚本里的说明性注释提到旧坐标，只检查真正的声明部分。
const appGradle = stripComments(appGradleRaw);
const rootGradle = stripComments(rootGradleRaw);
const props = stripComments(propsRaw);

const testDir = path.join(root, 'app/src/test/kotlin/com/example/glassdock');
const testNames = fs.existsSync(testDir) ? fs.readdirSync(testDir).filter((f) => f.endsWith('.kt')) : [];
const tests = testNames
  .map((n) => stripComments(fs.readFileSync(path.join(testDir, n), 'utf8')))
  .join('\n');

const code = Object.fromEntries(
  Object.entries(raw).map(([k, v]) => [k, stripComments(v)]),
);
const all = Object.values(code).join('\n');
const dock = code['GlassDock.kt'] ?? '';
const previews = code['GlassDockPreviews.kt'] ?? '';
const main = code['MainActivity.kt'] ?? '';

const checks = [];
const add = (name, ok) => checks.push({ name, ok: Boolean(ok) });
const has = (s, re) => new RegExp(re).test(s);

// ---- 版本与依赖 -----------------------------------------------------------
add('依赖为 io.github.kyant0:backdrop:2.0.1', has(appGradle, 'io\\.github\\.kyant0:backdrop:2\\.0\\.1'));
add('仓库无 JitPack / com.github.Kyant0 字样', !has(appGradle + rootGradle, 'com\\.github\\.Kyant0|jitpack'));
add('Compose 编译器插件 2.4.10 对齐库 metadata', has(rootGradle, 'org\\.jetbrains\\.kotlin\\.plugin\\.compose"\\) version "2\\.4\\.10'));
// Compose 1.12.1（backdrop 2.0.1 经 CMP 1.12.0 映射）的 AAR metadata 要求
// compileSdk >= 37，否则 aar-metadata-check 直接失败；minSdk 仍压到 23 覆盖降级区间。
add('compileSdk = 37 / minSdk = 23', has(appGradle, 'compileSdk = 37') && has(appGradle, 'minSdk = 23'));
add('AGP 升到 9.5.1（满足 Compose 1.12.1 的 minAgpVersion）', has(rootGradle, 'com\\.android\\.application"\\) version "9\\.5\\.1'));
add('Gradle wrapper 为 9.6.0（AGP 9.5.1 要求 ≥9.6.0）', has(wrapperRaw, 'gradle-9\\.6\\.0-bin\\.zip'));
add('未声明 org.jetbrains.kotlin.android（AGP 9 内置 Kotlin，声明会被拒绝）', !has(appGradle, 'org\\.jetbrains\\.kotlin\\.android'));
add('android.builtInKotlin=true 显式声明', has(props, 'android\\.builtInKotlin=true'));
add('JUnit4 测试依赖已声明', has(appGradle, 'junit:junit:4\\.13\\.2'));

// ---- 只用 2.x API --------------------------------------------------------
const alphaSymbols = [
  'rememberLiquidGlassProviderState', 'liquidGlassProvider', 'GlassStyle',
  'refractionWithDispersion', 'drawHighlight', 'InnerRefraction',
];
add('代码里 0 个旧 alpha API 符号', !alphaSymbols.some((s) => all.includes(s)));
add('使用 rememberLayerBackdrop()', has(dock, 'rememberLayerBackdrop\\s*\\{'));
add('使用 Modifier.layerBackdrop(backdrop)', has(dock, 'Modifier\\.layerBackdrop\\(backdrop\\)'));
add('使用 Modifier.drawBackdrop(...)', has(dock, 'Modifier\\.drawBackdrop\\('));
add('全局只有一个玻璃节点（无玻璃叠玻璃）', (all.match(/Modifier\.drawBackdrop\(/g) || []).length === 1);

// ---- 教程关键：背景也画进采样源 -------------------------------------------
add('采样源先 drawRect(backgroundColor)', has(dock, 'drawRect\\(backgroundColor\\)'));
add('采样源再 drawContent()', has(dock, 'drawContent\\(\\)'));
const layerIdx = dock.indexOf('Modifier.layerBackdrop');
const glassIdx = dock.indexOf('drawBackdrop(');
add('layerBackdrop 在 drawBackdrop 之前（无采样环）', layerIdx > -1 && glassIdx > layerIdx);

// ---- effects 顺序与参数 ---------------------------------------------------
const iV = dock.indexOf('vibrancy()');
const iB = dock.indexOf('blur(4f.dp.toPx())');
const iL = dock.indexOf('lens(');
add('effects 顺序 color filter ⇒ blur ⇒ lens', iV > -1 && iB > iV && iL > iB);
add('blur 取最小够用半径 4dp', has(dock, 'blur\\(4f\\.dp\\.toPx\\(\\)\\)'));
add('lens(16dp, 32dp) 且开轻微 RGB 色散', has(dock, '16f\\.dp\\.toPx\\(\\)') && has(dock, '32f\\.dp\\.toPx\\(\\)') && has(dock, 'chromaticAberration = true'));
add('lens 仅在 FULL 档调用', has(dock, 'if \\(tier == GlassTier\\.FULL\\)'));
add('shape 是 CornerBasedShape 子类 RoundedCornerShape', has(dock, 'CornerBasedShape') && has(dock, 'RoundedCornerShape\\(percent = 50\\)'));
add('highlight / shadow 用 Highlight.Default / Shadow.Default', has(dock, 'Highlight\\.Default') && has(dock, 'Shadow\\.Default'));

// ---- 可读性 tint ---------------------------------------------------------
add('onDrawSurface 存在', has(dock, 'onDrawSurface = \\{'));
add('tint 从 surfaceContainer 派生', has(dock, 'MaterialTheme\\.colorScheme\\.surfaceContainer'));
add('浅色背景压 30% 暗层', has(dock, 'Color\\.Black\\.copy\\(alpha = 0\\.30f\\)'));
add('深色背景压少量白', has(dock, 'Color\\.White\\.copy\\(alpha = 0\\.10f\\)'));
add('未照抄教程写死 Color.White.copy(alpha = 0.5f)', !has(all, 'Color\\.White\\.copy\\(alpha = 0\\.5f\\)'));

// ---- 三档降级 -------------------------------------------------------------
add('GlassTier 三档齐全', ['FULL', 'BLUR', 'FLAT'].every((t) => has(dock, `GlassTier\\.${t}`)));
add('33+ 才开 FULL（TIRAMISU）', has(dock, 'Build\\.VERSION_CODES\\.TIRAMISU'));
add('31+ 才开 BLUR（S）', has(dock, 'Build\\.VERSION_CODES\\.S'));
add('低内存 / 省电纳入判定', has(dock, 'isLowRamDevice') && has(dock, 'isPowerSaveMode'));
add('档位判定抽成纯函数 resolveGlassTier（可被 JVM 测试覆盖）', has(dock, 'internal fun resolveGlassTier\\('));
const flatBranch = (dock.match(/GlassTier\.FLAT\s*->[\s\S]*?\n\s*\)/) || [''])[0];
add('FLAT 档完全不调用 drawBackdrop（零离屏缓冲）', flatBranch.length > 0 && !flatBranch.includes('drawBackdrop'));
add('FLAT 档用普通 background + 描边', has(flatBranch, '\\.background\\(') && has(flatBranch, '\\.border\\('));

// ---- Material 3 规范 ------------------------------------------------------
add('最小点击区 48dp', has(dock, 'sizeIn\\(minWidth = 48\\.dp, minHeight = 48\\.dp\\)'));
add('文字用 MaterialTheme.typography.*', has(all, 'MaterialTheme\\.typography\\.'));
add('动态配色 / 深色模式', has(main, 'dynamicLightColorScheme') && has(main, 'dynamicDarkColorScheme') && has(main, 'isSystemInDarkTheme'));
add('selected 语义 + contentDescription + Role.Tab', has(dock, 'selectable\\(') && has(dock, 'contentDescription =') && has(dock, 'Role\\.Tab'));
add('悬浮不贴边：左右 16dp / 底部 20dp', has(dock, 'padding\\(horizontal = 16\\.dp\\)') && has(dock, 'padding\\(bottom = 20\\.dp\\)'));
add('heightIn(min) 支持字体放大不溢出', has(dock, 'heightIn\\(min = 64\\.dp\\)'));

// ---- 黑名单 ---------------------------------------------------------------
const banned = [
  'UIGlassEffect', 'glassEffect', 'GlassEffectContainer', 'RenderScript',
  'ScriptIntrinsicBlur', 'backdrop-filter', 'feDisplacementMap',
  'rememberInfiniteTransition', '.clip(', '.graphicsLayer(', 'alpha = 0.5f)',
];
banned.forEach((b) => add(`黑名单零命中：${b}`, !all.includes(b)));
add('源码未自建 RuntimeShader（由库缓存）', !has(all, 'RuntimeShader\\('));
add('LazyColumn 内容里没有玻璃节点', !has(main, 'drawBackdrop'));
add('未做全屏 shader / 全屏玻璃', !has(all, 'fillMaxSize\\(\\)\\s*\\.then\\(glassModifier|Modifier\\.fillMaxSize\\(\\)\\.drawBackdrop'));

// ---- 性能 -----------------------------------------------------------------
add('滚动可冻结 backdrop 捕获', has(dock, 'captureEnabled') && has(main, 'isScrollInProgress'));
add('静置无无限缓动高光', !has(all, 'infiniteTransition|InfiniteRepeatableSpec'));
add('玻璃节点不做父级 alpha 动画', !has(all, 'animateFloatAsState\\([^)]*alpha|\\.alpha\\('));

// ---- Preview --------------------------------------------------------------
const previewCount = (raw['GlassDockPreviews.kt'].match(/@Preview/g) || []).length;
add('Preview 覆盖 FULL / BLUR / FLAT 三档', previewCount >= 4);
add('Preview 含深色模式与字体放大 200%', has(raw['GlassDockPreviews.kt'], 'UI_MODE_NIGHT_YES') && has(raw['GlassDockPreviews.kt'], 'fontScale = 2f'));

// ---- JVM 单元测试 ---------------------------------------------------------
add('存在 JVM 单元测试文件', testNames.length > 0);
add('单元测试使用 JUnit4 @Test', has(tests, '@Test'));
add('单元测试覆盖三档降级判定', has(tests, 'resolveGlassTier'));
add('单元测试覆盖感知亮度与混合', has(tests, 'perceivedLuminance') && has(tests, 'blend'));

// ---- 输出 -----------------------------------------------------------------
const pass = checks.filter((c) => c.ok).length;
for (const c of checks.filter((x) => !x.ok)) console.error('  ✗ ' + c.name);
console.log(`\nBackdrop 玻璃底栏静态验收：${pass}/${checks.length} 通过`);
console.log(`源码文件：${ktNames.join(', ')}`);
if (pass !== checks.length) process.exit(1);
