# 第 10 项 · Backdrop 版本对齐报告（对齐完成，并按官方教程实现）

> 第 0 步（版本 / API / 约束核对）原文保留在下方供审计；2026-11-15 用户给出
> 官方教程 `tutorials/glass-bottom-bar` 后已进入实现，交付物在
> `/workspace/backdrop-glass-dock`（见 §9）。文中 Kotlin 声明均为
> `Kyant0/AndroidLiquidGlass` 仓库 `kmp` 分支的库源码或官方文档原文引用，
> 用于核对签名，不是本项目的实现代码。
>
> 核对时间：2026-11-15。来源：Maven Central metadata、GitHub `kmp` 分支源码、
> 官方文档站 `kyant.gitbook.io/backdrop`（含 `llms.txt` / API / FAQ / 教程）。

---

## 1. 版本结论

| 项目 | 结论 | 依据 |
| --- | --- | --- |
| 仓库 | `Kyant0/AndroidLiquidGlass`，现行主分支 `kmp` | GitHub 默认分支文件树、289 commits |
| 仓库现行库名 | **Backdrop**（README 标题 `# Liquid Glass (Backdrop)`，CMP Catalog 已改名 `Backdrop Catalog`） | README、iosApp 提交记录 |
| 正式坐标 | **`io.github.kyant0:backdrop`**（Maven Central，非 JitPack） | 官方 Get started 的 `implementation("io.github.kyant0:backdrop:<version>")` + Maven Central badge |
| 当前最新正式版 | **`2.0.1`** | `repo1.maven.org/.../backdrop/maven-metadata.xml`：`<latest>2.0.1</latest>` `<release>2.0.1</release>`，`lastUpdated 20260826040722` |
| 2.x 版本线 | `2.0.0-alpha01` / `02` / `03` → `2.0.0-rc01` → `2.0.0` → `2.0.1` | Maven metadata `<versions>` |
| 1.x 版本线 | `1.0.0-rc02` / `1.0.0` / `1.0.1` … `1.0.6` | 同上 |
| 目标 API | **2.x Backdrop API** | 本文第 2 节全部签名来自 `kmp` 分支（即 2.x）源码 |

**明确不使用旧 alpha 一代**：`com.github.Kyant0:AndroidLiquidGlass`（JitPack）+
`1.0.0-alpha09` 前后的 `rememberLiquidGlassProviderState` / `liquidGlassProvider` /
`GlassStyle(InnerRefraction(...), Dispersion..., GlassMaterial...)` / `refraction()` /
`refractionWithDispersion()` / `drawHighlight()`。

> 判定依据不只是「名字不一样」：2.x 的采样源是 `LayerBackdrop` +
> `Modifier.layerBackdrop`，效果载体是 `BackdropEffectScope` 上的 RenderEffect 链，
> 高光/阴影是 `drawBackdrop` 的 `highlight` / `shadow` 参数；旧 alpha 是
> provider state + `GlassStyle` 组合式。两者的数据流完全不同，**混写会直接编译失败
> 或产出错误的采样环**，因此本任务全篇只用 2.x。

---

## 2. 将调用的 API 签名与 Android API level 门槛

以下签名逐字核对自 `kmp` 分支 `backdrop/src/commonMain/kotlin/com/kyant/backdrop/`。
门槛中的 `S = 31`、`TIRAMISU = 33`，来自
`backdrop/src/androidMain/kotlin/com/kyant/backdrop/Platform.kt`：

```kotlin
@ChecksSdkIntAtLeast(Build.VERSION_CODES.S)
actual fun isRenderEffectSupported(): Boolean =
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S          // 31

@ChecksSdkIntAtLeast(Build.VERSION_CODES.TIRAMISU)
actual fun isRuntimeShaderSupported(): Boolean =
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU  // 33
```

官方 `api/backdrop-effects.md` 原文：
> "Backdrop effects are `RenderEffect`s radically. They only take effect with
> **Android 12 and above**. Some effects involving with `RuntimeShader` need
> **Android 13 and above**."
> "The order of effects matters … **color filter ⇒ blur ⇒ lens**"
> "**Lens (Android 13+)** — ⚠️ To use the lens effect, your `shape` must be
> `CornerBasedShape`."
> "`height` must be in [0, `shape.minCornerRadius`] … `amount` must be in
> [0, `size.minDimension`]."

