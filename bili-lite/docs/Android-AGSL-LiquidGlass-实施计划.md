# 悬浮玻璃胶囊底栏 · 第 0 步实施计划（**未实现，等待确认**）

> 按「【第 0 步：先别写代码】」执行。本文**只输出计划，不含任何 Kotlin / AGSL 实现源码**。
> 文中出现的函数签名均为 Android 官方文档摘录，用于逐条核对 API level 门槛，不是交付物。
>
> 核对时间：2026-11-15。来源：`developer.android.com` / `developer.android.google.cn` 的
> `RenderEffect`、`RuntimeShader`、`Window`、`WindowManager` reference，AOSP《窗口模糊处理》，
> 以及 Compose《Graphics modifiers》《Compose 中的模糊处理》官方指南。
>
> **范围说明**：本任务是独立的 Android / Kotlin / Jetpack Compose 实现计划，与
> `bili-lite` 的 Flutter 工程无关；不会改动现有 Dart 代码，不会触发该项目的
> 版本递增、提交、CI 或 Release。与上一轮 `docs/Backdrop-版本对齐.md` 是**两条不同路线**：
> 那一轮评估的是 `io.github.kyant0:backdrop` 库；本轮走**纯 Android 官方图形 API + AGSL 自研**，
> 不引入任何第三方玻璃库（理由见 §9 D2）。

---

## 0. 本轮交付边界

本轮只回答你要求的三件事（§1 / §2 / §3），外加把实现方案、降级、Material 3、
性能红线、以及确认后的交付物列成可审阅的计划（§4~§8）。**你确认后才写源码。**

---

## 1. 前置承认：Android 没有原生 Liquid Glass

明确承认，写进实现文件的类注释与交付说明里：

* **Android 平台不存在** `UIGlassEffect` / `glassEffect` / `GlassEffectContainer` /
  任何名为「Liquid Glass」的原生控件或系统材质。这些是 Apple / iOS 26 的 API，
  在 Android 上没有对应物，也无法通过任何隐藏 API 调用。
* 本实现是**屏幕空间近似（screen-space approximation）**：把「玻璃背后的内容」
  栅格化成一张位图作为输入纹理，用 `RenderEffect` 链做模糊，再用
  **AGSL（Android Graphics Shading Language）`RuntimeShader`** 在片元阶段按
  SDF 法线做像素位移、色散与高光合成。它模拟的是**观感**，不是光学折射。
* 具体做不到的部分（确认后会在「对照说明」里逐条展开）：真实的光线追迹 / 厚度折射、
  随视角变化的物理折射率、真实焦散、系统级材质与动态岛那样的跨应用合成、
  iOS 的 `UIGlassEffect` 交互语义。所有「凝胶鼓起」「边缘弯折」都是
  **数学位移 + 时间插值**，不是物理模拟。
* 因此对外措辞统一为「**逼近 iOS 26 Liquid Glass 观感的 AGSL 屏幕空间近似**」，
  绝不宣称「调用了原生 Liquid Glass」。

---

## 2. 将调用的 Android 官方图形 API 及其 API level 门槛

### 2.1 Android 平台图形 API（严格按官方 "Added in API level"）

