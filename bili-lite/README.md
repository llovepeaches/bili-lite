# Bili Lite · 简洁的哔哩哔哩第三方多端客户端

一套代码覆盖 **Android / iOS / Web / Windows / macOS / Linux**，基于哔哩哔哩公开 Web 数据，
只保留「看内容」这件事：推荐、热门、排行榜、搜索、视频详情与评论，以及纯本地的收藏 / 历史 / 稍后再看。

> 非官方项目，仅供学习与个人使用，与哔哩哔哩官方无任何关联。

---

## 一眼看懂

```
┌──────────────────────────────────────────────────────────────┐
│  Flutter App（一套 Dart 代码，六端共用）                        │
│  首页推荐/热门/排行榜 · 搜索 · 详情+评论 · 我的 · 设置           │
│  液态玻璃：iOS 26 式透镜 + 边缘折射高光 + Clear / Tinted 双材质  │
│  自适应布局：<700px 底部导航 / ≥700px 侧栏；2~5 列网格           │
└──────────┬──────────────────────────────┬──────────────────────┘
           │ Web：同源 REST /api/*         │ 原生端：HTTPS 直连
┌──────────▼───────────────────────────┐  │
│  Node BFF（零依赖，node src/index.js）│  │ Dart 直连客户端
│  ① spi 访客身份 + UA/Referer 注入     │  │ bili_direct.dart
│  ② 5 套上游字段归一为 Video/Comment   │  │ 同一套归一规则
│  ③ 缓存 + stale-on-error + 快照降级   │  │ 同一套访客身份
│  ④ 图片代理 ⑤ 托管 Flutter Web 产物   │  │ 进程内 TTL 缓存
└──────────┬───────────────────────────┘  │
           │ HTTPS                        │ HTTPS
┌──────────▼──────────────────────────────▼───────────────────┐
│  api.bilibili.com 公开 Web 接口                                │
│  rcmd / popular / ranking v2 / search / view / reply / spi     │
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

**独立安装包不需要上面这个服务**：Android APK / Windows exe 会自行直连 B 站公开接口拿实时数据，
只有连不上时才降级到内置的 `assets/offline.json`。真机调试若想改回走本机 BFF，
用 `flutter run --dart-define=BFF_URL=http://<电脑IP>:8787`；完全禁用联网则加 `--dart-define=OFFLINE=1`。

---

## 功能

| 模块 | 内容 |
| --- | --- |
| 首页 | 推荐流（下拉换一批 + 触底加载）、综合热门（分页）、排行榜（21 个分区切换 + 名次角标） |
| 搜索 | 关键词搜索视频、热词、本地搜索历史、分页与去重 |
| 详情 | 封面、完整统计数据、UP 主、可展开简介、分 P 列表、热评 / 最新排序、子回复预览 |
| 我的 | 收藏、观看历史、稍后再看；长按卡片删除、一键清空；全部本地存储，无需登录 |
| 设置 | 浅色 / 深色 / 跟随系统、**液态玻璃开关 / 浓度 / 通透·着色材质 / 动态光晕**、服务状态与健康检查、缓存条目、清空本地数据、合规说明 |

**设计取舍**：播放交由 B 站官方外链播放器、不加载广告、不做个性化追踪、不持有任何登录凭证。
点击封面在应用内打开官方播放器；评论 / 投币等需要账号的互动回官方客户端完成。
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
| 胶囊控件语言 | 芯片、徽章、时长角标、Tab 指示器、选中项统一为全圆角胶囊；封面与容器同心圆角 | `GlassPill` / `GlassChip` / `shell_page.dart` |
| 内容让位 | 卡片内部填充压到极薄，标题、UP 主、统计数据直接压在透镜上，并加轻微文字阴影保证可读性 | `widgets/video_card.dart` |

**两档材质**（对应 iOS 26.1 的 Clear / Tinted）：

