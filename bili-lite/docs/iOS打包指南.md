# iOS 打包指南

iOS 是六端里唯一需要"花钱 + 账号 + 特定机器"才能出包的一端。这份文档把门槛拆开讲清楚，
并给出三条可落地的路径。

---

## 一、先分清三道坎

很多人以为"打 iOS 包"是一件事，其实是三件独立的事，缺任何一道都拿不到能装进手机的 IPA。

| 坎 | 是什么 | 需要什么 | 能不能在 CI 里做 |
| --- | --- | --- | --- |
| **① 编译** | 把 Dart 代码编成 `.app` | macOS + Xcode + Flutter SDK | ✅ 可以，`macos-15` runner |
| **② 签名** | 让 Apple 认这个 App | Apple Developer Program（$99/年）签发的证书 + 描述文件 | ✅ 可以，把证书存进 Secret |
| **③ 分发** | 让用户装得上 | TestFlight / Ad Hoc / App Store / 企业分发 | ✅ TestFlight 可全自动 |

**未签名的 IPA 装不进任何真机。** 这是 iOS 与 Android 的根本差别：Android 允许自签名，
iOS 不允许。所以"CI 打了个 IPA"和"CI 打了个能用的 IPA"之间，隔着第②③道坎。

---

## 二、三条路径怎么选

| | 路径 A：CI + TestFlight | 路径 B：本机 macOS 出 IPA | 路径 C：CI 出未签名 IPA |
| --- | --- | --- | --- |
| 额外花钱 | $99/年 | $99/年 | $0 |
| 需要 Mac | ❌ | ✅ | ❌ |
| 产出 | 用户可装的 IPA（TestFlight） | 用户可装的 IPA（Ad Hoc/开发） | 装不了的 IPA，仅供编译验证 |
| 适合 | 长期维护、多人安装 | 一次性的自用/小范围测试 | 只验证代码能不能编过 |
| 自动化程度 | 全自动（推送即出包） | 半自动 | 全自动 |

**推荐路径 A。** 它和前一轮"构建统一交给 GitHub"的思路是一致的：编译、签名、上传全在流水线里完成，
你只管在手机上装 TestFlight。

---

## 三、路径 A：GitHub Actions → TestFlight（推荐）

### 3.1 账号侧一次性准备

1. **加入 Apple Developer Program**
   <https://developer.apple.com/programs/> — 个人或公司，$99/年。
   这是硬门槛：没有它就没有证书、没有描述文件、无法上传 App Store Connect。

2. **在 App Store Connect 创建 App 记录**
   <https://appstoreconnect.apple.com/apps> → "新建 App" → 填名称、副标题、bundle id
   （用 `com.bililite.bililite`）、主语言、分类。
   - 这里创建 App 时，Apple 会自动在开发者门户注册对应的 App ID；
   - 首次创建需要等待 Apple 的角色分配邮件（通常几分钟到几小时）。

3. **创建 App Store Connect API Key**
   App Store Connect → 用户与访问 → 集成 → App Store Connect API → 创建团队密钥
   - 角色选 **App Manager**（或 App Store Connect Admin）
   - 下载得到的 `AuthKey_XXXXXXXXXX.p8` **只此一份**，务必存好
   - 记下 **Key ID** 和 **Issuer ID**

4. **拿到团队 ID（Team ID）**
   App Store Connect → 用户与访问 → 右上角姓名 → 查看账户信息 → 团队 ID（10 位字母数字）

### 3.2 在仓库配置 Secrets

```bash
# 在仓库根目录执行（需要 gh 已登录且对仓库有 admin 权限）
gh secret set APP_STORE_CONNECT_ISSUER_ID --repo llovepeaches/bili-lite
gh secret set APP_STORE_CONNECT_KEY_ID    --repo llovepeaches/bili-lite
gh secret set APPLE_TEAM_ID               --repo llovepeaches/bili-lite
gh secret set APP_STORE_CONNECT_KEY_CONTENT --repo llovepeaches/bili-lite \
  --body "$(base64 -w0 AuthKey_XXXXXXXXXX.p8)"
```