### 2.1 签名清单

| # | API（库源码声明） | 完整签名 | API level 门槛 |
| --- | --- | --- | --- |
| 1 | `rememberLayerBackdrop` | `@Composable fun rememberLayerBackdrop(graphicsLayer: GraphicsLayer = rememberGraphicsLayer(), onDraw: ContentDrawScope.() -> Unit = DefaultOnDraw): LayerBackdrop` | 无 SDK 门槛（仅 Compose） |
| 2 | `Modifier.layerBackdrop` | `fun Modifier.layerBackdrop(backdrop: LayerBackdrop): Modifier` | 无 SDK 门槛 |
| 3 | `rememberCombinedBackdrop` | `@Composable fun rememberCombinedBackdrop(backdrop1: Backdrop, backdrop2: Backdrop): Backdrop`；另有 3 参重载与 `vararg backdrops: Backdrop` 重载 | 无 SDK 门槛 |
| 4 | `Modifier.drawBackdrop` | `fun Modifier.drawBackdrop(backdrop: Backdrop, shape: () -> Shape, effects: BackdropEffectScope.() -> Unit, highlight: (() -> Highlight?)? = DefaultHighlight, shadow: (() -> Shadow?)? = DefaultShadow, innerShadow: (() -> InnerShadow?)? = null, layerBlock: (GraphicsLayerScope.() -> Unit)? = null, exportedBackdrop: LayerBackdrop? = null, onDrawBehind: (DrawScope.() -> Unit)? = null, onDrawBackdrop: DrawScope.(drawBackdrop: DrawScope.() -> Unit) -> Unit = DefaultOnDrawBackdrop, onDrawSurface: (DrawScope.() -> Unit)? = null, onDrawFront: (DrawScope.() -> Unit)? = null): Modifier` | 本身无门槛；**内部 `updateEffects()` 以 `isRenderEffectSupported()`（≥31）为前置条件** |
| 5 | `Modifier.drawPlainBackdrop` | 与 #4 同参，但**没有** `highlight` / `shadow` / `innerShadow` 三个参数（源码只链 `DrawBackdropElement`，不链 Highlight/Shadow/InnerShadow Element）→ 大面积面板去白边 | 同上 |
| 6 | `Highlight.Default` | `data class Highlight(width: Dp = 0.5f.dp, blurRadius: Dp = width / 2f, alpha: Float = 1f, style: HighlightStyle = HighlightStyle.Default)`，`companion object` 内 `@Stable val Default: Highlight = Highlight()`（另有 `Ambient` / `Plain`） | 无 |
| 7 | `Shadow.Default` | `data class Shadow(radius: Dp = 24f.dp, offset: DpOffset = DpOffset(0f.dp, radius / 6f), color: Color = Color.Black.copy(alpha = 0.1f), alpha: Float = 1f, blendMode: BlendMode = DrawScope.DefaultBlendMode)`，`@Stable val Default: Shadow = Shadow()` | 无 |
| 8 | `effects { vibrancy() }` | `fun BackdropEffectScope.vibrancy()`（= `colorControls(saturation = 1.5f)`） | **≥31**（ColorFilter/RenderEffect） |
| 9 | `effects { blur(...) }` | `fun BackdropEffectScope.blur(radius: Float, edgeTreatment: TileMode = TileMode.Clamp)` | **≥31**（RenderEffect） |
| 10 | `effects { lens(...) }` | `fun BackdropEffectScope.lens(refractionHeight: Float, refractionAmount: Float, depthEffect: Boolean = false, chromaticAberration: Boolean = false)` — **源码更正：`refractionAmount` 无默认值、必须显式传**（教程传 `16dp, 32dp`） | **≥33**（RuntimeShader）；`shape` 必须 `CornerBasedShape`；`refractionHeight ≤ shape.minCornerRadius`；`refractionAmount ≤ size.minDimension` |
| 11 | `onDrawSurface` | `onDrawSurface: (DrawScope.() -> Unit)?`；绘制顺序 `onDrawBehind → onDrawBackdrop → onDrawSurface → drawContent → onDrawFront` | 无 |
| 12 | `isRenderEffectSupported` / `isRuntimeShaderSupported` | `expect fun isRenderEffectSupported(): Boolean` / `expect fun isRuntimeShaderSupported(): Boolean`；Android actual 见上方代码块 | 库自带检测：≥31 / ≥33 |
| 13 | `ActivityManager.isLowRamDevice()` | Android 平台 API（非本库） | API 19+（我们自己调用） |