| 档位 | 效果 | 适用 |
| --- | --- | --- |
| **通透 Clear**（默认） | 内部几乎全透，背景色带直接穿过玻璃，只靠边缘高光与折射环勾勒形状 —— 最接近 iOS 原生观感 | 主推，浅色 / 深色都成立 |
| **着色 Tinted** | 抬高材质不透明度，形状更实、文字对比度更高，但仍保留边缘高光 | 强光环境、可读性优先时 |

**可调**：设置 →「液态玻璃」可一键关闭材质、切换**轻微 / 标准 / 浓郁**三档浓度、切换 Clear / Tinted、开关动态光晕，全部持久化在 `SharedPreferences`。关闭后所有组件退回不透明卡片与纯色背景，低配设备也能流畅用。

**平台差异**：原生端（Android / iOS / 桌面）对大面积玻璃条启用真实 `BackdropFilter` 背景模糊；Web 的 html renderer 下关闭模糊，改用 Canvas 渐变、边缘折射环与镜面亮斑模拟透镜 —— 20+ 张卡片同时做 backdrop-filter 会明显掉帧。
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

---

## 目录

```
bili-lite/
├── README.md
├── docs/
│   ├── 多端构建.md          # 六个平台各自的构建与真机调试命令
│   └── preview/             # 14 张页面效果截图
├── server/                  # BFF（零依赖）
│   ├── package.json
│   ├── .env.example
│   └── src/
│       ├── index.js         # 路由、静态托管、图片代理
│       ├── bili.js          # 上游客户端、身份、缓存、stale-on-error
│       ├── normalize.js     # 5 套上游字段 → 统一模型
│       ├── mock.js          # 降级逻辑
│       └── mock-data.json   # 真实数据快照（2026-11-09）
└── app/                     # Flutter 工程（六平台骨架齐全）
    ├── pubspec.yaml         # 仅 4 个依赖
    ├── web/                 # PWA 配置、启动占位页
    ├── android/ ios/ linux/ macos/ windows/
    └── lib/
        ├── main.dart / app.dart
        ├── core/            # 配置、主题、透镜调色板、格式化、响应式断点
        │   └── glass_theme.dart  # GlassConfig / GlassScope / GlassClock / GlassPalette
        ├── data/            # models / api_client / repository
        ├── state/           # 主题+玻璃外观+服务状态 / 本地库 / 全局单例
        ├── widgets/         # 封面、卡片、网格、骨架屏、状态视图
        │   └── glass.dart        # 可折射背景 + 透镜光学层 + 全部玻璃组件
        └── features/        # shell / home / search / detail / library / settings
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
| `BFF_URL` | 自动 | **Flutter 编译参数**：`--dart-define=BFF_URL=http://<IP>:8787`，让原生端改走指定 BFF |
| `OFFLINE` | `0` | **Flutter 编译参数**：置 `1` 完全不发网络请求，纯内置快照；默认关闭（在线直连） |

---

## 账号、播放与互动：实现范围与边界

本项目只用**官方公开能力**：不解析播放地址、不持有登录凭证、不代用户调用需要登录的写接口。
三项常见诉求的实际范围如下。

