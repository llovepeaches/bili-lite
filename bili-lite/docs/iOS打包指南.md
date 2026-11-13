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

| | 路径 A：CI + TestFlight | 路径 B：本机 macOS 出 IPA | 路径 C：CI 出 ad-hoc 签名 IPA |
| --- | --- | --- | --- |
| 额外花钱 | $99/年 | $99/年 | $0 |
| 需要 Mac | ❌ | ✅ | ❌ |
| 产出 | 用户可装的 IPA（TestFlight） | 用户可装的 IPA（Ad Hoc/开发） | 可侧载重签的 IPA（7 天有效）+ 纯未签名 IPA |
| 适合 | 长期维护、多人安装 | 一次性的自用/小范围测试 | 验证编译链路、自用侧载 |
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
  -f release_tag=bili-lite-v1.4.0 \
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

## 五、路径 C：CI 出 IPA（$0，编译验证 + 侧载素材）

不需要任何证书、不需要开发者账号：

```bash
gh workflow run build-installers.yml -f run_ios=true -f publish=true
```

产出**两个** IPA：

| 产物 | 状态 | 用途 |
| --- | --- | --- |
| `BiliLite-<版本>-UNSIGNED.ipa` | 完全无签名 | 验证编译链路、CI 冒烟 |
| `BiliLite-<版本>-iOS-ADHOC.ipa` | **ad-hoc 自签名**（`codesign -s -`） | 侧载素材：AltStore / Sideloadly / 爱思 可直接重签安装 |

> ad-hoc 签名用本机自带的自签名身份完成，**不需要任何 Apple 凭证**，
> 但它**不是** Apple 认可的签名 —— 装到真机上仍需由侧载工具用自己的证书重签，
> 且免费 Apple ID 重签的有效期只有 **7 天**。

### ad-hoc 签名的顺序（踩过坑）

签名顺序错了会被拒绝（引用了未签名代码）：

```
dylib  →  framework  →  PlugIns 里的 .app/.framework  →  Runner.app 本身
```

CI 里对应这段：

```bash
find "$APP/Frameworks" -type f -name "*.dylib" -print0 \
  | xargs -0 -I{} codesign --force --sign - --timestamp=none "{}"
for fw in "$APP"/Frameworks/*.framework; do
  codesign --force --sign - --timestamp=none "$fw"
done
codesign --force --sign - --timestamp=none "$APP"
```

验证结果（run `43349748942`）：

```
Identifier=com.bililite.bililite
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20400 size=974 flags=0x2(adhoc) hashes=24+3 location=embedded
Signature=adhoc
```

---

## 六、当前状态：编译链路已打通，只差证书

**结论先说**：iOS 的编译环节已经在 GitHub Actions 上跑通了，不需要升级 Flutter。
剩下的唯一障碍是 Apple 的账号与证书。

### 实测结果（run `43336509008`，2026-11-13）

| 项 | 结果 |
| --- | --- |
| Runner | `macos-15`，Xcode **16.4**，iOS 18.5 SDK |
| Flutter | **3.0.0**（未升级） |
| 编译 | `flutter build ios --release --no-codesign` ✅ 110.4s |
| 产物 | `Runner.app` → `BiliLite-1.2.0-UNSIGNED.ipa` 7.29 MB + `BiliLite-1.2.0-iOS-ADHOC.ipa` 7.31 MB（ad-hoc 签名） |
| 可执行文件 | `Mach-O 64-bit arm64 executable`（真机架构） |
| `CFBundleIdentifier` | `com.bililite.bililite` |
| `CFBundleShortVersionString` / `CFBundleVersion` | `1.2.0` / `15`（= GitHub run number） |
| `MinimumOSVersion` | `13.0` |

### 曾经拦路的三个事实（都已处理）

- `macos-13` runner 已于 **2025-12-04** 移除，`macos-14` 已于 **2026-11-02** EOL，
  现在只剩 `macos-15`（Xcode **16.0–16.4**、26.x）与 `macos-26`；
- 镜像里**不再有 Xcode 15.x**，没法靠降级 Xcode 绕开；
- Xcode 16 起 deployment target 硬性下限为 iOS 12.0。

> 曾以为"Flutter 3.0.0 与 Xcode 16 不兼容、必须升到 3.24.4+"是硬前提，
> 实测证明**并非如此**。真正卡住的是下面两个 Podfile 配置问题，与 Flutter 版本无关。

### 已经处理的部分

- `Runner.xcodeproj` 的 `IPHONEOS_DEPLOYMENT_TARGET` 由 9.0 提到 **13.0**
- `Flutter/AppFrameworkInfo.plist` 的 `MinimumOSVersion` 同步到 **13.0**
- `Podfile` 的 `platform :ios` 统一到 **13.0**，`post_install` 强制所有 pod 一致，
  并补上 CocoaPods 1.16+ `target_validator` 对空 `ARCHS` 的兼容处理
- `Podfile` 顶部保留 `File.exists?` 兼容补丁（Ruby 3.2+ 已移除该方法）
- `Podfile` 的 `pre_install` 绕过 CocoaPods #3289 的校验崩溃（见下）

### 实测：macos-15 上的两个真实拦路虎

