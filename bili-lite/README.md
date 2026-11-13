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

**官方登录是第四条独立链路**，与浏览数据完全解耦——不登录也能看全部内容：

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
授权码 `code` 也不落客户端。详见 [「B 站账号：官方 OAuth 2.0」](#b-站账号官方-oauth-20)。

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

想体验官方登录链路但没有开放平台凭证时，用 `BILI_OAUTH_SANDBOX=1 node src/index.js` 启动，
设置页「B 站账号」会出现醒目的「演示授权 · 非 B 站官方」标签，可完整走一遍登录 / 续期 / 退出登录。
真实凭证的配置方式见 [「启用真实登录」](#启用真实登录)。

**独立安装包不需要上面这个服务**：Android APK / Windows exe 会自行直连 B 站公开接口拿实时数据，
只有连不上时才降级到内置的 `assets/offline.json`。真机调试若想改回走本机 BFF，
用 `flutter run --dart-define=BFF_URL=http://<电脑IP>:8787`；完全禁用联网则加 `--dart-define=OFFLINE=1`。

### 直接下载已构建好的安装包

所有二进制统一由 GitHub Actions 编译（`.github/workflows/build-installers.yml`），
产物直接发布到仓库 Release，本地不需要装 Android SDK / MSVC：

| 平台 | Release 资产 |
| --- | --- |
| Android | `BiliLite-1.2.0-Android.apk` |
| Windows | `BiliLite-1.2.0-Windows-Setup.exe` |
| Web + BFF | `bili-lite-web-v1.2.0.tar.gz` |

手动触发一次全平台构建：

```bash
gh workflow run build-installers.yml -f release_tag=bili-lite-v1.2.0 -f publish=true
```

Android APK 使用正式 release 密钥签名（密钥以 Secret 存放，不入库），可覆盖升级。
iOS IPA 需要 macOS + Xcode + Apple 签名证书，用 `scripts/build-ios-local.sh` 在本机构建，
或用 `scripts/ios-preflight.sh` 先做环境自检；
完整的「三道坎 + 三条路径」说明见 [iOS 打包指南](docs/iOS打包指南.md)。

---

## 功能

| 模块 | 内容 |
| --- | --- |
| 首页 | 推荐流（下拉换一批 + 触底加载）、综合热门（分页）、排行榜（21 个分区切换 + 名次角标） |
| 搜索 | 关键词搜索视频、热词、本地搜索历史、分页与去重 |
| 详情 | 封面、完整统计数据、UP 主、可展开简介、分 P 列表、热评 / 最新排序、子回复预览 |
| 我的 | 收藏、观看历史、稍后再看；长按卡片删除、一键清空；全部本地存储，无需登录 |
| 设置 | 浅色 / 深色 / 跟随系统、**液态玻璃开关 / 浓度 / 通透·着色材质 / 动态光晕**、服务状态与健康检查、缓存条目、清空本地数据、**B 站账号（官方 OAuth 2.0 登录 / 续期 / 退出）**、数据边界与合规说明 |

**设计取舍**：播放交由 B 站官方外链播放器、不加载广告、不做个性化追踪。
B 站账号登录走开放平台官方 OAuth 2.0 授权码流程，用户授权后把 token 持久化到本机，
但只用已授权的只读 scope（`USER_INFO`）；不抓取 Web 登录态、不代用户执行写操作。
点击封面在应用内打开官方播放器；评论 / 投币等观看侧互动在官方客户端完成（开放平台没有对应 scope）。
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

**官方 OAuth 端点**（`/api/oauth/*`，由 `server/src/oauth.js` 独立分发，全部 `Cache-Control: no-store`）：

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
│   ├── 重构说明.md          # 一次全量重构的逐条问题清单与改进方案
│   └── preview/             # 20 张页面效果截图（含 6 张 OAuth 链路）
├── server/                  # BFF（零依赖）
│   ├── package.json
│   ├── .env.example
│   ├── src/
│   │   ├── index.js         # 路由、静态托管、图片代理、OAuth 分发
│   │   ├── bili.js          # 上游客户端、身份、缓存、stale-on-error
│   │   ├── normalize.js     # 5 套上游字段 → 统一模型
│   │   ├── oauth.js         # 官方 OAuth 2.0：state/ticket、换 token、签名 2.0
│   │   ├── mock.js          # 降级逻辑
│   │   └── mock-data.json   # 真实数据快照（2026-11-09）
│   └── tool/                # 签名向量自检 + 授权链路自检
└── app/                     # Flutter 工程（六平台骨架齐全）
    ├── pubspec.yaml         # 仅 4 个依赖
    ├── tool/                # verify_live.dart / verify_web.cjs / verify_oauth_web.cjs
    ├── web/                 # PWA 配置、启动占位页
    ├── android/ ios/ linux/ macos/ windows/
    └── lib/
        ├── main.dart / app.dart   # main 启动时消费 ?oauth_ticket=
        ├── core/            # 配置、令牌、分区表、路径表、存储门面、导航、主题
        │   ├── glass_theme.dart  # GlassConfig / GlassScope / GlassClock / GlassPalette
        │   ├── tokens.dart       # 设计令牌：状态色 / 字号 / 圆角 / 间距 / 取色扩展
        │   ├── storage.dart      # LocalStore：本地持久化门面 + 能力探测
        │   ├── partitions.dart   # 分区表单一数据源
        │   ├── api_paths.dart    # 接口路径单一数据源（纯 Dart）
        │   ├── navigation.dart   # 详情跳转与收藏切换的统一入口
        │   └── oauth_launcher.dart  # Web 同页导航 / 原生系统浏览器（条件导出）
        ├── data/            # models / api_client / bili_direct / oauth_api / repository
        ├── state/           # 主题+玻璃 / 本地库 / auth_session（登录态持久化）/ 搜索历史 / 单例
        ├── widgets/         # 封面、卡片、网格、骨架屏、状态视图、glass、统一 Logo/对话框/页头
        └── features/        # shell / home / search / detail / library / player / account / settings
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
| `BFF_URL` | 自动 | **Flutter 编译参数**：`--dart-define=BFF_URL=http://<IP>:8787`，让原生端改走指定 BFF；官方 OAuth 也走这个地址 |
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

## B 站账号：官方 OAuth 2.0

登录**已实现**，走的是 B 站开放平台 [OAuth 2.0 授权码流程](https://openhome.bilibili.com/doc/4/eaf0e2b5-bde9-b9a0-9be1-019bb455701c)，
用户授权后按需求把登录态**持久化到本机**。不登录也能浏览全部内容，两条链路互不影响。

| 能力 | 实现范围 | 交互方式 | 数据存储边界 | 合规判定 |
| --- | --- | --- | --- | --- |
| 官方登录 | ✅ **已实现**：2025-03 后的官方授权页 `account.bilibili.com/pc/account-pc/auth/oauth` | 设置页「B 站账号」→ 系统浏览器 / 同页打开官方授权页 → 同意 → 回调自动完成登录；原生端也可粘贴回调页的一次性授权码 | 本机持久化 `access_token`、`refresh_token`、过期时间、scope、openid / 昵称 / 头像 | 官方授权码流程；不接触密码 / Cookie / `SESSDATA` / `bili_jct` |
| 凭证续期 | ✅ 按官方 `refresh_token` 端点续期 | 启动时临期自动续期，也可手动点「刷新凭证」 | 新 token 覆盖本地旧值；每个 `refresh_token` 只用一次 | 官方明确 `expires_in` 是 UTC 绝对时间戳，按秒解析后再转毫秒 |
| 退出登录 | ✅ 清除本机全部凭证 | 确认对话框 → 本机 5 个键值一并删除 | 不留残值；B 站侧授权需到官方账号设置里解除 | 官方会在用户解除授权时推送事件，本项目未接入推送，故在 UI 明确提示 |
| 应用内播放 | ✅ B 站官方[站外外链播放器](https://player.bilibili.com) | 详情页点封面 → 应用内播放页；Web 用 `HtmlElementView`，原生端用系统浏览器打开同一官方 URL | 只传 `bvid` 与分 P；不请求 `playurl`、不接触视频流、不把 OAuth token 注入播放器 | 官方提供的公开嵌入方式，鉴权与版权控制由 `player.bilibili.com` 负责 |
| 评论 / 投币 / 点赞 | **未实现**，提供「评论 / 投币」入口 | 唤起官方客户端 / 网页，在官方完成互动 | 不代持凭证、不调用写接口 | 已开放 scope（`USER_INFO` / `USER_DATA` / `ARC_*` / `ATC_*` 等）全是创作者与账号侧只读能力，**不含观看侧互动**；模拟 Web 写接口需 `SESSDATA` + `bili_jct` + WBI 签名，属于协议禁止的自动化访问 |

### 启用真实登录

官方 OAuth 要求开发者资质，代码无法代你申请。四步：

1. 在 [openhome.bilibili.com](https://openhome.bilibili.com) 完成开发者入驻、创建应用；
2. 申请并等待 `USER_INFO` 等 scope 审核通过；
3. 把 `BILI_REDIRECT_URI`（形如 `https://你的域名/api/oauth/callback`）填入应用的「授权回调域」，**必须与环境变量一字不差**；
4. 在受信任终端注入 `BILI_CLIENT_ID` / `BILI_CLIENT_SECRET` / `BILI_REDIRECT_URI` 后重启 BFF。

未配置时 `/api/oauth/config` 返回 `configured: false`，设置页显示「未配置官方开放平台凭证，登录入口已停用」并列出缺失项，
**不会伪造登录按钮或假账号**。授权页 2025 年 3 月已迁移，旧的 `passport.bilibili.com/register/pc_oauth2.html` 不再使用。

### 本地存储明细

| 位置 | 键 | 内容 |
| --- | --- | --- |
| `SharedPreferences`（Web → localStorage，原生 → 平台偏好） | `bili_lite_oauth_access_token` / `bili_lite_oauth_refresh_token` | 官方 OAuth 凭证，仅本机 |
| 同上 | `bili_lite_oauth_expires_at` / `bili_lite_oauth_scopes` | 过期时间（毫秒 UTC）、已授权权限点 |
| 同上 | `bili_lite_oauth_user` | `USER_INFO` 的 openid / 昵称 / 头像 URL |
| BFF 进程内存 | `state`（5 分钟）/ `ticket`（60 秒） | 一次性，消费即删，**不落盘** |
| BFF 环境变量 | `client_secret` | 只在服务端进程内，不进响应 / 日志 / Git |

**明确不存**：账号密码、Cookie、`SESSDATA`、`bili_jct`、`client_secret`、授权码 `code`。
`SharedPreferences` 不是硬件加密存储——真机发布建议把 token 迁到 iOS Keychain / Android Keystore。
收藏 / 历史 / 稍后再看 / 搜索历史继续留在本机，**不关联账号、不上传**。

> **关于跨端持久化**：本地存储统一走 `app/lib/core/storage.dart` 的 `LocalStore` 门面，
> 启动时主动探测插件是否真的可用，结果通过设置页如实展示。
> `shared_preferences` 需 **≥ 2.1.0**（工程已锁定 `^2.1.0`）才有完整的六端原生实现
> （Windows / Linux / macOS 在 2.0.x 上是缺失的）。若探测失败，会退化为
> 「仅本次会话有效」并明确提示，而不是静默丢数据。

### 演示授权模式（仅本地自检）

```bash
cd server && BILI_OAUTH_SANDBOX=1 node src/index.js
```

用于在没有开放平台凭证时验证「授权码 → 换 token → 本地持久化 → 续期 → 退出登录」全链路。
它用本地模拟授权页代替官方页，**不连接 B 站、不产生真实凭证**，UI 顶部有醒目的「非 B 站官方」标签，
生产必须保持 `BILI_OAUTH_SANDBOX=0`。链路自检：

```bash
cd server && npm run verify:oauth          # 签名向量 + 授权流程，30 项
cd app && NODE_PATH=$(npm root -g) node tool/verify_oauth_web.cjs   # Web 端到端，20 项
```

**为什么不走「Cookie 登录 + 逆向 WBI 写接口」**：那要求第三方长期持有用户完整账号凭证，
等于把账号权限交给非官方应用；同时触发风控、可能导致账号受限，也与
[开放平台开发者服务协议](https://open.bilibili.com/agreement/developer-service)
「不得以自动程序获取服务 / 数据」冲突。因此本项目宁可少几项互动功能，也不做这层。

---

## 重构记录

本工程完成过一次覆盖全项目的重构（统一存储门面、设计令牌收敛、分区表去重、重复组件抽取、
跨端明文流量策略收紧、深色模式对比度修复、分页与生命周期缺陷修复等）。
逐条的问题清单与改进方案见 **[docs/重构说明.md](docs/重构说明.md)**。

## 已知限制

- **评论条数**：未登录的访客身份下，B 站 `/x/v2/reply` 通常只开放少量热评（实测 3 条，`is_end=true`）。已验证 WBI 签名的新接口结果相同，属于上游策略而非实现问题。
- **播放依赖官方外链播放器**：Web 端在应用内以 iframe 嵌入，原生端用系统浏览器打开同一个官方播放器 URL（Flutter 3.0 六端没有统一的 WebView 插件，故不自行伪造播放器）。部分 UP 主可关闭「允许嵌入」；大会员 / 高画质内容需在官方播放器中由用户自行登录，本应用不解析播放地址、不接触视频流。
- **接口稳定性**：上游可能调整字段或加风控；Web 链路的适配点是 `server/src/normalize.js`，原生直连链路是 `app/lib/data/bili_direct.dart`，两处规则同构，改动需同步；所有接口都有真实快照兜底。
- **登录依赖授权服务端**：官方 OAuth 的 `client_secret` 不能放进客户端（APK / exe / Web 产物都可被反编译），所以原生端登录也必须连到一个持有密钥的 BFF。默认指向 `10.0.2.2:8787` / `127.0.0.1:8787`，真机请用 `--dart-define=BFF_URL=https://你的授权域名` 指向已部署实例；不登录不影响浏览内容。
- **登录态不是硬件加密**：`SharedPreferences` 在当前依赖约束下是最简方案；生产发布建议接 Keychain / Keystore。跨端持久化依赖 `shared_preferences ≥ 2.1.0`（六端原生实现齐全），版本被降到 2.0.x 时桌面端会退化为会话内存态 —— 工程已锁定 `^2.1.0` 并在设置页显示实际探测结果。
- **解除授权推送未接入**：官方会在用户主动解除授权或注销时向厂商推送消息，本项目没有消息接收端点，因此本地可能残留已失效 token；调用开放接口返回失效时请重新授权，或点「退出登录」清除。
- **scope 由开放平台审核决定**：授权页只展示已审核通过的权限点；新增 scope 后已授权用户必须重新授权，代码里通过 `BILI_OAUTH_SCOPES` 配置，不会自行扩张权限。
- **工具链**：本工程在 Flutter 3.0 / Dart 2.17 上验证通过，依赖刻意压到 4 个，较新 SDK 同样可用。
- **Web 玻璃模糊**：html renderer 下不启用 `BackdropFilter`，改用 Canvas 渐变、边缘折射环与镜面亮斑模拟透镜；光学层与内容合并为单一渲染对象，避免 html renderer 的负 z-index canvas 盖住文字。原生端启用真实背景模糊。若改用 `flutter build web --web-renderer canvaskit`，需自行评估首包体积与字体加载。
- **着色 Tinted 档偏保守**：为保证文字可读性抬高了不透明度，观感比通透 Clear 更接近实色卡片；想看最典型的 iOS 26 透镜效果请用默认的通透档。

---

## 合规提示

请遵守哔哩哔哩用户协议、robots 规则与相关数据法规：**仅供学习与个人使用，勿商用、勿高频抓取、勿绕过登录鉴权获取受限内容**。
登录严格走官方 OAuth 2.0 授权码流程，不抓取 Web 登录态、不逆向 WBI 签名、不解析播放地址、不代用户执行需要登录的写操作，
也不把 token 用于未授权 scope。收藏 / 历史 / 搜索历史与 OAuth 凭证全部留在设备本地，不上传、不共享、不关联第三方。
`client_secret` 只在授权服务端环境变量里，请勿提交到代码仓库或写进客户端构建产物。