| # | API 签名（官方文档摘录） | Added in API level | 在本实现中的用途 |
| --- | --- | --- | --- |
| 1 | `RenderEffect.createBlurEffect(float radiusX, float radiusY, Shader.TileMode edgeTreatment)` | **31** | BLUR 档磨砂；FULL 档作为 chain 的 `inner` |
| 2 | `RenderEffect.createBlurEffect(float radiusX, float radiusY, RenderEffect inputEffect, Shader.TileMode edgeTreatment)` | **31** | 备选：显式指定输入（若采用捕获位图作为输入） |
| 3 | `RenderEffect.createChainEffect(RenderEffect outer, RenderEffect inner)` | **31** | 组合 `outer(inner(source))`，官方明确 **inner 先执行、结果作为 outer 的源位图** |
| 4 | `RenderEffect.createRuntimeShaderEffect(RuntimeShader shader, String uniformShaderName)` | **33** | 把 RenderNode 内容绑定到名为 `content` 的 shader uniform，作为 chain 的 `outer` |
| 5 | `android.graphics.RuntimeShader(String agslSource)` | **33** | 编译一次 AGSL；类本身也是 33，低于 33 需整段隔离（见 §5） |
| 6 | `RuntimeShader.setFloatUniform(String, float…)` / `(String, float[])` | **33** | 每帧只更新尺寸、圆角、touch 点、press 进度、band 宽度、色散系数 |
| 7 | `RuntimeShader.setColorUniform(String, long)` / `(String, Color)` | **33** | 传入从 `surfaceContainer` 派生的 tint / 高光色；要求 AGSL 侧声明 `layout(color)` 且类型为 `vec3`/`vec4` |
| 8 | `RuntimeShader.setIntUniform(String, int…)` | **33** | 档位标志等整型参数（可选） |
| 9 | `RuntimeShader.setInputShader(String, Shader)` | **33** | 仅在需要把额外 Shader 喂给 AGSL 时使用；本实现优先用 `content` |
| 10 | `View.setRenderEffect(RenderEffect)` | **31** | View 体系入口；本实现是纯 Compose，走 #11，不直接调用 |
| 11 | `Modifier.graphicsLayer { renderEffect = … }`（`GraphicsLayerScope.renderEffect`） | 依赖 `RenderEffect`，**31 生效** | Compose 侧挂链的唯一位置，只挂在背景副本节点 |
| 12 | `Modifier.blur(radius: Dp, edgeTreatment: BlurredEdgeTreatment)` | 内部走 `RenderEffect`，**31 生效** | 仅 BLUR 档、仅挂在纯背景节点；<31 官方明确「ignored」 |
| 13 | `android.graphics.RenderEffect.asComposeRenderEffect()`（`androidx.compose.ui.graphics`） | 库版本门槛，见 §2.3 | 把平台 `RenderEffect` 转成 Compose `RenderEffect` |
| 14 | AGSL：`uniform shader content;` + `content.eval(float2)` + `half4 main(float2)` | 由 `RuntimeShader` 决定，**33** | 片元采样与返回；坐标是 **RenderNode 局部像素坐标**，左上为原点 |
| 15 | `Window.setBackgroundBlurRadius(int)` | **31** | **本实现不调用**，见 §9 D5 / §2.2 |
| 16 | `WindowManager.LayoutParams.FLAG_BLUR_BEHIND` + `setBlurBehindRadius(int)` | **31** | **本实现不调用**，见 §9 D5 / §2.2 |

> 关键门槛结论：**`createChainEffect` 是 31，但只要链里含 `createRuntimeShaderEffect` /
> `RuntimeShader`，整条链只能在 ≥33 使用**。因此 FULL 档严格限定 API 33+，
> BLUR 档可用 31~32，FLAT 档不触碰任何 `RenderEffect`。

### 2.2 档位判断与跨窗口模糊的运行时检测（非图形 API，但必须做）

| API | 门槛 | 用途 |
| --- | --- | --- |
| `Build.VERSION.SDK_INT` / `Build.VERSION_CODES.S` / `TIRAMISU` | 1 / 31 / 33 | 三档分界 |
| `ActivityManager.isLowRamDevice()` | **19** | 命中即强制 FLAT，零离屏缓冲 |
| `PowerManager.isPowerSaveMode()` | **21** | 你要求的「省电」降级到 FLAT；用 `ACTION_POWER_SAVE_MODE_CHANGED` 监听动态切换 |
| `WindowManager.isCrossWindowBlurEnabled` / `addCrossWindowBlurEnabledListener` | **31** | **仅当**未来改成浮动半透明 Activity/Dialog 时才需要；AOSP 文档明确省电模式、多媒体隧道、GPU 限制会在运行时关闭跨窗口模糊，必须监听并把 surface 换成更不透明的兜底 |
| `Configuration.fontScale` / `LocalDensity` | 1 | 字体放大，见 §6 |