补充会用到但不产生 SDK 门槛的 effect：
`colorFilter(colorFilter: ColorFilter)`、`opacity(alpha: Float)`、
`colorControls(brightness=0f, contrast=1f, saturation=1f)`、
`exposureAdjustment(ev: Float)`、`gammaAdjustment(power: Float)`（**≥33**）、
`effect(effect: RenderEffect)`、`runtimeShaderEffect(key, shaderString, uniformShaderName, block)`（**≥33**）。

### 2.2 三档降级（确认后实现，此处仅为策略约定）

| 档 | 条件 | 做法 |
| --- | --- | --- |
| A 全效果 | `SDK_INT >= 33` 且非低内存 | `vibrancy() → blur() → lens(..., chromaticAberration = true)`，`Highlight.Default` / `Shadow.Default` 保留 |
| B 仅模糊 | `SDK_INT in 31..32` | 只 `vibrancy() → blur()`，**不调用 lens**；其余不变 |
| C 纯 Surface | `< 31` 或 `isLowRamDevice()` | **完全不调用 `drawBackdrop`**（库在 <31 仍会 `recordLayer` 建离屏缓冲），改用普通半透明 `Surface` + theme tint，零离屏缓冲 |

顺序严格 `color filter ⇒ blur ⇒ lens`；`lens` 的 shape 用 `RoundedCornerShape`（`CornerBasedShape` 子类），
折射参数按 `minCornerRadius` / `size.minDimension` 钳制。

---

## 3. 白名单逐条确认

| 白名单条目 | 确认 |
| --- | --- |
| `rememberLayerBackdrop()` + `Modifier.layerBackdrop(backdrop)` 注册采样源 | ✅ 用 #1 + #2，且二者同一 window |
| `Modifier.drawBackdrop(backdrop, shape, effects, onDrawSurface, highlight, shadow, innerShadow)` | ✅ 用 #4 全签名，`highlight`/`shadow` 走 `Highlight.Default` / `Shadow.Default` |
| `Modifier.drawPlainBackdrop(...)` 大面积面板去白边 | ✅ 白名单允许；**实现时未使用**——本屏只有一层玻璃，再引一层会变成玻璃叠玻璃 / 采样环，见 §9 |
| effects 顺序 color filter ⇒ blur ⇒ lens | ✅ 官方 API 文档强制 |
| lens 的 shape 必须 `CornerBasedShape`，参数上界 | ✅ 用 `RoundedCornerShape`，按文档钳制 |
| `onDrawSurface` 从 `surfaceContainer` 派生 tint，浅色背景压约 30% 暗层 | ✅ 自己实现；**不照抄官方教程的 `Color.White.copy(alpha = 0.5f)`**（那是示例，不满足浅色背景可读性要求） |
| `SDK_INT >= TIRAMISU(33)` 才开 lens；31~32 只 blur；更低 + 低内存走纯半透明 Surface，零离屏缓冲 | ✅ 与 `Platform.kt` 的 31/33 完全一致 |
| 跨区域采样用 `rememberCombinedBackdrop` | ✅ 需要时用 #3 |

## 4. 黑名单逐条确认（**均未使用**）