| Secret | 内容 |
| --- | --- |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect 的 Issuer ID（UUID） |
| `APP_STORE_CONNECT_KEY_ID` | API Key 的 Key ID（10 位） |
| `APP_STORE_CONNECT_KEY_CONTENT` | `.p8` 私钥的 base64 编码 |
| `APPLE_TEAM_ID` | 开发者团队 ID（10 位） |

> `.p8` 不要提交到仓库，也不要放进安装包。它只存在于 GitHub Secret 与流水线临时目录，
> 流水线结束即删除（job 里配了 `if: always()` 的清理步骤）。

### 3.3 触发构建

```bash
gh workflow run build-installers.yml \
  -f flutter_version=3.24.4 \
  -f release_tag=bili-lite-v1.2.0 \
  -f publish=true \
  -f run_ios=true \
  -f publish_testflight=true
```

流水线里 `ios-testflight` job 会依次做四件事：

1. `flutter build ios --config-only` 生成 xcconfig
2. `xcodebuild archive` 带 `-allowProvisioningUpdates` + API Key
   → **Xcode 自动在开发者门户创建证书与描述文件**，不需要手动导入 p12
3. `xcodebuild -exportArchive` 按 `ios/ExportOptions.plist` 导出 IPA
4. `xcrun altool --upload-app` 上传到 App Store Connect

上传后等待 Apple 的构建处理（通常 5–30 分钟），然后在 App Store Connect → 测试飞行 里
把构建加到内部测试组，用户装上 **TestFlight** App 即可安装。

### 3.4 常见错误

| 报错 | 原因 | 处理 |
| --- | --- | --- |
| `No suitable application records were found` | App Store Connect 没有这个 bundle id 的记录 | 先在 ASC 新建 App |
| `The bundle version must be higher than the previously uploaded version` | build 号重复 | CI 用 `${{ github.run_number }}` 作 build 号，一般不会撞；手改版本号时注意 |
| `HTTP 401` / `Authentication credentials are missing or invalid` | `.p8` 没写到 `altool` 找得到的位置 | 流水线已设 `API_PRIVATE_KEYS_DIR`，确认 key 文件名是 `AuthKey_<KeyID>.p8` |
| `Invalid Provisioning Profile` | 导出方式不是 App Store | `ExportOptions.plist` 的 `method` 必须是 `app-store-connect` |
| `Unable to find a destination matching...` | Xcode 版本过低 / Flutter 过旧 | 见下一节 |

---

## 四、路径 B：在自己的 Mac 上出可安装 IPA

适合"就装到自己手机上"这种一次性需求。

```bash
# 1. 先做环境自检，把缺的东西一次列清
./scripts/ios-preflight.sh

# 2. 构建并用你的证书重签
./scripts/build-ios-local.sh \
    "Apple Development: Zhang San (ABCDE12345)" \
    ./BiliLite.mobileprovision \
    BiliLite-1.2.0-signed.ipa

# 3. 装到设备
xcrun devicectl device install app --device <UDID> BiliLite-1.2.0-signed.ipa
```

`build-ios-local.sh` 做四步：依赖准备 → `flutter build ios --no-codesign` → 打包未签名 IPA →
调 `resign-ipa.sh` 用你的证书重签（重签会替换描述文件、清旧签名、签 Frameworks 再签主 App）。

> 注意：本机可以自己安装旧版 Xcode。macOS-15 runner 镜像只预装 Xcode 16.0–16.4 与 26.x，
> 但你自己的 Mac 可以装 Xcode 15.4 —— 那是让 Flutter 3.0.0 也能编过的最省事办法。

---

## 五、路径 C：只要未签名 IPA

不需要任何证书、不需要开发者账号，只想验证"iOS 端能不能编过"：

```bash
gh workflow run build-installers.yml -f run_ios=true -f publish=false
```