### 2.3 Jetpack Compose 库版本要求（**不是 Android API level**）

| 能力 | 库 / 版本 | 说明 |
| --- | --- | --- |
| `GraphicsLayerScope.renderEffect`、`asComposeRenderEffect()`、`BlurEffect`、`isSupported()` | `androidx.compose.ui:ui-graphics` **1.1.0+** | 官方注明「RenderEffect is only supported on Android 12 and above; attempts on older versions will be ignored」 |
| `rememberGraphicsLayer()` / `GraphicsLayer.record { }` / `GraphicsLayer.toImageBitmap()` / `drawLayer()` | Compose **1.7.0+** | 官方《Graphics modifiers》「Write contents of a composable to a bitmap」标准路径 |
| `Modifier.blur` / `BlurredEdgeTreatment` | Compose **1.1.0+** | 低版本平台静默忽略，需自行降级 |
| Material 3 `dynamicLightColorScheme` / `dynamicDarkColorScheme` | `material3`，动态配色本身 **API 31+** | <31 回退到 baseline light/dark scheme |

### 2.4 minSdk / compileSdk 建议（确认后写入 `build.gradle`）

* `minSdk 23`（让 FLAT 档有真实设备意义；若你只要覆盖现代设备，可提到 26）。
* `compileSdk 35`（或 36）、`targetSdk` 与 `compileSdk` 对齐。
* 依赖只加 Compose BOM + `material3` + `ui` / `ui-graphics` + `activity-compose`；
  **不加** haze / backdrop / liquid-glass（见 §9 D2）。

---

## 3. 黑名单逐条确认：**九条全未使用**

| # | 黑名单项 | 确认 | 落实方式 |
| --- | --- | --- | --- |
| 1 | 声称调用原生 Liquid Glass / `UIGlassEffect` / `glassEffect` / `GlassEffectContainer` | ✅ 无 | §1 明确承认为 Apple API 且 Android 不存在，全篇只称「AGSL 屏幕空间近似」 |
| 2 | 只写 `Modifier.blur` + 半透明白 + 亮边就宣称是 Liquid Glass | ✅ 无 | FULL 档必须含 AGSL lens：SDF 边缘 band + 数值法线位移 + RGB 三次采样色散 + Fresnel 高光 + touch bulge，缺一不叫 FULL |
| 3 | 把 `Modifier.blur` 加在含 `Text`/`Icon` 的容器上 | ✅ 无 | 所有 `RenderEffect` / `blur` 只挂在**纯背景副本节点**；内容层是兄弟节点、零 effect（§4.5） |
| 4 | `RenderScript` / `ScriptIntrinsicBlur` | ✅ 无 | 已弃用，全链路用 `RenderEffect`；依赖里也不引入 renderscript 兼容包 |
| 5 | CSS `backdrop-filter` / SVG `feDisplacementMap` | ✅ 无 | 那是 Web；本项目上一轮的 `liquid-glass-dock` 是 Web 组件，与本 Android 实现互不引用 |
| 6 | 全屏 `RuntimeShader`、每帧 `new RuntimeShader`、无版本判断、无低内存降级 | ✅ 无 | shader 只挂胶囊尺寸节点；`remember { }` 编译一次；`@RequiresApi(33)` + SDK 判断；`isLowRamDevice` 强制 FLAT（§5 / §7） |
| 7 | 照抄 iOS HIG：44pt 点击区 / SF 字体 / Dynamic Type / capsule 贴屏幕边 | ✅ 无 | 48dp、`MaterialTheme.typography.*`、`LocalDensity.fontScale`、悬浮 `horizontal 16dp / bottom 20dp`（§6） |
| 8 | 玻璃叠玻璃、把玻璃放进 `LazyColumn` 每一行 | ✅ 无 | 全局只有一个玻璃胶囊（导航层）；列表行是普通 M3 组件。这也是规避官方 FAQ 记录的 **RenderThread SIGSEGV 采样环**的关键 |
| 9 | 自定义 Shape 配 lens、固定白色 tint、忽略 `onDrawSurface` 可读性 | ✅ 无 | 用解析 SDF 圆角矩形（非自定义 `Shape` 对象）；tint 从 `surfaceContainer` 派生并压约 30% 暗层；可读性有独立色调层与对比度验收（§4.4 / §8） |

