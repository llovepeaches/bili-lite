# Bili Lite · 简洁的哔哩哔哩第三方多端客户端

一套代码覆盖 **Android / iOS / Web / Windows / macOS / Linux**，基于哔哩哔哩公开 Web 数据，
只保留「看内容」这件事：推荐、热门、排行榜、搜索、视频详情与评论、**应用内播放 + 弹幕**，以及纯本地的收藏 / 历史 / 稍后再看，加上 **B 站 App 扫码登录**（另有官方 OAuth 2.0 备用通道）。

> 非官方项目，仅供学习与个人使用，与哔哩哔哩官方无任何关联。

---

## 一眼看懂

```
┌──────────────────────────────────────────────────────────────┐
│  Flutter App（一套 Dart 代码，六端共用）                        │
│  首页推荐/热门/排行榜 · 搜索 · 详情+评论 · 应用内播放+弹幕 · 我的 · 设置 │
│  液态玻璃：iOS 26 式透镜 + 边缘折射高光 + Clear / Tinted 双材质  │
│  自适应布局：<700px 底部导航 / ≥700px 侧栏；2~5 列网格           │
└──────────┬──────────────────────────────┬──────────────────────┘
           │ Web：同源 REST /api/*         │ 原生端：HTTPS 直连
┌──────────▼───────────────────────────┐  │
│  Node BFF（零依赖，node src/index.js）│  │ Dart 直连客户端
│  ① spi 访客身份 + UA/Referer 注入     │  │ bili_direct.dart
│  ② 5 套上游字段归一为 Video/Comment   │  │ 同一套归一规则
│  ③ 缓存 + stale-on-error + 快照降级   │  │ 同一套访客身份
│  ④ 图片代理 ⑤ 视频流代理(Range)       │  │ 进程内 TTL 缓存
│  ⑥ 托管 Flutter Web 产物              │  │
└──────────┬───────────────────────────┘  │
           │ HTTPS                        │ HTTPS
┌──────────▼──────────────────────────────▼───────────────────┐
│  api.bilibili.com 公开 Web 接口                                │
│  rcmd / popular / ranking v2 / search / view / reply / spi     │
│  playurl(播放地址) · dm/list.so(弹幕) · bilivideo(视频流)      │
└──────────────────────────────────────────────────────────────┘
           任一层失败 → assets/offline.json 内置真实快照自动降级
```

**三条数据链路**（`ApiConfig` / `ApiClient` 决定）：

| 场景 | 链路 | 说明 |
| --- | --- | --- |
| Web | 同源 BFF 代理 | 浏览器有 CORS 限制，且 Web 端图片需代理规避防盗链 |
| Android / iOS / Windows / macOS / Linux | **直连 B 站公开接口** | 安装包不需要电脑上的 Node BFF，装好就是实时数据 |
| 断网 / 风控 / 上游异常，或 `OFFLINE=1` | 内置离线快照 | 界面不白屏，来源标签显示「离线·陈旧」 |

Web 之所以仍要 BFF：B 站没有给第三方开放 CORS，且无访客 Cookie 时详情/搜索接口会返回风控 HTML 页。
原生端没有这两个限制，因此 `bili_direct.dart` 用 spi 动态换取 `buvid3/buvid4`（失败则有兜底身份），
再按与 `server/src/normalize.js` 同构的规则归一。设置页会如实显示「已连接 B 站 / 已降级」与当前访客身份。

**登录是第四条独立链路**，与浏览数据完全解耦——不登录也能看全部内容。

主通道是 **B 站 App 扫码登录**：客户端直连 B 站 Web 登录接口，不需要开放平台凭证，
也不需要用户自己部署任何服务，独立安装包开箱即用。它拿的是 B 站 Web 登录
Cookie（SESSDATA / bili_jct / DedeUserID 等），仅保存在本机、只发往 bilibili.com。

```
原生端（Android / iOS / 桌面）            B 站
   │ ① GET passport.bilibili.com/.../qrcode/generate      │
   ├────────────────────────────────────────────────────►│ → url + qrcode_key
   │ ② QrImage 渲染 url，手机 B 站 App 扫码并确认           │
   │ ③ 每 2s GET .../qrcode/poll?qrcode_key=               │
   ├────────────────────────────────────────────────────►│ → 86101 未扫 / 86090 待确认 / 0 成功
   │ ④ 成功时从 Set-Cookie 与回调 URL 取登录 Cookie         │
   │ ⑤ GET api.bilibili.com/x/web-interface/nav（带 Cookie）│ → 昵称 / 头像 / mid
   │ ⑥ Cookie 存入本机 SharedPreferences                   │
```

Web 端受同源策略限制，由 BFF 的 `/api/qr/*` 做纯转发代理（不落盘、不缓存、不打印 Cookie）；
原生端完全不经过 BFF。

**备用通道**是官方 OAuth 2.0，只服务已有自建授权服务的场景（`client_secret` 只能留在服务端）：

```
Flutter App                         BFF（唯一持有 client_secret）        B 站开放平台
   │  ① /api/oauth/begin                    │                              │
   ├─────────────────────────────────────►│ 生成一次性 state，返回授权页 URL  │
   │  ② 系统浏览器 / 同页打开官方授权页 ────┼─────────────────────────────────►│ account.bilibili.com
   │                                       │  ③ 回调 gourl?code=&state=      │
   │                                       │◄─────────────────────────────────┤
   │                                       │ 校验 state → POST /x/account-oauth2/v1/token
   │                                       ├─────────────────────────────────►│ api.bilibili.com
   │  ④ 302 回 /?oauth_ticket=<一次性码>    │  token 只在内存暂存 60s          │
   │◄─────────────────────────────────────┤                              │
   │  ⑤ /api/oauth/exchange 领取 → 写入本机 SharedPreferences
   │  ⑥ /api/oauth/me（签名 2.0 + USER_INFO）→ 昵称 / 头像 / openid
```