| # | 黑名单写法 | 本方案 |
| --- | --- | --- |
| 1 | 声称调用原生 Liquid Glass / `glassEffect` / `UIGlassEffect` | ❌ 不出现。这是 Apple API；本项目只用 Kyant0 Backdrop 的 Compose 实现 |
| 2 | backdrop 源与玻璃放在不同 window（Popup/Dialog） | ❌ 不出现。源与玻璃同 window；弹层内容走普通 `GlassSurface` 兜底 |
| 3 | `drawBackdrop` 外再套同形状 `.clip` | ❌ 不出现。库自身已按 shape 裁剪；外层 clip 会裁掉扩散高光/阴影 |
| 4 | Offscreen / `graphicsLayer` 与 `drawBackdrop` 串在同一 modifier 链 | ❌ 不出现。库的动画入口是 `drawBackdrop` 的 `layerBlock`；确需离屏时拆成父子两节点 |
| 5 | 对含玻璃的父节点做 alpha 动画 | ❌ 不出现。只用 translation-only 进出场 |
| 6 | 玻璃叠玻璃、玻璃放进 `LazyColumn` 每一行 | ❌ 不出现。玻璃只用于悬浮导航胶囊这一层 |
| 7 | 自定义 Shape 配 lens / 固定白色 surface tint / 忽略 `onDrawSurface` | ❌ 不出现。lens 只用 `RoundedCornerShape`；tint 由 `surfaceContainer` 派生；必用 `onDrawSurface` |
| 8 | 照抄 iOS HIG（44pt / SF / Dynamic Type） | ❌ 不出现。按 Material 3：48dp 最小点击区、`MaterialTheme.typography.*`、动态配色、深色模式、字体放大、`semantics { contentDescription; selected }` 与 TalkBack |
| 9 | 旧 alpha API（provider state / `GlassStyle` / `refraction()` 等） | ❌ 不出现。见第 1 节 |

---

## 5. 「库提供 / 必须自己写」对照（**规划，非实现**）

| 库提供 | 必须自己写 |
| --- | --- |
| `LayerBackdrop` 采样、`layerBackdrop` 注册、`rememberCombinedBackdrop` 合并 | 胶囊的布局、尺寸、悬浮定位与安全区 |
| RenderEffect 链（vibrancy / blur / lens）与 `BackdropEffectScope` | 三档降级的分支判断与 `isLowRamDevice()` |
| lens 的 RuntimeShader 及库内 `RuntimeShaderCache`（编译一次并缓存） | 不在组件里重复构造 shader / 不新增全屏 shader；限制采样区为胶囊最小矩形 |
| `Highlight.Default` / `Shadow.Default` / `InnerShadow` 的绘制 | 选中态、点击反馈、`selected` 语义与 TalkBack、48dp 点击区 |
| `onDrawSurface` / `onDrawBehind` / `onDrawFront` 绘制钩子 | 由 `MaterialTheme.colorScheme.surfaceContainer` 派生的 tint（浅色背景压约 30% 暗层）、`onSurface` 内容色 |
| `isRenderEffectSupported()` / `isRuntimeShaderSupported()` | 降级 C 档完全绕开 `drawBackdrop`（库在 <31 仍建离屏层） |
| `exportedBackdrop`、`layerBlock` | 滚动时冻结 backdrop 捕获；静置时不无限缓动高光角度 |
| — | `@Preview` 三档（亮/暗/降级）、验收清单、已知风险 |

---

## 6. 验收清单（确认后实现时逐项核验）

1. 依赖为 `io.github.kyant0:backdrop:2.0.1`，仓库无 JitPack / `com.github.Kyant0` 字样。
2. 全仓搜索不到旧 alpha 符号（`rememberLiquidGlassProviderState` / `GlassStyle` / `refractionWithDispersion` 等）。
3. 33 / 31~32 / <31（含低内存）三档在真机或 Preview 下分别呈现全效果 / 仅模糊 / 纯 Surface。
4. `effects` 块顺序为 `vibrancy() → blur() → lens()`；`lens` 参数按 `minCornerRadius`、`size.minDimension` 钳制。
5. 浅色壁纸下文字对比度可读（tint 不是固定白）；深色模式与字体放大 200% 不溢出。
6. 无外层同形状 `.clip`、无同链 `graphicsLayer`、无父节点 alpha 动画、无玻璃叠玻璃、无 LazyColumn 内玻璃。
7. 最小点击区 ≥48dp；每个 tab 有 `contentDescription` 与 `selected` 语义，TalkBack 可读。
8. 不出现全屏 shader；RuntimeShader 只由库缓存一次；滚动时冻结捕获。
9. `./gradlew :app:compileDebugKotlin` 通过（若落地到工程）；无 `Fatal signal 11` 崩溃。