> 补充确认：不使用 `RenderNode` 记录**实时 View 树**；不在含玻璃的父节点做 alpha 动画
> （改用 translation-only）；不在 `drawBackdrop` 外再套同形状 `.clip`（会裁掉扩散高光）；
> 不把 Offscreen / `graphicsLayer` 离屏合成与 `RenderEffect` 串在同一条 modifier 链上
> （拆成父子两节点）。

---

## 4. 渲染管线设计（严格按你给的顺序）

### 4.1 ① 捕获「玻璃背后的内容」为静态背景副本 + `isCapturing` 守卫

* 捕获范围**只包含玻璃下方的内容层**（列表 / 页面背景 / 图片），**不含玻璃自身、
  不含图标与文字**。捕获矩形 = 胶囊 bounding box + 一圈 blur padding，不是全屏。
* **`isCapturing` 守卫**：在捕获入口的 `draw()` 里，若 `isCapturing == true`
  则**直接 return**（不录制、不重绘），防止 `root.draw()` 递归回玻璃自身形成无限反馈。
  捕获开始置 `true`，`try/finally` 保证任何异常路径都复位，避免守卫卡死导致底栏永久消失。
* **栅格化方式（需要你确认，见 §9 D1）**：
  * 主选：Compose 官方 `rememberGraphicsLayer()` → `record { drawContent() }` →
    **立即 `toImageBitmap()` 栅格化**成位图。白名单允许 `GraphicsLayer.record`；
    ⚠️ 禁的是「用它记录整棵实时 View 树」，这里只记录**一个局部背景层**并立刻落地成
    Bitmap，不形成实时采样环，也不触发 HWUI 栈溢出。
  * 备选（若你要求绝对零 RenderNode）：`android.graphics.Picture` + software
    `Canvas(bitmap)` 立即栅格化。代价是背景内容需要**显式重绘一遍**（双份绘制），
    且与真实 UI 同步更脆弱。我倾向主选，理由写在 §9 D1。
* 位图**降采样倍率不低于 0.3**（你对「不要低于 30%」的要求，理解见 §9 D4），
  避免 2dp 模糊在 3x 屏上塌成马赛克；位图按胶囊尺寸复用，不每帧重建大对象。
* 滚动时**冻结捕获**：用 `LazyListState.isScrollInProgress` / `NestedScrollConnection`
  判断，滚动期间复用上一张位图，松手后延迟一帧再追上（§7）。

### 4.2 ② 背景副本 → blur（inner）→ AGSL lens 采样（outer）

* 把 4.1 的位图作为**唯一输入**：在一个「只绘制这张位图」的节点上挂
  `Modifier.graphicsLayer { renderEffect = chain }`。该节点的 RenderNode 内容
  就是背景副本，因此 `content` 采样到的正是它。
* 链构造：`createChainEffect(outer = createRuntimeShaderEffect(shader, "content"),
  inner = createBlurEffect(radiusPx, radiusPx, TileMode.CLAMP))`。
  官方语义 `outer(inner(source))`，**inner 先执行**，outer 的 `content.eval()` 拿到的是
  **模糊后**的背景 —— 与你的顺序完全一致。
* `radiusPx` 由 dp 经 density 换算；取「刚好够」的最小值（初值 8~12dp，
  真机调参），`TileMode.CLAMP` 避免边缘 DECA L 透明造成黑边。

### 4.3 ③ AGSL 数学（全部在片元阶段，无循环）