`client_secret` 只在 BFF 进程的环境变量里，不写入客户端、安装包、日志、Git 或响应；
授权码 `code` 也不落客户端。详见 [「B 站账号」](#b-站账号登录)。

---

## 30 秒跑起来

```bash
cd server
node src/index.js          # 端口 8787，自动换取访客身份
```

另开一个终端构建 Web 版：

```bash
cd app
flutter pub get
flutter build web
```

然后打开 **http://localhost:8787** —— BFF 会同时提供 API 与刚构建好的 Flutter Web App。
浏览器里也能「添加到主屏 / 安装应用」，直接当 PWA 用。

只想看 UI、不联网也可以：`MOCK_MODE=1 node src/index.js`，全部走内置的真实数据快照。

**登录不需要上面这个服务**：Android APK / Windows exe / iOS 直接点账号面板的「扫码登录」，
用手机 B 站 App 扫一下即可，无需开放平台凭证、无需自建后端。
只有想体验 **官方 OAuth 备用通道** 而没有开放平台凭证时，才用 `BILI_OAUTH_SANDBOX=1 node src/index.js` 启动，
展开账号面板的「官方 OAuth 与授权服务（高级 / 可选）」，会出现醒目的「演示授权 · 非 B 站官方」标签，
可完整走一遍授权 / 续期 / 退出登录。真实凭证的配置方式见 [「B 站账号登录」](#b-站账号登录)。

**独立安装包也不需要 BFF 拿数据**：Android APK / Windows exe 会自行直连 B 站公开接口拿实时数据，
只有连不上时才降级到内置的 `assets/offline.json`。真机调试若想改回走本机 BFF，可以在账号面板
「授权服务」里直接填 `http://<电脑IP>:8787`（**运行时生效，无需重新打包**），或编译时用
`flutter run --dart-define=BFF_URL=http://<电脑IP>:8787`；完全禁用联网则加 `--dart-define=OFFLINE=1`。
注意 `10.0.2.2` 只在 Android 模拟器里指向宿主机，真机必须填局域网 IP 或 https 域名。

### 直接下载已构建好的安装包

所有二进制统一由 GitHub Actions 编译（`.github/workflows/build-installers.yml`），
产物直接发布到仓库 Release，本地不需要装 Android SDK / MSVC：

| 平台 | Release 资产 |
| --- | --- |
| Android | `BiliLite-0.1.4-Android.apk` |
| Windows | `BiliLite-0.1.4-Windows-Setup.exe` |
| Web + BFF | `bili-lite-web-v0.1.4.tar.gz` / `.zip` |
| iOS | `BiliLite-0.1.4-UNSIGNED.ipa`（编译验证）、`BiliLite-0.1.4-iOS-ADHOC.ipa`（ad-hoc 签名） |
| 源码 | `bili-lite-v0.1.4-src.tar.gz` / `.zip` |

最新发行版：[bili-lite-v0.1.4](https://github.com/llovepeaches/bili-lite/releases/tag/bili-lite-v0.1.4)

手动触发一次全平台构建：

```bash
gh workflow run build-installers.yml -f release_tag=bili-lite-v0.1.4 -f publish=true -f run_ios=true
```

Android APK 使用正式 release 密钥签名（密钥以 Secret 存放，不入库），可覆盖升级。

iOS 需要加 `-f run_ios=true` 才会构建（macOS runner）：

```bash
gh workflow run build-installers.yml -f release_tag=bili-lite-v0.1.4 -f publish=true -f run_ios=true
```

产出 `UNSIGNED.ipa`（编译验证）与 `iOS-ADHOC.ipa`（ad-hoc 自签名，侧载工具可重签）。
**要出能直接装进 iPhone 的 IPA**，还需 Apple Developer Program 与 App Store Connect
API Key（四个 Secret，见 [iOS 打包指南](docs/iOS打包指南.md)），走 TestFlight 分发。
完整的「三道坎 + 三条路径」说明见 [iOS 打包指南](docs/iOS打包指南.md)。

### 版本规则与更新检查

当前版本 **v0.1.4**（`pubspec.yaml` 为 `0.1.4+5`）。后续发版从这里按语义化版本递增，
**应用内显示的版本必须与发布 tag 一致**；从 v0.1.4 起用户可见版本只显示三段号，
不再显示 `+构建号`：

| 来源 | 值 |
| --- | --- |
| `app/pubspec.yaml` | `version: 0.1.4+5`（内部构建号 5） |
| `app/lib/core/app_version.dart` | `kAppVersion = '0.1.4'`、`kAppBuildNumber = 5`、`kAppVersionLabel = '0.1.4'` |
| 自动派生的发布 tag | `bili-lite-v0.1.4` |
| 设置页「关于 / 版本更新」 | 直接读 `kAppVersionLabel`，显示 `0.1.4`，不再手写 |

发版只改 `pubspec.yaml` 与 `app_version.dart` 的两个常量，并同步 workflow input 的
`release_tag` 默认值。CI 的 `Verify version sync` 步骤逐项比对，漏改直接让构建失败——
旧版曾出现「设置页写死 1.4.0 / pubspec 1.6.0 / tag v1.6.0」三处漂移。
`push tag` 触发时 tag 名直接由 `github.ref_name` 取，不必再改 workflow。

**应用内更新检查**：设置页 →「版本更新」卡片，可手动点「检查更新」，启动后每 12 小时
也会自动静默检查一次。数据源是 GitHub Releases 的公开 `releases/latest` 接口，只读取
`tag_name` 与发布页地址，不上传任何本机数据；离线、限流、超时或解析失败只显示
「检查未完成」，绝不误报成「有新版本」。点击「前往下载 / 发布页」用 `url_launcher`
打开系统浏览器。

> **当前仓库为私有**：匿名 `releases/latest` 返回 404，因此私有期间应用内在线检查会停在
> 「检查未完成」，这是预期降级、不是故障；请先用「发布页」按钮查看。后续把仓库转为
> Public 后，同一接口即返回 200，应用内检查自动生效，**无需改代码或重新打包**。
> 详见 [重构说明 §9.4](docs/重构说明.md)。

### 应用图标与启动速度（v0.1.0）

* **图标重绘**：粉→紫渐变 squircle + 白色「bi」字标，替换六端共用的 Flutter 默认蓝色
  「F」。资源由 `app/tool/generate_icons.py` 幂等生成，覆盖 Android（含 adaptive icon）、
  iOS、macOS、Windows `.ico`、Web PWA 全套；应用内 `AppLogo` 同步改为同一套视觉。
  预览见 `docs/preview/app-icon-v0.1.0.png`。
* **启动提速**：`main()` 把本地初始化并行化，并把 BFF 健康探测、官方 OAuth 备用通道
  探活（原先 15s 超时）、OAuth 回调领取与更新检查全部挪到 `runApp()` 之后，各自带
  8s 上限与异常兜底。`test/startup_test.dart` 用计数 HTTP 客户端断言启动关键路径
  **不发起任何网络请求**。

---

## 功能

| 模块 | 内容 |
| --- | --- |
| 首页 | 推荐流（下拉换一批 + 触底加载）、综合热门（分页）、排行榜（21 个分区，**分区浮层「图标 + 名称」网格** + 横向快捷条 + 名次角标） |
| 搜索 | 关键词搜索视频、热词、本地搜索历史、分页与去重 |
| 详情 | **MiniBili 式信息层级**：工具胶囊组 → 播放器 → 详情/评论分段控件 → 标题 → 统计行 → UP 主卡片 → 四连互动栏 → 折叠简介 + 话题标签 → 分 P；宽屏「左详情 + 右评论」双栏 |
| 视频卡片 | **沉浸式**（弹幕数叠在封面左下角，UP 主带头像）/ **紧凑型**两种样式可切换 |
| 我的 | 收藏、观看历史、稍后再看；长按卡片删除、一键清空；全部本地存储，无需登录 |
| 导航 | 底部悬浮玻璃 dock（**滚动时自动收起**）/ 宽屏侧边栏；**入口可增删与排序**；返回键先回首页再退出 |
| 详情 | **应用内播放 + 弹幕**：详情页点封面进播放页，画面直接解码 B 站公开直链，弹幕作为叠加层渲染（开关 / 不透明度 / 字号 / 滚动·顶部·底部轨道）；另有「在官方站点打开」降级入口 |
| 设置 | 浅色 / 深色 / 跟随系统、**液态玻璃开关 / 浓度 / 通透·着色材质 / 动态光晕**、**卡片样式 / 导航入口编辑器 / 滚动收起底栏**、服务状态与健康检查、缓存条目、清空本地数据、**B 站账号（扫码登录 / 退出，高级区含官方 OAuth 2.0 备用通道与授权服务地址）**、数据边界与合规说明 |

**设计取舍**：应用内自建播放器、不加载广告、不做个性化追踪；播放只取 B 站公开的 `playurl` 直链与公开弹幕，不注入登录凭证。
B 站账号登录**主通道是官方 Web 扫码登录**（B 站 App 扫码确认，本机保存 Web 登录 Cookie），
**备用通道**才是开放平台官方 OAuth 2.0 授权码流程，且只使用已授权的只读 scope（`USER_INFO`）。
两路都只用于展示昵称 / 头像，不代用户执行任何写操作；评论 / 投币等观看侧互动仍在官方客户端完成。
数据状态在 UI 上以「B 站实时 / 实时 / 缓存 / 离线」标签透明展示，设置页可见当前连接方式与访客身份。

页面效果截图见 [`docs/preview/`](docs/preview/)；六个平台的构建命令见 [`docs/多端构建.md`](docs/多端构建.md)。

---

## 液态玻璃视觉（v1.2 · iOS 26 式）

按 iOS 26 / 26.1 的 Liquid Glass 重做：**不是半透明白色亚克力板，而是内部近乎全透、靠沿边缘的折射高光定义形状的透镜材质**。
整套光学层自绘，**没有引入任何第三方 UI 依赖**。

| 层 | 实现 | 代码位置 |
| --- | --- | --- |
| 可折射背景 | 淡粉 / 淡蓝宽色带 + 柔光斑 + 斜向掠光，作为透镜背后的内容；光晕缓慢漂移，48 步量化避免 Web 每帧重绘全屏渐变 | `widgets/glass.dart` → `GlassBackdrop` |
| 边缘外部高光 | 沿形状轮廓一圈明亮高光，左上与右下最强（镜面反射），两端亮、中段带色偏 | `GlassPalette.rim()` / `_LensPainter` |
| 内侧折射环 | 由外向内的多层亮度梯度，模拟光线在玻璃边缘被弯折、聚集（lensing）；边缘一侧偏青、一侧偏粉形成色散 | `_LensPainter` / `dispersion` |
| 镜面亮斑 | 高光沿轮廓缓慢流动；由全 App 唯一的 `GlassClock` 驱动，只有侧栏 / dock / 工具条等大面积玻璃订阅，卡片级玻璃保持静态 | `GlassClock` / `_specularArc` |
| **真实背景采样** | 导航级玻璃（底栏 / 顶栏 / 侧栏）真的去采样背后已绘制的内容并做模糊，而不是自己画渐变假装玻璃 | `RenderLensBackdrop` / `GlassSample` |
| **透镜折射** | 采样结果再经仿射矩阵放大，等效凸透镜把底下的内容顶大；支点取玻璃中心并换算到滤镜坐标空间 | `GlassOptics.magnify` |
| **表面层** | 折射结果之上铺一层半透明白，模拟厚玻璃的漫反射表面 | `GlassConfig.surface` |
| **共享 backdrop** | 底栏的胶囊与圆形按钮引用**同一份**背景采样（一次 `BackdropFilter` + 并集裁剪 + 各自透镜），因此两件玻璃看到的画面完全一致、不会互相采样 | `liquid_dock.dart` → `_GlassDock` |
| **色相染色** | 玻璃表面叠一层 `BlendMode.hue` 的冷蓝染色（半透明源），让材质像一块有色的实体而不是无色玻璃 | `GlassConfig.hue / hueMix / hueAlpha` |
| **弹簧按压** | 圆形玻璃按下时用 `spring(ratio 0.5 / stiffness 300)` 放大自身形状（不是只放大图标），松手过冲回弹 —— 液态手感最容易被感知到的一环 | `GlassPress` |
| 胶囊控件语言 | 芯片、徽章、时长角标、Tab 指示器、选中项统一为全圆角胶囊；封面与容器同心圆角 | `GlassPill` / `GlassChip` / `shell_page.dart` |
| 内容让位 | 卡片内部填充压到极薄，标题、UP 主、统计数据直接压在透镜上，并加轻微文字阴影保证可读性 | `widgets/video_card.dart` |

**两档材质**（对应 iOS 26.1 的 Clear / Tinted）：

| 档位 | 效果 | 适用 |
| --- | --- | --- |
| **通透 Clear**（默认） | 内部几乎全透，背景色带直接穿过玻璃，只靠边缘高光与折射环勾勒形状 —— 最接近 iOS 原生观感 | 主推，浅色 / 深色都成立 |
| **着色 Tinted** | 抬高材质不透明度，形状更实、文字对比度更高，但仍保留边缘高光 | 强光环境、可读性优先时 |

**可调**：设置 →「液态玻璃」可一键关闭材质、切换**轻微 / 标准 / 浓郁**三档浓度、切换 Clear / Tinted、开关动态光晕，全部持久化在 `SharedPreferences`。关闭后所有组件退回不透明卡片与纯色背景，低配设备也能流畅用。

**共享 backdrop 的实测依据**（原生 Linux + Xvfb 读截图像素）：两块**重叠**的兄弟玻璃会互相采样 —— 上层实测读到下层的纯红 `(255,0,0)`；嵌套 `BackdropFilter` 的内层采样的是**外层的输出**（条纹周期正好翻倍）；而嵌套下内层透镜的 src/dest 仍在**根空间**（实测暗段中心 420，与理论值 `2×460−500` 精确吻合）。所以底栏采用「一次采样 + 并集裁剪 + 各自透镜」的结构。

**平台差异**：**两端都开**真实 `BackdropFilter` 背景采样 —— 底栏、顶栏、侧栏这三件大面积玻璃走「导航级」模糊（`navBlur`），卡片级模糊（`blur`）只在原生端开（Web 上一页几十张卡片同时做 backdrop 采样会明显掉帧）。
Web 的 html renderer 其实**支持** `BackdropFilter`：引擎把它落成 CSS `backdrop-filter: blur(Npx)`（实测 DOM 里确实生成了 `flt-backdrop-filter` 且带 backdrop-filter 样式），但 CSS 只认 blur —— 滤镜链里一旦混入 matrix/compose，整个滤镜会被丢弃、玻璃退化成一层黑纱。所以**真·透镜折射（把背景顶大）只在原生端生效**，Web 端退化为纯 blur + 手绘折射环。

镜面时钟相位量化成 24 步，且刻意把光学 painter 与内容合并进**同一个渲染对象**：Flutter Web html renderer 遇到 `Path.computeMetrics()` 或独立 `Positioned` 绘制层会切出 `z-index:-1` 的 canvas，把同容器里的文字盖到背景下面。浅色与深色各有独立调色板，Tab 选中态使用专用深粉色保证对比度。

---

## 接口清单

所有响应统一为 `{ code, message, data, meta:{ source, stale, ts } }`，`source` 取值 `live | cache | mock | static`。

| 端点 | 参数 | 上游 |
| --- | --- | --- |
| `GET /api/health` | — | 本地状态 |
| `GET /api/meta` | — | 分区表 / 评论排序 |
| `GET /api/feed` | `ps`, `fresh_idx` | `/x/web-interface/index/top/feed/rcmd` |
| `GET /api/rank` | `rid` | `/x/web-interface/ranking/v2` |
| `GET /api/popular` | `pn`, `ps` | `/x/web-interface/popular` |
| `GET /api/search` | `keyword`, `page` | `/x/web-interface/search/type` |
| `GET /api/video` | `bvid` 或 `aid` | `/x/web-interface/view` |
| `GET /api/reply` | `aid`, `pn`, `ps`, `sort` | `/x/v2/reply` |
| `GET /api/img` | `url` | 图片反向代理（仅放行 `*.hdslb.com`） |

缓存 TTL：推荐 60s、排行榜 5min、热门 3min、搜索 2min、详情 10min、评论 60s。

**扫码登录代理端点**（`/api/qr/*`，仅 Web 端使用，由 `server/src/qr_proxy.js` 纯转发，全部 `Cache-Control: no-store`）：

| 端点 | 方法 | 作用 |
| --- | --- | --- |
| `/api/qr/generate` | GET | 转发 `passport.bilibili.com/x/passport-login/web/qrcode/generate`，返回 `{ url, qrcodeKey }` |
| `/api/qr/poll` | GET | `?key=` 转发 `qrcode/poll`，把业务码 `86101 / 86090 / 86038 · 86039 / 0` 归并为 `waiting / scanned / expired / success`；成功时从 `Set-Cookie` 与回调 URL 提取登录 Cookie |
| `/api/qr/nav` | POST | 带 Cookie 转发 `api.bilibili.com/x/web-interface/nav`，返回 `{ mid, name, face, vipLabel }` |

代理不缓存、不落盘、不打印 Cookie；`SESSDATA` 里的 `%2C` / `%2A` 等百分号编码原样保留，
避免被 `URLSearchParams` / `Uri.queryParameters` 自动解码破坏。
原生端（Android / iOS / 桌面）**完全不经过这些端点**，由 `app/lib/data/qr_login_api.dart` 直连 B 站。

**官方 OAuth 端点（备用通道）**（`/api/oauth/*`，由 `server/src/oauth.js` 独立分发，全部 `Cache-Control: no-store`）：

| 端点 | 方法 | 作用 |
| --- | --- | --- |
| `/api/oauth/config` | GET | 公开配置：是否已配置、scope、缺失的环境变量、是否演示模式。**永不返回 client_secret** |
| `/api/oauth/begin` | POST | 生成一次性 `state`（5 分钟），返回 B 站官方授权页 URL |
| `/api/oauth/callback` | GET | 官方回调：校验 state → 服务端换 token → 一次性 ticket（60 秒）；Web 302 回 App，原生返回可复制的授权码页 |
| `/api/oauth/exchange` | POST | 用 ticket 领取 token，领取即销毁 |
| `/api/oauth/refresh` | POST | 用 `refresh_token` 续期（官方每个 refresh_token 只能用一次） |
| `/api/oauth/me` | POST | 签名 2.0 调用 `member.bilibili.com/arcopen/fn/user/account/info`（`USER_INFO`） |
| `/api/oauth/scopes` | POST | 查询用户已授权权限点 |

官方开放接口签名 2.0：`x-bili-*` 六个公共头按 ASCII 字典序拼 `key:value`（`\n` 连接、无尾随换行），
以 `app_secret` 做 HMAC-SHA256 填入 `Authorization`；GET / 空 body 用空串 MD5 `d41d8cd9…8427e`。
拼接规则已用 B 站官方公开签名样例验证，见 `server/tool/verify_oauth_sign.js`。

---

## 目录

```
bili-lite/
├── README.md
├── docs/
│   ├── 多端构建.md          # 六个平台各自的构建与真机调试命令
│   ├── 重构说明.md          # 四轮重构 / 改造的逐条问题清单与改进方案
│   └── preview/             # 页面效果截图（含 6 张官方 OAuth 备用链路）
├── server/                  # BFF（零依赖）
│   ├── package.json
│   ├── .env.example
│   ├── src/
│   │   ├── index.js         # 路由、静态托管、图片代理、/api/oauth/* 与 /api/qr/* 分发
│   │   ├── bili.js          # 上游客户端、身份、缓存、stale-on-error
│   │   ├── normalize.js     # 5 套上游字段 → 统一模型（含 playurl / 弹幕）
│   │   ├── qr_proxy.js      # Web 扫码登录同源代理：generate / poll / nav
│   │   ├── oauth.js         # 官方 OAuth 2.0（备用）：state/ticket、换 token、签名 2.0
│   │   ├── mock.js          # 降级逻辑
│   │   └── mock-data.json   # 真实数据快照（2026-11-09）
│   └── tool/                # 签名向量自检 + 授权链路自检
└── app/                     # Flutter 工程（六平台骨架齐全）
    ├── pubspec.yaml         # 仅 5 个运行时依赖（含 qr_flutter 4.0.0）
    ├── tool/                # verify_live.dart / verify_web.cjs / verify_oauth_web.cjs
    ├── web/                 # PWA 配置、启动占位页
    ├── android/ ios/ linux/ macos/ windows/
    └── lib/
        ├── main.dart / app.dart   # 启动时初始化 ServerConfig / qrSession / authSession，消费 ?oauth_ticket=
        ├── core/            # 配置、令牌、分区表、路径表、存储门面、导航、主题
        │   ├── glass_theme.dart  # GlassConfig / GlassScope / GlassClock / GlassPalette
        │   ├── tokens.dart       # 设计令牌：状态色 / 字号 / 圆角 / 间距 / 取色扩展
        │   ├── storage.dart      # LocalStore：本地持久化门面 + 能力探测
        │   ├── server_config.dart # 运行时 BFF 地址（账号高级区可改，编译期 BFF_URL 作默认）
        │   ├── partitions.dart   # 分区表单一数据源（含各分区图标与主色）
        │   ├── api_paths.dart    # 接口路径单一数据源（纯 Dart）
        │   ├── nav_section.dart  # 导航项枚举（首页 / 搜索 / 我的 / 设置）
        │   ├── card_style.dart   # 卡片样式枚举（沉浸式 / 紧凑型）
        │   ├── route_args.dart   # 纯数据的路由名与参数类
        │   ├── navigation.dart   # 详情跳转与收藏切换的统一入口
        │   └── oauth_launcher.dart  # Web 同页导航 / 原生系统浏览器（条件导出）
        ├── router/          # app_routes.dart：集中路由表 AppRouter.generate
        ├── data/            # models / api_client / bili_direct / repository
        │                    #   / qr_login_api（扫码登录主通道）/ oauth_api（备用通道）
        ├── state/           # 主题+玻璃 / 本地库 / 搜索历史 / preferences / 单例
        │                    #   / qr_session（扫码登录态，优先）/ auth_session（官方 OAuth 备用）
        ├── widgets/         # 封面、卡片、网格、骨架屏、状态视图、glass、统一 Logo/对话框/页头
        │                    #   / partition_sheet（分区浮层）/ segmented_switch（分段控件）
        └── features/        # shell / home / search / detail / library / player / account / settings
                             #   account/：扫码主卡片、二维码弹层、统一身份门面、
                             #             运行时授权服务设置、折叠的官方 OAuth 备用卡片
                             #   每个 feature 拆 controller + view 两层
```

---

## 环境变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `PORT` | `8787` | BFF 端口 |
| `HOST` | `0.0.0.0` | 监听地址 |
| `MOCK_MODE` | `0` | 置 `1` 完全使用离线快照 |
| `UPSTREAM_TIMEOUT` | `10000` | 上游超时（ms） |
| `WEB_DIR` | `app/build/web` | Flutter Web 产物目录 |
| `BFF_URL` | 自动 | **Flutter 编译参数**：`--dart-define=BFF_URL=http://<IP>:8787`，让原生端改走指定 BFF；官方 OAuth 也走这个地址。**运行时可在账号面板「授权服务」里覆盖**（键 `bili_lite_bff_url`，优先级更高，打好的安装包也能改）；扫码登录不依赖它 |
| `OFFLINE` | `0` | **Flutter 编译参数**：置 `1` 完全不发网络请求，纯内置快照；默认关闭（在线直连） |
| `PUBLIC_BASE_URL` | `http://<host>` | 对外可访问的根地址，用于拼接回调与演示授权页链接 |
| `BILI_CLIENT_ID` | 空 | **官方开放平台 Client ID**（公开值，可下发给客户端） |
| `BILI_CLIENT_SECRET` | 空 | **官方开放平台 Secret**：只在 BFF 进程内使用，绝不进客户端 / 日志 / Git |
| `BILI_REDIRECT_URI` | 空 | 与开放平台备案的「授权回调域」完全一致，指向 `/api/oauth/callback` |
| `BILI_OAUTH_SCOPES` | `USER_INFO` | 申请并已审核通过的 scope，逗号分隔 |
| `BILI_OAUTH_SANDBOX` | `0` | **仅本地自检**：置 `1` 启用模拟授权页，不连接 B 站、不产生真实凭证；生产必须为 `0` |

建议在受信任终端注入密钥，避免进入 shell 历史：

```bash
read -rsp 'BILI_CLIENT_SECRET: ' BILI_CLIENT_SECRET; export BILI_CLIENT_SECRET; echo
```

---

## B 站账号登录

登录**已实现且开箱即用**，提供两条互相独立的链路，**不登录也能浏览全部内容**。

| 能力 | 实现范围 | 交互方式 | 数据存储边界 | 合规判定 |
| --- | --- | --- | --- | --- |
| **扫码登录（主通道）** | ✅ **已实现**：B 站官方 Web 扫码登录 `passport.bilibili.com/x/passport-login/web/qrcode/*` | **首页顶栏账号按钮 / 「我的」页账号卡片 → 「扫码登录」** → 弹层显示二维码 → 手机 B 站 App 扫码并确认 → 每 2 秒轮询，成功后自动关闭弹层；可「刷新二维码」/「取消」 | 本机持久化 `SESSDATA` / `bili_jct` / `DedeUserID` 等 Web 登录 Cookie 与 `mid` / 昵称 / 头像 | 走 B 站官方登录页，用户本人扫码授权；**不接触账号密码**，Cookie 只发往 `bilibili.com`，不上传第三方 |
| 官方 OAuth 2.0（备用） | ✅ 已实现：2025-03 后的官方授权页 `account.bilibili.com/pc/account-pc/auth/oauth` | 账号面板展开「官方 OAuth 与授权服务（高级 / 可选）」→ 系统浏览器 / 同页打开官方授权页 → 同意 → 回调自动完成登录；原生端也可粘贴回调页的一次性授权码 | 本机持久化 `access_token`、`refresh_token`、过期时间、scope、openid / 昵称 / 头像 | 官方授权码流程；不接触密码 / Cookie / `SESSDATA` / `bili_jct` |
| 凭证续期 | ✅ 官方 OAuth 按 `refresh_token` 端点续期；扫码通道 Cookie 失效时重新扫码 | 启动时临期自动续期，也可手动点「刷新凭证」 | 新 token 覆盖本地旧值；每个 `refresh_token` 只用一次 | 官方明确 `expires_in` 是 UTC 绝对时间戳，按秒解析后再转毫秒 |
| 退出登录 | ✅ 清除本机全部凭证 | 确认对话框 → **扫码 Cookie 与官方 OAuth token 一并删除** | 不留半套凭证；B 站侧授权需到官方账号设置里解除 | 官方会在用户解除授权时推送事件，本项目未接入推送，故在 UI 明确提示 |
| 应用内播放 | ✅ **已实现**：自建播放器（Web 用同源 `<video>`，Android / iOS 用 `video_player`） | 详情页点封面 → 应用内播放页；画面直接解码 B 站 mp4，不跳出应用 | 服务端 `/api/stream` 代取视频流（带 Referer 与访客身份，绕过防盗链与 CORS）；不注入任何登录凭证 | 只调用 B 站公开的 `playurl` 接口取公开直链，不触碰账号态内容 |
| 弹幕 | ✅ **已实现**：解析 B 站 `dm/list.so` 的 deflate 压缩 XML | 播放页叠加层，支持开关 / 不透明度 / 字号；滚动、顶部固定、底部固定三种模式各有独立轨道 | 服务端解压后转 JSON（Web），原生端用 `ZLibDecoder(raw: true)` 本地解压 | 只读公开弹幕接口，不发送任何弹幕 |
| 官方播放器（备用） | ✅ B 站官方[站外外链播放器](https://player.bilibili.com) | 播放页「在官方站点打开」入口 | 只传 `bvid` 与分 P | 作为内置播放失败时的降级路径保留 |
| 评论 / 投币 / 点赞 | **未实现**，提供「评论 / 投币」入口 | 唤起官方客户端 / 网页，在官方完成互动 | 不代持凭证、不调用写接口 | 已开放 scope 全是创作者与账号侧只读能力，**不含观看侧互动**；即便扫码登录持有 Cookie，模拟 Web 写接口仍需逆向 WBI 签名，属于协议禁止的自动化访问，本项目明确不做 |

**为什么把扫码登录设为主通道**：官方 OAuth 2.0 的 `client_secret` 只能留在一个持有密钥的服务端，
而独立安装包（APK / exe / Web 静态产物）里没有这个服务端；`10.0.2.2:8787` 又只是 Android 模拟器的专用别名，
真机不可达，release 包原先还禁用了明文 HTTP。三层叠加的结果就是旧版账号面板显示「授权服务不可用」，
用户看不到任何可用的登录方式。扫码登录直连 B 站官方登录域，不需要开放平台凭证、不需要自建后端，
因此成为默认入口；官方 OAuth 收进折叠高级区，只服务已自建或部署授权服务的场景。
即便 `AuthSession.refreshConfig()` 探活失败，只要扫码登录态有效，UI 仍显示「已登录」（由 `AccountIdentity` 合并两路身份）。

### 启用官方 OAuth 备用通道

官方 OAuth 要求开发者资质，代码无法代你申请。四步：

1. 在 [openhome.bilibili.com](https://openhome.bilibili.com) 完成开发者入驻、创建应用；
2. 申请并等待 `USER_INFO` 等 scope 审核通过；
3. 把 `BILI_REDIRECT_URI`（形如 `https://你的域名/api/oauth/callback`）填入应用的「授权回调域」，**必须与环境变量一字不差**；
4. 在受信任终端注入 `BILI_CLIENT_ID` / `BILI_CLIENT_SECRET` / `BILI_REDIRECT_URI` 后重启 BFF，
   并在账号面板「授权服务」里填上这个 BFF 地址（真机填局域网 IP 或 https 域名，运行时生效）。

未配置时 `/api/oauth/config` 返回 `configured: false`，备用卡片显示「本通道为可选备用」并提示日常用扫码登录，
**不会伪造登录按钮或假账号，也不会遮住扫码登录入口**。授权页 2025 年 3 月已迁移，
旧的 `passport.bilibili.com/register/pc_oauth2.html` 不再使用。

### 本地存储明细

| 位置 | 键 | 内容 |
| --- | --- | --- |
| `SharedPreferences`（Web → localStorage，原生 → 平台偏好） | `bili_lite_qr_cookie` / `bili_lite_qr_user` | **扫码登录主通道**：B 站 Web 登录 Cookie（`SESSDATA` / `bili_jct` / `DedeUserID` 等）与 `mid` / 昵称 / 头像，仅本机 |
| 同上 | `bili_lite_bff_url` | 运行时填写的授权服务地址（留空恢复默认） |
| 同上 | `bili_lite_oauth_access_token` / `bili_lite_oauth_refresh_token` | 官方 OAuth 备用通道凭证，仅本机 |
| 同上 | `bili_lite_oauth_expires_at` / `bili_lite_oauth_scopes` | 过期时间（毫秒 UTC）、已授权权限点 |
| 同上 | `bili_lite_oauth_user` | `USER_INFO` 的 openid / 昵称 / 头像 URL |
| BFF 进程内存 | `state`（5 分钟）/ `ticket`（60 秒） | 官方 OAuth 一次性数据，消费即删，**不落盘** |
| BFF 环境变量 | `client_secret` | 只在服务端进程内，不进响应 / 日志 / Git |

**明确不存**：账号密码、`client_secret`、授权码 `code`；官方 OAuth 通道不存任何 Cookie。
**扫码登录会保存上述 Web 登录 Cookie**——这是它与官方 OAuth 最本质的区别，账号面板「本地数据边界」里已如实标注。
Cookie 只随请求发往 `*.bilibili.com`，不上传第三方；Web 端的 `/api/qr/*` 代理不缓存、不落盘、不打印 Cookie。
`SharedPreferences` 不是硬件加密存储，且扫码 Cookie 的敏感度高于 OAuth token —— 真机发布建议把凭证迁到
iOS Keychain / Android Keystore。
收藏 / 历史 / 稍后再看 / 搜索历史继续留在本机，**不关联账号、不上传**。

> **关于跨端持久化**：本地存储统一走 `app/lib/core/storage.dart` 的 `LocalStore` 门面，
> 启动时主动探测插件是否真的可用，结果通过设置页如实展示。
> `shared_preferences` 需 **≥ 2.1.0**（工程已锁定 `^2.1.0`）才有完整的六端原生实现
> （Windows / Linux / macOS 在 2.0.x 上是缺失的）。若探测失败，会退化为
> 「仅本次会话有效」并明确提示，而不是静默丢数据。

### 演示授权模式（仅本地自检 · 官方 OAuth 备用通道）

```bash
cd server && BILI_OAUTH_SANDBOX=1 node src/index.js
```

用于在没有开放平台凭证时验证**备用通道**「授权码 → 换 token → 本地持久化 → 续期 → 退出登录」全链路。
它用本地模拟授权页代替官方页，**不连接 B 站、不产生真实凭证**，UI 顶部有醒目的「非 B 站官方」标签，
生产必须保持 `BILI_OAUTH_SANDBOX=0`。扫码登录主通道走真实 B 站登录页，不受这个开关影响。链路自检：

```bash
cd server && npm run verify:oauth          # 签名向量 + 授权流程，30 项
cd app && NODE_PATH=$(npm root -g) node tool/verify_oauth_web.cjs   # Web 端到端，20 项
```

**为什么扫码登录只用来读资料、不做写接口**：扫码登录确实会在本机保存 Web 登录 Cookie，
但项目只用它们调用 `/x/web-interface/nav` 读取昵称 / 头像等只读身份信息，
**不逆向 WBI 签名、不模拟 Web 写接口、不代用户点赞 / 投币 / 发评论**。
后者会触发风控、可能导致账号受限，也与
[开放平台开发者服务协议](https://open.bilibili.com/agreement/developer-service)
「不得以自动程序获取服务 / 数据」冲突。因此本项目宁可少几项互动功能，也不做这层。

---

## 重构记录

本工程完成过五轮重构 / 改造（另有多轮视觉与光学专项改造，详见 [docs/重构说明.md](docs/重构说明.md)）：

1. **第一轮 · 全项目收敛** —— 统一存储门面、设计令牌收敛、分区表去重、重复组件抽取、
   跨端明文流量策略收紧、深色模式对比度修复、分页与生命周期缺陷修复等。
2. **第二轮 · 参考 MiniBili 与 PiliPlus 的界面与架构改造** —— 建立集中路由层、
   全部页面拆 controller/view 两层、沉浸式视频卡片、分区浮层菜单、详情页信息层级重排、
   可配置导航与滚动隐藏底栏；同时修复了「首页整页蒙白纱」「卡片显示 `[object Object]`」
   「详情页在桌面浏览器上读不到内容」三个真实缺陷。
3. **第三轮 · 应用内播放、弹幕与刷新修复** —— 自建播放器（Web DOM `<video>` + 弹幕 canvas /
   原生 `video_player`）、解析 deflate 压缩弹幕 XML、修复「换一批」永远拿同一批内容的缓存游标缺陷、
   把账号入口前置到首页顶栏与「我的」页；同时把 Android `compileSdk` 抬到 33 修掉 CI AAR metadata 失败。
4. **第四轮 · 扫码登录主通道与授权服务降级** —— 新增 B 站官方 Web 扫码登录（原生直连 / Web 走同源代理），
   把必须依赖 `client_secret` 服务端的官方 OAuth 收进折叠高级区，新增运行时 BFF 地址配置、统一账号身份门面、
   Android 真机明文放行与 Cookie 数据边界说明。修掉了独立安装包里「授权服务不可用、无法登录」的根因。
5. **第五轮 · 品牌图标、启动提速、版本基线与更新检查** —— 重绘六端图标并提供幂等生成脚本；
   把启动关键路径上的网络请求全部移出 `runApp()` 之前；版本基线重置为 v0.1.0，建立
   `app_version.dart` 单一真源与 CI 强制同步校验；设置页新增基于 GitHub Releases 的更新检查。

逐条的问题清单与改进方案见 **[docs/重构说明.md](docs/重构说明.md)**。

## 已知限制

- **评论条数**：未登录的访客身份下，B 站 `/x/v2/reply` 通常只开放少量热评（实测 3 条，`is_end=true`）。已验证 WBI 签名的新接口结果相同，属于上游策略而非实现问题。
- **应用内播放的已知边界**：Web 端用同源 `<video>` + 弹幕 canvas，Android / iOS 用 `video_player`；桌面端（Windows / macOS / Linux）没有对应插件实现，会明确提示改用系统播放器。清晰度目前固定 `qn=64`（720P），大会员 / 高画质内容仍需在官方站点登录观看；本应用只取公开 `playurl` 直链，不注入登录凭证、不解析受限内容。
- **接口稳定性**：上游可能调整字段或加风控；Web 链路的适配点是 `server/src/normalize.js`，原生直连链路是 `app/lib/data/bili_direct.dart`，两处规则同构，改动需同步；所有接口都有真实快照兜底。
- **官方 OAuth 备用通道依赖授权服务端**：`client_secret` 不能放进客户端（APK / exe / Web 产物都可被反编译），所以这一路必须连到持有密钥的 BFF。`10.0.2.2:8787` 只在 Android 模拟器有效，真机请在账号面板「授权服务」里填局域网 IP 或 https 域名（运行时生效）。**扫码登录主通道不受此限制**；不登录也不影响浏览内容。
- **登录态不是硬件加密**：`SharedPreferences` 在当前依赖约束下是最简方案；扫码登录保存的 Web Cookie 敏感度高于 OAuth token，生产发布更应接 Keychain / Keystore。跨端持久化依赖 `shared_preferences ≥ 2.1.0`（六端原生实现齐全），版本被降到 2.0.x 时桌面端会退化为会话内存态 —— 工程已锁定 `^2.1.0` 并在设置页显示实际探测结果。
- **解除授权推送未接入**：官方会在用户主动解除授权或注销时向厂商推送消息，本项目没有消息接收端点，因此本地可能残留已失效 token；调用开放接口返回失效时请重新授权，或点「退出登录」清除。
- **scope 由开放平台审核决定**：授权页只展示已审核通过的权限点；新增 scope 后已授权用户必须重新授权，代码里通过 `BILI_OAUTH_SCOPES` 配置，不会自行扩张权限。
- **工具链**：本工程在 Flutter 3.0 / Dart 2.17 上验证通过，运行时依赖刻意压到 5 个（`qr_flutter 4.0.0` 是最后一个兼容 Dart 2.17 的二维码库版本），较新 SDK 同样可用。
- **Web 玻璃模糊**：html renderer **支持** `BackdropFilter`（引擎落成 CSS `backdrop-filter: blur()`），所以底栏 / 顶栏 / 侧栏两端都开真实背景采样；卡片级模糊只在原生端开。CSS 只认 blur，**真·透镜折射（把背景顶大）只在原生端生效** —— Web 端滤镜链里混入 matrix 会被整体丢弃、玻璃退化成黑纱。光学层与内容合并为单一渲染对象，避免 html renderer 的负 z-index canvas 盖住文字。若改用 `flutter build web --web-renderer canvaskit`，需自行评估首包体积与字体加载。
- **玻璃不能自带 `RepaintBoundary`**：Flutter 会为该子树建立独立渲染表面，backdrop 采样只能看到同一 surface 内的内容 —— 给玻璃套一层等于把背景全隔离掉，玻璃会退化成一块不透明浅色板（原生实测：同一画面左右对照，套 boundary 的一侧完全看不到背后的黑条）。透镜支点因此不能靠「套 boundary 换坐标系」解决，改为在 paint 阶段用 `getTransformTo(最近一层 RepaintBoundary 祖先)` 把玻璃中心换算到滤镜坐标空间（`RenderLensBackdrop`）。
- **色相染色不能用不透明源**：`BlendMode.hue` 取源的色相、目标的饱和度与明度。若照 Compose 参考直接用不透明色做 Hue 源，色相会被**整体**接管，玻璃退化成一块不透明蓝色板、背景一点也透不出来（原生截图已确认）。因此染色源本身降为半透明（`hueMix = 0.22 × 强度`），只部分接管色相，背景明暗层次得以保留。
- **着色 Tinted 档偏保守**：为保证文字可读性抬高了不透明度，观感比通透 Clear 更接近实色卡片；想看最典型的 iOS 26 透镜效果请用默认的通透档。

---

## 合规提示

请遵守哔哩哔哩用户协议、robots 规则与相关数据法规：**仅供学习与个人使用，勿商用、勿高频抓取、勿绕过登录鉴权获取受限内容**。
两种登录都只读取用户本人的资料（昵称 / 头像）：扫码登录走 B 站官方 Web 登录页，用户扫码确认后把 Cookie 留在本机、
只用于调用只读的 `/x/web-interface/nav`；官方 OAuth 走授权码流程，不抓取 Web 登录态、不把 token 用于未授权 scope。
两路都**不逆向 WBI 签名、不解析受限播放地址、不代用户执行需要登录的写操作**。
收藏 / 历史 / 搜索历史与两类登录凭证全部留在设备本地，不上传、不共享、不关联第三方。
`client_secret` 只在授权服务端环境变量里，请勿提交到代码仓库或写进客户端构建产物。
