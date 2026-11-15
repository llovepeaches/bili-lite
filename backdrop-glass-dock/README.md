# Backdrop 悬浮玻璃胶囊底栏（Android / Jetpack Compose）

依据官方设计文档实现：<https://kyant.gitbook.io/backdrop/tutorials/glass-bottom-bar>

## 0. 前提与边界

**Android 没有原生 Liquid Glass。** `UIGlassEffect` / `glassEffect` / `GlassEffectContainer`
都是 Apple 的 API，Android 平台不存在。本实现用的是 Kyant0 的 **Backdrop 2.x** 库：
它在 Compose 层把「玻璃背后的内容」录成图层，再用 `RenderEffect`（API 31+）模糊、
用 `RuntimeShader`（API 33+）按圆角矩形 SDF 做边缘折射与 RGB 色散，属于**屏幕空间近似**，
不是物理折射，也拿不到真实焦散、视角相关折射率或系统级材质合成。

这是上一轮 `docs/Backdrop-版本对齐.md` 的库路线实现；另一份
`docs/Android-AGSL-LiquidGlass-实施计划.md` 是纯官方 API 自研的备选路线，两者不混用。

## 1. 快速开始

| 项 | 值 |
| --- | --- |
| 依赖坐标 | `io.github.kyant0:backdrop:2.0.1`（Maven Central，Gradle 自动解析 `backdrop-android`） |
| minSdk / compileSdk | **23 / 37**（FULL 档需运行设备 API 33+；compileSdk 37 由 Compose 1.12.1 的 AAR metadata 强制） |
| Kotlin | AGP 9 内置（`android.builtInKotlin=true`）；**Compose 编译器插件 2.4.10** 对齐库 metadata |
| Compose | BOM `2026.09.00`（库映射到 CMP / AndroidX Compose 1.12.0） |
| AGP / Gradle | `9.5.1` / `9.6.0`（AGP 9.5.1 的 version-check 要求 Gradle ≥ 9.6.0） |

```bash
./gradlew :app:assembleDebug         # 产出 debug APK
./gradlew :app:testDebugUnitTest     # 12 个 JVM 单元测试（三档降级 / 亮度 / 混合）
./gradlew :app:compileDebugKotlin   # 编译校验
./gradlew :app:installDebug         # 真机看效果
node scripts/verify.mjs             # 无需 Android SDK 的静态验收（64 项）
```

> **为什么 compileSdk 必须是 37**：backdrop 2.0.1 经 Compose Multiplatform 1.12.0 映射到
> AndroidX Compose **1.12.1**，其 AAR metadata 声明 `minCompileSdk = 37`，AGP 的
> `aar-metadata-check` 会直接失败，无法用 warning 蒙混过去。
> **为什么 AGP 必须是 9.1.0+**：Compose 1.12.1 同时要求 AGP ≥ 9.1.0，
> 因此 Gradle 也要跟着升到 9.x（AGP 8.9.2 最高只测试到 compileSdk 35）。
> **为什么 AGP 要到 9.5.1**：Android 17 的平台目录名是 `android-37.0`（`ApiLevel=37.0`），
> AGP 9.1.0 只认 `android-37`，会报 `Failed to find target with hash string 'android-37'`；
> 9.5.1 能正确识别带小版本的平台目录。
> `minSdk` 仍保持 23，以覆盖三档降级里的低版本区间。

> **Kotlin 的坑**：AGP 9 起内置 Kotlin，`org.jetbrains.kotlin.android` 插件**不能再声明**
> （声明会被 version-check 直接拒绝）；反过来若用 `android.builtInKotlin=false` +
> 显式 KGP，又必须同时 `android.newDsl=false`，且该开关在 AGP 10 会被移除。
> 本工程走默认的内置 Kotlin，只保留 `org.jetbrains.kotlin.plugin.compose` 2.4.10
> （Compose 编译器插件必须与内置 KGP 匹配）。