| 效果 | 数学做法（自然语言描述，非源码） |
| --- | --- |
| SDF 圆角矩形 | 解析有符号距离函数，输入局部像素坐标、半尺寸、圆角半径；`d<0` 为内部 |
| 边缘 band | `|d|` 经 `smoothstep` 得到「仅靠近轮廓才生效」的权重，中心区权重≈0（内容区不被扭曲） |
| 数值法线 | 对 SDF 做中心差分（±eps 的 x/y 偏导）再归一化，**不依赖 `dFdx` 之类导数内置函数**，兼容性更稳 |
| 折射位移 | 采样坐标 = 原坐标 + 法线 × `refractionHeight` × band 权重；`refractionHeight ≤ 圆角半径`，`refractionAmount ≤ 尺寸短边`，避免越界采样 |
| RGB 色散 | R/G/B 用略不同位移系数（例如 1.00 / 0.94 / 0.88）分三次 `content.eval()`，合成时只取各自通道；**仅 3 次采样，无循环** |
| Fresnel 式高光 | 由法线与固定光向（左上）的点积 + `pow(1 - |dot|, k)` 得到轮廓高光，乘 band 权重；光向静态，不做无限缓动 |
| touch bulge | 以触点为中心的高斯权重 × 按压进度，额外叠加到位移量并轻微抬高高光；按压用一次性 spring，结束即停 |
| vibrancy | 在 AGSL 内用亮度插值提升饱和度（`mix(luma, rgb, s)`），**不调用**白名单外的 `createColorFilterEffect` |

* AGSL 侧约定：`uniform shader content;` + `half4 main(float2)`；
  颜色 uniform 用 `layout(color)` 配合 `setColorUniform`；
  `main()` 返回值必须是**预乘 alpha**（`RGB × A`），否则半透明处会发灰；
  坐标是 RenderNode 局部像素坐标，尺寸用 `setFloatUniform("uSize", w, h)` 传入。

### 4.4 ④ 半透明色调层（浅色背景可读性）

* 独立于 effect 链，用普通 `Surface` / `drawRect` 叠在「模糊+折射层」之上、
  内容层之下，**不套任何 `RenderEffect`**。
* 颜色从 `MaterialTheme.colorScheme.surfaceContainer` 派生，不写死纯白 / 纯黑：
  * 浅色背景：叠加约 **30% 黑的压暗层**（提高前景文字对比度到你要求的「仍可读」）；
  * 深色背景：叠加少量白（约 8~12%）提亮；
  * 高对比度模式 / 字体放大时进一步加深，验收用 WCAG 对比度检查。
* 这一层取代官方示例里常见的 `Color.White.copy(alpha = 0.5f)` 写死做法。

### 4.5 ⑤ 内容层单独绘制，永不套任何 RenderEffect

* 图标、文字、`selected` 指示器是 **兄弟节点**，位于胶囊 `Box` 的最上层，
  不参与 `graphicsLayer { renderEffect }`、不参与 `Modifier.blur`、不进入捕获。
* 结构（父→子）：背景副本节点（含 effect 链） → 色调层 → 描边/高光层 → 内容层。
  四层分离，任何一层都不包裹内容层。
* 内容层用 `semantics { contentDescription = …; stateDescription / selected }`，
  48dp 最小点击区，TalkBack 可读。

---

## 5. 三档降级（必须实现）

| 档 | 触发条件 | 图形路径 | 离屏缓冲 |
| --- | --- | --- | --- |
| **FULL** | `SDK_INT ≥ 33` 且 `!isLowRamDevice` 且非省电 | 4.1 捕获 → blur(inner) → AGSL lens(outer)：vibrancy + 折射 + 色散 + Fresnel 高光 + bulge；外加色调层 | 1 张胶囊尺寸位图 + 1 个最小 offscreen |
| **BLUR** | `SDK_INT` 31~32（或 33+ 但运行中降级） | 只有磨砂模糊（`createBlurEffect` 或纯背景节点上的 `Modifier.blur`）+ 描边高光；**无 AGSL、无色散、无 lens** | 1 个最小 offscreen |
| **FLAT** | `<31` / `isLowRamDevice` / 省电 / shader 编译失败 | 纯半透明色块 + 1dp 描边；**零 `RenderEffect`、零离屏缓冲、不捕获背景** | 0 |