在 `macos-15`（Xcode 16.4）实跑 `flutter build ios --no-codesign`，连着撞了两个坑。
**两个都跟 Flutter 版本无关**，一个在 CocoaPods，一个在本工程自己的 Podfile。

#### 坑一：CocoaPods 1.17 的 target_validator 崩溃

```
Error running pod install
NoMethodError - undefined method `each' for nil
  .../cocoapods-1.17.0/lib/cocoapods/installer/xcode/target_validator.rb:88:in `each'
  .../target_validator.rb:88:in `flat_map'
  .../target_validator.rb:88:in `block (2 levels) in verify_no_static_framework_transitive_dependencies'
```

对应源码（CocoaPods 1.17.0 `target_validator.rb`）：

```ruby
static_deps = dynamic_pod_targets.flat_map(&:recursive_dependent_targets).uniq.select(&:build_as_static?)
```

`recursive_dependent_targets` 递归展开依赖链时返回了 nil，导致 `.each` 崩掉。
本工程用了 `use_frameworks!` + Flutter 自带的静态 Framework，正好命中这条路径。

**已修**：在 `Podfile` 里用 issue #3289 的官方 workaround 跳过这项校验：

```ruby
pre_install do |installer|
  Pod::Installer::Xcode::TargetValidator.send(
    :define_method, :verify_no_static_framework_transitive_dependencies
  ) {}
end
```

Flutter 官方模板同样使用 `use_frameworks!`，跳过这项校验是安全的。
另一条路是在 CI 里把 CocoaPods 降到 1.16.2，也能绕过。

#### 坑二：Podfile 里 Profile 的映射值写错（本工程的真 bug）

绕过坑一后，`pod install` 又崩在下一层：

```
TypeError - no implicit conversion of nil into Hash
  xcodeproj-1.28.1/lib/xcodeproj/project.rb:794:in `merge!'
  xcodeproj-1.28.1/lib/xcodeproj/project.rb:794:in `add_build_configuration'
  cocoapods-1.17.0/lib/cocoapods/project.rb:375:in `add_build_configuration'
  cocoapods-1.17.0/.../pods_project_generator/project_generator.rb:88
```

顺着源码看下去就明白了 —— `xcodeproj` 生成 build configuration 时，
会按 `type` 去默认配置表里取一份基础设置：

```ruby
common_settings = Constants::PROJECT_DEFAULT_BUILD_SETTINGS
settings = ProjectHelper.deep_dup(common_settings[:all])
settings.merge!(ProjectHelper.deep_dup(common_settings[type]))   # ← type 为 nil 时炸这里
```

而 CocoaPods 的 `type` **只有 `:debug` 与 `:release` 两种**。本工程的 Podfile 写成了：

```ruby
project 'Runner', {
  'Debug' => :debug,
  'Profile' => :profile,   # ← 非法值！common_settings[:profile] 是 nil
  'Release' => :release,
}
```

`common_settings[:profile]` 返回 nil，`merge!(nil)` 就抛出了那个 TypeError。

**已修**：改回 Flutter 官方模板的写法：

```ruby
'Profile' => :release,
```

> 这个坑很值得记一笔：报错信息指向 CocoaPods / xcodeproj 两个第三方库，
> 真正的原因却是工程里一行手误。遇到 CocoaPods 崩在 `add_build_configuration`
> 附近时，先回头看 `project 'Runner'` 那段映射。

### 可选：升级 Flutter 的收益与代价

**当前不需要升级**，Flutter 3.0.0 在 Xcode 16.4 上编译正常。
但如果你想顺手把工程 modernize，以下是评估过的改动清单：

| # | 改动 | 位置 | 说明 |
| --- | --- | --- | --- |
| 1 | SDK 约束 | `app/pubspec.yaml` | `>=2.17.0 <3.0.0` → `>=3.x <4.0.0` |
| 2 | 按钮配色 API | 4 处 `TextButton.styleFrom(primary:)` | Flutter 3.22 起移除 `primary`，改用 `foregroundColor` |
| 3 | Web 渲染器 | CI 与文档里的 `--web-renderer html` | Flutter 3.29 移除 html renderer，需改 canvaskit 并内置 CanvasKit |
| 4 | 依赖升级 | `http` / `shared_preferences` / `url_launcher` | 新版本对 Dart 3 与新 iOS 最低版本更友好 |
| 5 | `dart:html` | `oauth_launcher_web.dart`、`player_view_web.dart` | 3.29 起标记废弃，需迁到 `package:web` |

第 3 项影响面最大：Web 端的液态玻璃是用 Canvas 手动模拟折射与镜面高光的，
换 canvaskit 后渲染路径变化，需要重新做一轮浏览器验收。
好处是 canvaskit 支持真实 `BackdropFilter`，液态玻璃在 Web 上可以少一层手工模拟。

**建议**：等 iOS 分发链路稳定后再单独安排，别和签名工作搅在一起。

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

> **编译**已经在 GitHub Actions 上跑通（macos-15 + Xcode 16.4 + Flutter 3.0.0，实测通过），
> **签名**需要 $99/年的 Apple Developer Program，
> **分发**用 TestFlight 就能全自动。
> 仓库侧流水线、脚本、配置都已就位，剩下的只有账号和证书。