> Wrapper 的 `distributionUrl` 指向腾讯云 Gradle 镜像（官方源在本环境只返回 307，
> Gradle 的 URL 校验不接受）。离线或海外环境把
> `gradle/wrapper/gradle-wrapper.properties` 改回
> `https\://services.gradle.org/distributions/gradle-9.6.0-bin.zip` 即可。

`io.github.kyant0:backdrop:2.0.1` 的 Android 变体依赖 `kotlin-stdlib 2.4.10`、
`org.jetbrains.compose.{foundation,ui,ui-graphics} 1.12.0`、`io.github.kyant0:shapes 1.2.1`。
若你的现有工程 Kotlin/Compose 版本较低，**优先对齐工具链**，不要靠 force 降级库版本。

## 2. 目录

```
app/src/main/kotlin/com/example/glassdock/
├── GlassDock.kt           # 组件主体：采样源、三档降级、tint、条目语义
├── MainActivity.kt        # 最小可运行示例（动态配色 / 深色 / 滚动冻结）
└── GlassDockPreviews.kt   # 4 个 Preview：FULL / BLUR深色 / FLAT / 字体200%
app/src/test/kotlin/com/example/glassdock/
└── GlassDockLogicTest.kt  # 12 个 JVM 用例：三档判定 / 感知亮度 / overlay 混合
scripts/verify.mjs         # 64 项静态断言
```

## 3. 与官方教程的对应

| 教程步骤 | 本实现 |
| --- | --- |
| `Box { MainNavHost() }` | `GlassDockScaffold` 的 `content()` |
| `rememberLayerBackdrop()` + `layerBackdrop(backdrop)` | ✅ 采样源只包住背后内容 |
| Step 2：`drawRect(backgroundColor); drawContent()` | ✅ **必须**，否则胶囊超出内容处会采到透明像素、边缘出现空洞 |
| `drawBackdrop(shape = { CircleShape }, effects = { ... })` | ✅ 改成 `RoundedCornerShape(percent = 50)`，同属 `CornerBasedShape` |
| `vibrancy(); blur(4dp); lens(16dp, 32dp)` | ✅ 顺序严格不变；FULL 档额外开 `chromaticAberration = true` |
| `onDrawSurface = { drawRect(Color.White.copy(alpha = 0.5f)) }` | ❌ **有意不照抄**：写死白在浅色壁纸上会让 `onSurface` 文字失去对比度 |

三处有意差异写在 `GlassDock.kt` 文件头注释里：语义 tint、胶囊 shape、三档降级。

### 层级（也是规避 RenderThread SIGSEGV 的关键）

```
Box(root, safeContentPadding)
├─ Box(layerBackdrop(backdrop))        ← 采样源，只包「背后内容」
│  └─ content()
└─ GlassDock(drawBackdrop(backdrop))   ← 兄弟节点，不把自己画进采样源
```

玻璃节点里的 `Row / Icon / Text` 由库的 `drawContent()` 在 effect 链之外绘制，
**不套任何 RenderEffect**，所以始终锐利；`drawBackdrop` 外也没有同形状 `.clip`，
扩散高光/阴影不会被裁掉。

## 4. 三档降级

| 档 | 条件 | 做法 |
| --- | --- | --- |
| `FULL` | `SDK_INT >= 33` 且非低内存/省电 | `vibrancy → blur(4dp) → lens(16dp,32dp, chromaticAberration=true)` + `Highlight.Default` / `Shadow.Default` |
| `BLUR` | `SDK_INT 31..32` | 只 `vibrancy → blur(4dp)`，**不调用 lens**；描边高光仍由库提供 |
| `FLAT` | `<31` / `isLowRamDevice()` / 省电 | **完全不调用 `drawBackdrop`**，普通 `background + border` 半透明色块，零离屏缓冲 |

库在 <31 会跳过 effects 但仍执行 `recordLayer` 建离屏层，所以 FLAT 必须从外层绕开。
门槛常量与库 `Platform.kt` 的 `S(31)` / `TIRAMISU(33)` 一致。