判定顺序：`SDK_INT` → `isLowRamDevice()` → `isPowerSaveMode()` → 运行时兜底
（AGSL 编译异常 / `RenderEffect` 不被支持时直接降 BLUR，再失败降 FLAT）。

**类加载隔离（真实坑，必须处理）**：`RuntimeShader` 类在 API < 33 的设备上可能
在**类验证阶段**就抛异常，仅靠 `if (SDK_INT >= 33)` 运行时分支不够。
实现时把 AGSL 常量、`RuntimeShader` 构造、链构造全部放进独立的
`@RequiresApi(33)` 文件 / object，由 FULL 分支显式进入；BLUR / FLAT 代码路径
**不引用任何 `RuntimeShader` 类型**。

**动态切换**：注册省电模式广播，`isPowerSaveMode` 打开时从 FULL/BLUR 降到 FLAT，
关闭后恢复；切换时不重建 shader 实例，只切换绘制分支。

---

## 6. Material 3 规范（不是 iOS HIG）

| 要求 | 落实 |
| --- | --- |
| 最小点击区 48dp | 每个导航项 `sizeIn(minWidth/minHeight = 48.dp)`，**不是 44pt** |
| 字体 | `MaterialTheme.typography.labelMedium` 等，**不用 SF / Dynamic Type** |
| 动态配色 | `dynamicLightColorScheme` / `dynamicDarkColorScheme`（API 31+），<31 回退 baseline；tint 从 `surfaceContainer` 派生 |
| 深色模式 / 高对比度 | 跟随系统 `isSystemInDarkTheme()`；高对比度下加深色调层、加粗描边 |
| 字体放大 | 文字用 `sp` + `LocalDensity.fontScale` 自适应，胶囊高度随内容增长，不裁切文字 |
| 悬浮不贴边 | `horizontal 16dp` / `bottom 20dp`，圆角胶囊，不贴屏幕边 |
| 无障碍 | `semantics { contentDescription; selected }`、`Role.Tab`、TalkBack 播报选中态、stateDescription |
| 玻璃使用范围 | **只用于导航 / 悬浮控件层**；列表行、正文、卡片一律普通 M3 组件 |

---

## 7. 性能红线（逐条对应）

| 红线 | 落实 |
| --- | --- |
| `RuntimeShader` 只编译一次 | `remember { RuntimeShader(AGSL) }`，key 不含 size / touch；之后**只** `setFloatUniform` / `setColorUniform` |
| 禁止全屏 shader / 复杂循环 | shader 节点尺寸 = 胶囊 bounding box；AGSL 内无循环，仅 3 次 `content.eval()` |
| 滚动冻结捕获 | 滚动中复用旧位图、不 `record`；松手后延迟一帧追上 |
| 降采样不低于 30% | 位图倍率 ≥ 0.3，且 blur 半径按 density 换算，避免 3x 屏马赛克 |
| 静置不无限缓动高光 | 光向固定常量；高光完全由 SDF + band 静态计算；只有 touch bulge 用一次性 spring，动画结束注销 |
| blur 半径最小够用 | 8~12dp 起步真机调参，禁止 40dp 级大半径；半径越大采样与离屏缓冲越大 |
| 零 OOM | FLAT 档不分配位图 / 不建离屏；位图按胶囊尺寸复用并在 `dispose` 时释放；大屏/折叠屏设上限 |
| 避免离屏套离屏 | 捕获层与 effect 层拆成父子两节点，不在同一条 modifier 链上叠加 `graphicsLayer` 离屏与 `RenderEffect` |

---

## 8. 确认后的交付物（本轮**不**交付）