## 7. 已知风险

- **RenderThread SIGSEGV（库官方已知 issue）**：FAQ 原文
  `Fatal signal 11 (SIGSEGV), code 2 (SEGV_ACCERR), fault addr 0x__ in tid __ (RenderThread), pid __`，
  并指向 `tutorials/glass-bottom-sheet`。该教程明确成因：**玻璃套玻璃形成采样环**——把
  `layerBackdrop` 放在 `drawBackdrop` 之后，内容既被画进 backdrop、又去采样这个 backdrop。
  规避：跨层采样只用 `exportedBackdrop` 参数，绝不自建循环。
- **backdrop 随缩放走形**：官方 interactive-bottom-bar 教程指出，把动画写在 `graphicsLayer`
  会让 backdrop 一起缩放；应改用 `drawBackdrop` 的 `layerBlock`。
- **lens 的形状限制**：非 `CornerBasedShape` 会抛异常；自定义 Shape 一律不配 lens。
- **均匀背景失效**：纯白 / 纯黑背景经 blur + lens 后仍几乎均匀，必须用语义 tint 建立内部亮度差。
- **模拟器 / 老设备静默失效**：`isRuntimeShaderSupported()` 会吞掉不支持的 lens，看起来"没效果"但不是代码错误。
- **低版本仍有离屏开销**：库在 <31 会跳过 effects，但 `recordLayer` 仍执行，所以 C 档必须完全不调用 `drawBackdrop`。
- **alpha 动画裁阴影**：含玻璃的父节点一旦 `alpha < 1f`，Compose 会用离屏层裁掉扩散阴影。

---

## 8. 当前状态

第 0 步对齐完成；用户给出官方教程后已进入实现，**交付物已产出**（见 §9）。
`bili-lite` 的 Flutter 代码、版本号与发布状态未受任何影响，仍是 `0.1.0+1`、
HEAD `2e6c364`，无新 commit / tag / push / CI / Release。

---

## 9. 实现交付（2026-11-15，按 `tutorials/glass-bottom-bar`）

独立工程：`/workspace/backdrop-glass-dock/`，与 `bili-lite` 完全隔离。

| 文件 | 内容 |
| --- | --- |
| `app/src/main/kotlin/com/example/glassdock/GlassDock.kt` | 组件主体：采样源、三档降级、语义 tint、条目语义 |
| `.../MainActivity.kt` | 最小可运行示例：动态配色 / 深色模式 / 滚动冻结 |
| `.../GlassDockPreviews.kt` | 4 个 `@Preview`：FULL / BLUR 深色 / FLAT / 字体 200% |
| `app/build.gradle.kts`、`build.gradle.kts`、`settings.gradle.kts` | 依赖 `io.github.kyant0:backdrop:2.0.1`、BOM 2026.09.00、Compose 编译器插件 2.4.10、AGP 9.5.1 / Gradle 9.6.0、minSdk 23 / compileSdk 37 |
| `app/src/test/kotlin/com/example/glassdock/GlassDockLogicTest.kt` | 12 个 JVM 用例：三档降级判定、感知亮度、overlay 混合 |
| `scripts/verify.mjs` | 64 项静态断言（版本与工具链、2.x API、effects 顺序、三档、M3、黑名单、性能红线、Preview、单元测试覆盖） |
| `README.md` | 「库提供 / 自己写」对照、真机验收清单、已知风险（含 RenderThread SIGSEGV、个人库稳定性） |

### 9.1 严格按教程的关键点

1. `rememberLayerBackdrop { drawRect(backgroundColor); drawContent() }` —— 教程 Step 2，
   背景必须画进采样源，否则胶囊超出内容处会采到透明像素。
2. `layerBackdrop(backdrop)` 只包住背后内容；`drawBackdrop(...)` 是**兄弟节点**，
   避免官方 FAQ 记录的玻璃套玻璃采样环（RenderThread `Fatal signal 11`）。
3. `effects` 顺序 `vibrancy() → blur(4dp) → lens(16dp, 32dp)`；FULL 档追加
   `chromaticAberration = true` 得到轻微 RGB 色散。