**可读性 tint**：从 `MaterialTheme.colorScheme.surfaceContainer` 派生，
浅色背景叠 `Color.Black.copy(alpha = 0.30f)`，深色背景叠 `Color.White.copy(alpha = 0.10f)`，
内容色用 `primary` / `onSurfaceVariant`。不是固定白，也不忽略 `onDrawSurface`。

## 5. 「库提供 / 必须自己写」对照

| Backdrop 2.x 库提供（不要重复造） | 本工程自己写 |
| --- | --- |
| `LayerBackdrop` 采样、`layerBackdrop` 注册、`rememberCombinedBackdrop` | 悬浮定位（左右 16dp / 底部 20dp）、胶囊尺寸与安全区 |
| RenderEffect 链：`vibrancy()` / `blur()` / `lens()` | 三档分支判断、`isLowRamDevice()` / 省电检测 |
| lens 的 RuntimeShader 与库内 `RuntimeShaderCache`（编译一次并缓存） | 不自建任何 `RuntimeShader`、不新增全屏 shader |
| `Highlight.Default` / `Shadow.Default` / `InnerShadow` 绘制 | 48dp 点击区、`selectable` 的 `selected` 语义、`contentDescription`、TalkBack |
| `onDrawBehind / onDrawBackdrop / onDrawSurface / onDrawFront` 钩子 | 由 `surfaceContainer` 派生的语义 tint、深浅两套暗/亮层 |
| `isRenderEffectSupported()` / `isRuntimeShaderSupported()` 内部兜底 | FLAT 档完全绕开 `drawBackdrop`；滚动时 `captureEnabled=false` 冻结捕获 |
| `exportedBackdrop` / `layerBlock` 动画入口 | 不用 alpha 动画、不做无限缓动高光；进出场如需动画只做 translation |

`drawPlainBackdrop` / `rememberCombinedBackdrop` 属于**允许清单**而非必用清单：
本屏只有一个玻璃层，引入它们会变成玻璃叠玻璃或跨区域采样环，因此没有使用。

## 6. 白名单 / 黑名单

白名单逐条落在代码里；黑名单九条全部零命中，由 `scripts/verify.mjs` 自动断言：
不声称 Apple 原生 API、源与玻璃同 window、无同形状 `.clip`、无同链
`graphicsLayer` / Offscreen、无含玻璃父节点 alpha 动画、无玻璃叠玻璃 / LazyColumn 内玻璃、
无自定义 Shape 配 lens、无固定白 tint、不照抄 iOS HIG（用 48dp /
`MaterialTheme.typography.*` / 动态配色 / 深色模式 / 字体放大 / TalkBack）。

静态验收：`node scripts/verify.mjs` → **64/64 通过**（版本与工具链、2.x API、effects 顺序、
三档、Material 3、黑名单、性能红线、Preview 覆盖、单元测试覆盖）。

## 7. 验证现状（本机无设备，已闭环 / 待真机）

| 项 | 状态 | 证据 |
| --- | --- | --- |
| Gradle 9.6.0 + AGP 9.5.1 + compileSdk 37 编译 | ✅ 通过 | `./gradlew :app:assembleDebug` → `BUILD SUCCESSFUL` |
| debug APK 产出 | ✅ 18 MB | `app/build/outputs/apk/debug/app-debug.apk`，`aapt2 dump badging` 显示 `compileSdkVersion='37' / minSdkVersion:'23' / targetSdkVersion:'37'`，V2 签名校验通过 |
| backdrop 库类已入 dex | ✅ | dex 中可检出 `com/kyant/backdrop/backdrops/LayerBackdrop`、`highlight/Highlight`、`shadow/Shadow` 等 169 处引用 |
| 三档降级 / 亮度 / 混合逻辑 | ✅ 12/12 | `./gradlew :app:testDebugUnitTest`（JUnit4，报告在 `app/build/test-results/`） |
| 白名单 / 黑名单 / API 用法 | ✅ 64/64 | `node scripts/verify.mjs` |
| **折射 / 色散 / 高光的实际观感** | ⏳ 待真机 | 本环境只有 SDK 无 emulator / system-images，无法渲染 GPU 上的 `RenderEffect` + `RuntimeShader`；须按第 8 节清单在 API 33+ 真机验收 |