1. **完整 Kotlin / Compose 源码**：AGSL 常量字符串、`RenderEffect` 链构造、
   三档降级状态机、`GlassCapsuleNavBar` 组件、`@Preview`（FULL / BLUR / FLAT 三档预览）、
   示例 `Scaffold` 用法、AGSL 编译失败兜底。
2. **「哪些是 Android 原生能力 / 哪些是数学近似 / 哪些做不到」对照说明**：
   * 原生：`RenderEffect` 模糊、`createChainEffect` 组合、`RuntimeShader` 片元着色、
     动态配色、`isLowRamDevice` / 跨窗口模糊检测；
   * 数学近似：SDF 轮廓、数值法线、折射位移、RGB 色散、Fresnel 高光、touch bulge、vibrancy；
   * 做不到：物理折射 / 焦散 / 真实厚度 / 系统级材质 / 跨应用合成 / iOS 交互语义。
3. **`build.gradle` 依赖与 minSdk 建议**：见 §2.4，含 Compose BOM 版本、
   `compileSdk` / `targetSdk`、以及「不加第三方玻璃库」的说明。
4. **验收清单与已知风险**：三档真机矩阵（31 / 32 / 33+ / 低内存 / 省电）、
   浅色背景文字对比度、TalkBack、48dp 点击区、滚动帧率、内存与离屏缓冲数量、
   shader 编译失败降级、以及**个人库稳定性问题**（官方 FAQ 记录的
   RenderThread SIGSEGV / Fatal signal 11 采样环、库版本漂移、KMP 分支未发布 API 变动）——
   本实现不引入库，故该类风险仅作为「若改用 haze / backdrop / liquid-glass」的对照列出。

---

## 9. 需要你确认的决策点

| # | 决策 | 我的建议 | 理由 |
| --- | --- | --- | --- |
| **D1** | 背景捕获用 `GraphicsLayer.record` + 立即 `toImageBitmap()`，还是严格按 ⚠️ 字面用 `Picture` + software `Canvas` 双份重绘？ | **主选 `GraphicsLayer.record` + 立即栅格化** | 白名单明确允许 `GraphicsLayer.record`；⚠️ 禁的是「记录实时 View 树」形成采样环。只记录局部背景层并立刻落地成 Bitmap、加 `isCapturing` 守卫，可同时避开递归与 HWUI 栈溢出。`Picture` 方案在纯 Compose 下需把背景内容重绘一遍，双份绘制且易不同步 |
| **D2** | 是否引入 haze / backdrop / liquid-glass 之一？ | **不引入，纯官方 API 自研** | 完全可控、无个人库维护 / API 漂移风险；上一轮 `docs/Backdrop-版本对齐.md` 已记录官方 FAQ 的 RenderThread SIGSEGV 采样环；自研能精确实现 `isCapturing` 守卫与三档降级 |
| **D3** | `minSdk` / `compileSdk` 目标？ | `minSdk 23` / `compileSdk 35` | 让 FLAT 档有真实设备意义；若只覆盖现代设备可把 minSdk 提到 26 |
| **D4** | 「背景降采样不要低于 30%」我理解为**降采样后分辨率 ≥ 原尺寸 30%（倍率 ≥ 0.3，不得降得更狠）** | 按此理解实现 | 若你指的是「最多只降 30%（保留 70%）」，告诉我，我调倍率 |
| **D5** | 跨窗口模糊（`setBackgroundBlurRadius` / `FLAG_BLUR_BEHIND`）是否启用？ | **本组件不启用** | 这是**同一个 Activity 内的悬浮胶囊底栏**，不是浮动半透明 Activity/Dialog，跨窗口模糊无「后面的窗口」可采样。白名单那条标注「仅浮动的半透明 Activity/Dialog」也吻合。若未来改成独立 Dialog，再启用并补 `isCrossWindowBlurEnabled` 运行时检测与兜底 |

---

**等你确认以上（尤其 D1 / D2 / D4）后，我再进入实现，交付 §8 的四项内容。
在此之前不写任何 `.kt` / AGSL 源码，也不改动 `bili-lite` 的版本、提交或发布状态。**