| 能力 | 实现范围 | 交互方式 | 数据存储边界 | 合规判定 |
| --- | --- | --- | --- | --- |
| 官方原生登录 | **未实现**。官方 [OAuth 2.0](https://openhome.bilibili.com/doc/4/eaf0e2b5-bde9-b9a0-9be1-019bb455701c) 需要开发者入驻、创建应用、审核 scope 与备案回调域；已开放的 scope（`USER_INFO` / `ARC_BASE` / `ARC_DATA` / `USER_DATA` / `ATC_*`）只覆盖创作者侧只读资料与投稿，**不含观看侧互动** | 若日后接入：走官方授权页 / 移动 SDK，`code` 由服务端换 `access_token` | 不采集、不传输、不存储密码 / Cookie / `SESSDATA` / `bili_jct` / `access_token` / `refresh_token`；无账号表、无凭证缓存、无本地会话。若接入 OAuth，token 仅存内存、进程退出即失效，需重新授权 | 抓 Web 登录态复用 `SESSDATA` **不是**官方登录，且违反[用户协议 5.6(3)](https://www.bilibili.com/protocal/licence.html)，不采用 |
| 应用内播放 | ✅ **已实现**：B 站官方[站外外链播放器](https://player.bilibili.com) | 详情页点封面 / 播放按钮 → 应用内播放页；Web 用 `HtmlElementView` 承载官方 iframe，原生端降级为用系统浏览器打开同一个官方播放器 URL | 只向官方传 `bvid` 与分 P；不请求 `playurl`、不接触视频流、不注入登录态 | 官方为第三方页面提供的公开嵌入方式，播放、鉴权、清晰度与版权控制由 `player.bilibili.com` 负责；部分 UP 主可关闭「允许嵌入」 |
| 评论 / 投币 / 点赞 | **未实现**，提供「评论 / 投币」入口 | 点击后唤起官方客户端 / 网页，在官方完成互动 | 不代持凭证、不调用写接口、不缓存互动结果 | 开放平台无对应 scope；模拟 Web 写接口需 `SESSDATA` + `bili_jct` + WBI 签名，属于协议禁止的自动化访问。协议明确官方公布方式为使用服务的**唯一合法方式**，其他途径获取的账号、硬币等为非法所得 |

**为什么不走「Cookie 登录 + 逆向 WBI 写接口」**：这三条路都要求第三方长期持有用户的完整账号凭证，
等于把账号权限交给一个非官方应用；同时触发风控、可能导致账号受限，也与[开放平台开发者服务协议](https://open.bilibili.com/agreement/developer-service)
「不得以自动程序获取服务 / 数据」冲突。因此本项目宁可少三项功能，也不做这层。

**本地仅保存**：收藏、观看历史、稍后再看、搜索历史与外观设置（`SharedPreferences`），
全部留在设备本地，不上传、不关联任何账号。设置页「账号与数据边界」有同样说明。

---

## 已知限制

- **评论条数**：未登录的访客身份下，B 站 `/x/v2/reply` 通常只开放少量热评（实测 3 条，`is_end=true`）。已验证 WBI 签名的新接口结果相同，属于上游策略而非实现问题。
- **播放依赖官方外链播放器**：Web 端在应用内以 iframe 嵌入，原生端用系统浏览器打开同一个官方播放器 URL（Flutter 3.0 六端没有统一的 WebView 插件，故不自行伪造播放器）。部分 UP 主可关闭「允许嵌入」；大会员 / 高画质内容需在官方播放器中由用户自行登录，本应用不解析播放地址、不接触视频流。
- **接口稳定性**：上游可能调整字段或加风控；Web 链路的适配点是 `server/src/normalize.js`，原生直连链路是 `app/lib/data/bili_direct.dart`，两处规则同构，改动需同步；所有接口都有真实快照兜底。
- **工具链**：本工程在 Flutter 3.0 / Dart 2.17 上验证通过，依赖刻意压到 4 个，较新 SDK 同样可用。
- **Web 玻璃模糊**：html renderer 下不启用 `BackdropFilter`，改用 Canvas 渐变、边缘折射环与镜面亮斑模拟透镜；光学层与内容合并为单一渲染对象，避免 html renderer 的负 z-index canvas 盖住文字。原生端启用真实背景模糊。若改用 `flutter build web --web-renderer canvaskit`，需自行评估首包体积与字体加载。
- **着色 Tinted 档偏保守**：为保证文字可读性抬高了不透明度，观感比通透 Clear 更接近实色卡片；想看最典型的 iOS 26 透镜效果请用默认的通透档。

---

## 合规提示

请遵守哔哩哔哩用户协议、robots 规则与相关数据法规：**仅供学习与个人使用，勿商用、勿高频抓取、勿绕过登录鉴权获取受限内容**。
不抓取 Web 登录态、不逆向 WBI 签名、不解析播放地址、不代用户执行需要登录的写操作。
收藏 / 历史 / 搜索历史全部留在设备本地，不上传，也不收集任何账号信息。