产物 `BiliLite-<版本>-UNSIGNED.ipa` 会作为 Actions artifact 留存 30 天。
它**不能装进任何真机**，只能用来验证编译链路、跑静态检查。

---

## 六、当前工程的已知阻碍：Flutter 3.0.0 vs Xcode 16

这是本项目 iOS 打包目前最实质的障碍，和签名无关。

### 事实

- `macos-13` runner 已于 **2025-12-04** 移除，`macos-14` 已于 **2026-11-02** EOL；
- 现在只剩 `macos-15`（Xcode **16.0–16.4**、26.x）和 `macos-26`；
- 镜像里**不再有 Xcode 15.x**，没法靠降级 Xcode 绕开；
- Xcode 16 起 deployment target 硬性下限为 iOS 12.0；
- Flutter 官方在 **3.24.4** 才修复 Xcode 16 相关的 `xcode_backend.sh` 与 `Generated.xcconfig` 模板。

### 已经处理的部分

- `Runner.xcodeproj` 的 `IPHONEOS_DEPLOYMENT_TARGET` 由 9.0 提到 **13.0**
- `Flutter/AppFrameworkInfo.plist` 的 `MinimumOSVersion` 同步到 **13.0**
- `Podfile` 的 `platform :ios` 统一到 **13.0**，`post_install` 强制所有 pod 一致，
  并补上 CocoaPods 1.16+ `target_validator` 对空 `ARCHS` 的兼容处理
- `Podfile` 顶部保留 `File.exists?` 兼容补丁（Ruby 3.2+ 已移除该方法）

### 还需要处理的部分（升级 Flutter）

工程当前锁定 `Flutter 3.0.0 / Dart 2.17`，要吃到 Xcode 16 支持需升级到 `≥ 3.24.4`。改动清单：

| # | 改动 | 位置 | 说明 |
| --- | --- | --- | --- |
| 1 | SDK 约束 | `app/pubspec.yaml` | `>=2.17.0 <3.0.0` → `>=3.x <4.0.0` |
| 2 | 按钮配色 API | 4 处 `TextButton.styleFrom(primary:)` | Flutter 3.22 起移除 `primary`，改用 `foregroundColor` |
| 3 | Web 渲染器 | CI 与文档里的 `--web-renderer html` | Flutter 3.29 移除 html renderer，需改 canvaskit 并内置 CanvasKit |
| 4 | 依赖升级 | `http` / `shared_preferences` / `url_launcher` | 新版本对 Dart 3 与新 iOS 最低版本更友好 |
| 5 | `dart:html` | `oauth_launcher_web.dart`、`player_view_web.dart` | 3.29 起标记废弃，需迁到 `package:web` |

第 3 项影响面最大：Web 端的液态玻璃是用 Canvas 手动模拟折射与镜面高光的，
换 canvaskit 后渲染路径变化，需要重新做一轮浏览器验收。

---

## 七、分发方式怎么选

| 方式 | 设备数上限 | 有效期 | 需要审核 | 适合 |
| --- | --- | --- | --- | --- |
| **TestFlight** | 10,000 名测试员 | 90 天（可续） | 否 | 团队内测、外部测试者 |
| Ad Hoc | 100 台/年 | 证书 1 年 | 否 | 已登记 UDID 的设备 |
| Development | 少量 | **7 天** | 否 | 临时调试 |
| App Store | 无上限 | — | 是 | 正式发布 |
| Enterprise | 无上限 | — | 否 | 企业内部（$299/年） |

TestFlight 是唯一"不写一行代码就全自动"的路子：上传即用，App Store Connect 会把 IPA 转成
TestFlight 专用格式并重新签名，用户不需要装描述文件。

---

## 八、一句话总结

> **编译**要 macOS + Xcode，**签名**要 $99/年的 Apple Developer Program，
> **分发**用 TestFlight 就能全自动。
> 仓库侧已经准备好流水线与脚本，剩下的只有账号和证书——以及把 Flutter 从 3.0.0 升到 3.24.4+。