4. `highlight = { Highlight.Default }` / `shadow = { Shadow.Default }` 显式传入；
   `onDrawSurface` 按 `surfaceContainer` 派生 tint，**不照抄**教程写死的
   `Color.White.copy(alpha = 0.5f)`。

### 9.2 与教程的三处有意差异

| 教程 | 本实现 | 原因 |
| --- | --- | --- |
| `onDrawSurface = { drawRect(Color.White.copy(alpha = 0.5f)) }` | `surfaceContainer` + 浅色压 30% 黑 / 深色压 10% 白 | 固定白在浅色壁纸上会让 `onSurface` 文字失去对比度 |
| `shape = { CircleShape }` | `RoundedCornerShape(percent = 50)` | 同属 `CornerBasedShape`（lens 硬性要求），更明确表达胶囊 |
| 单条 effects 链 | FULL / BLUR / FLAT 三档 | 31/33 门槛与低内存、省电降级；FLAT 完全不调 `drawBackdrop` |

`drawPlainBackdrop` 与 `rememberCombinedBackdrop` 属于允许清单而非必用清单，
本屏只有一层玻璃，故未使用（避免玻璃叠玻璃）。

### 9.3 验收结果

* `node scripts/verify.mjs` → **64/64 通过**（含「仓库零旧 alpha 符号」「全局只有一个
  `drawBackdrop`」「FLAT 分支不含 `drawBackdrop`」「无 `.clip` / `.graphicsLayer` /
  alpha 动画 / Apple API 字样」等断言）。
* 源码签名逐字核对自 `kmp` 分支，包名确认：
  `com.kyant.backdrop`（`drawBackdrop` / `BackdropEffectScope`）、
  `com.kyant.backdrop.backdrops`（`rememberLayerBackdrop` / `layerBackdrop`）、
  `com.kyant.backdrop.effects`（`vibrancy` / `blur` / `lens`）、
  `com.kyant.backdrop.highlight` / `.shadow`。
* **真实 Kotlin 编译已通过**（不再停留在「待验证」）：
  * 环境：`/opt/android-sdk`，平台 `android-37.0`（Android 17 / `ApiLevel=37.0`）、
    `build-tools;37.0.0`，JDK 17。
  * 工具链：Gradle **9.6.0** + AGP **9.5.1** + compileSdk **37** / minSdk **23**。
  * 三个卡点及其解法：
    1. `compileSdk` 必须 ≥ 37 —— Compose 1.12.1 的 AAR metadata 声明
       `minCompileSdk = 37`，`aar-metadata-check` 是硬失败，不是 warning。
    2. AGP 必须 ≥ 9.1.0（Compose 1.12.1 的 `minAgpVersion`），且必须 ≥ 9.5.x ——
       Android 17 的平台目录名是 `android-37.0`，AGP 9.1.0 只认 `android-37`，
       会报 `Failed to find target with hash string 'android-37'`。
    3. AGP 9 起内置 Kotlin：`org.jetbrains.kotlin.android` **不能声明**
       （version-check 直接拒绝）；走 `android.builtInKotlin=true` + 仅声明
       `org.jetbrains.kotlin.plugin.compose` 2.4.10。反向组合
       （`android.builtInKotlin=false`）还必须同时 `android.newDsl=false`，
       且该开关在 AGP 10 会被移除。
  * 产出：`app/build/outputs/apk/debug/app-debug.apk`（约 18 MB，`aapt2 dump badging`
    显示 `compileSdkVersion='37' / minSdkVersion:'23' / targetSdkVersion:'37'`，
    V2 签名校验通过；dex 中可检出 `com/kyant/backdrop/**` 169 处引用）。
  * `./gradlew :app:testDebugUnitTest` → **12/12 通过**；
    `./gradlew :app:lintDebug` → 仅剩 1 条来自 `androidx.lifecycle` 依赖自身的
    `ObsoleteLintCustomCheck`（"Library lint checks reference invalid APIs"），
    本工程代码零 lint 告警。
* **仍待真机**：折射 / 色散 / 高光的实际观感无法在本环境验收 —— 这里只有 SDK，
  没有 emulator 与 system-images，`RenderEffect` + `RuntimeShader` 需真实 GPU。
  验收步骤见独立工程 README 第 8 节。