## 8. 真机验收清单

1. API 33+ 真机：胶囊边缘能看到背后文字被弯折、轻微 RGB 色散、左上高光与投影。
2. 浅色壁纸下四个标签文字清晰可读；切深色模式、字体放大 200% 不溢出裁切。
3. API 31~32 设备：只有磨砂模糊与描边，无折射，且不崩溃。
4. <31 / 低内存 / 省电：纯半透明色块，`adb shell dumpsys gfxinfo` 无额外离屏层。
5. 快速滚动列表：不出现明显掉帧；松手后玻璃重新跟上背景。
6. TalkBack 逐项播报「首页标签，已选择／未选择，标签页」；每个点击区 ≥48dp。
7. 全仓搜索无旧 alpha 符号，无 `Fatal signal 11 (SIGSEGV)`。
8. `./gradlew :app:assembleDebug` + `./gradlew :app:testDebugUnitTest` 通过。

## 9. 已知风险

- **RenderThread SIGSEGV（库官方已知 issue）**：`Fatal signal 11 (SIGSEGV), code 2`
  出现在玻璃套玻璃形成采样环时（`layerBackdrop` 放在 `drawBackdrop` 之后）。
  规避：本工程源与玻璃是兄弟节点；需要跨层采样时只用 `exportedBackdrop`。
- **backdrop 随缩放走形**：把动画写在 `graphicsLayer` 会让 backdrop 一起缩放；
  库给的入口是 `drawBackdrop` 的 `layerBlock`。本工程不做缩放动画。
- **lens 形状限制**：非 `CornerBasedShape` 会抛异常；`refractionHeight` 必须 ≤
  `shape.minCornerRadius`、`refractionAmount` ≤ `size.minDimension`（本例 16dp ≤ 32dp、
  32dp ≤ 64dp）。自定义 Shape 一律不配 lens。
- **均匀背景失效**：纯白/纯黑背景经 blur + lens 仍几乎均匀，必须靠语义 tint 建立内部亮度差。
- **模拟器 / 老设备静默失效**：`isRuntimeShaderSupported()` 会吞掉不支持的 lens，
  看起来「没效果」但不是代码错误。
- **alpha 动画裁阴影**：含玻璃的父节点 `alpha < 1f` 会被 Compose 用离屏层裁掉扩散阴影。
- **个人库稳定性与工具链漂移**：Backdrop 是单人维护库，2.0.1 绑定 Kotlin 2.4.10 /
  CMP 1.12.0；升级 Kotlin/Compose 时可能再次出现 metadata 不兼容，建议锁定版本并回归
  第 8 节清单。这也是保留纯官方 API 自研备选路线的原因。
- **AGP 9 的 Kotlin 开关会过期**：`android.builtInKotlin=false` 在 AGP 10 将被移除，
  且它必须与 `android.newDsl=false` 同时使用；本工程依赖内置 Kotlin，AGP 升级时
  需同时回归 Compose 编译器插件版本（当前锁定 2.4.10）。
- **Android 17 平台目录命名**：SDK 目录是 `android-37.0`（`ApiLevel=37.0`），
  AGP 9.1.0 只认 `android-37` 会直接报错；本工程锁定 AGP 9.5.1，
  降级 AGP 前必须重新确认这一点。
- **冻结捕获的语义**：`captureEnabled=false` 依赖库保留上一次 `recordLayer` 的结果，
  不同库版本行为可能变化；默认 `true`，只在滚动时短时关闭。

## 10. 与 bili-lite 的关系

这是**独立 Android 工程**，没有改 `bili-lite` 的 Dart 代码、版本号、提交或 Release。
按「不发布版本先」的约束：无新 commit / tag / push / CI 触发 / Release，
`bili-lite` 仍是 `0.1.0+1`。
