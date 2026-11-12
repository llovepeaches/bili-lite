#!/usr/bin/env bash
# iOS 打包环境自检：在真正动手构建前，先把「缺什么」一次性列清楚。
#
#   ./scripts/ios-preflight.sh
#
# 只做只读检查，不修改钥匙串、不安装任何东西。
set -uo pipefail

BUNDLE_ID="com.bililite.bililite"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/bili-lite/app"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

echo "Bili Lite · iOS 打包环境自检"

# ---------------------------------------------------------------- 操作系统
head_ "1. 操作系统"
if [ "$(uname -s)" = "Darwin" ]; then
  ok "macOS $(sw_vers -productVersion)"
  ARCH="$(uname -m)"
  ok "架构 $ARCH"
  if [ "$ARCH" = "arm64" ]; then
    warn "Apple Silicon：部分 CocoaPods 依赖需要 `arch -x86_64` 或装 ffi 的 arm64 版本"
  fi
else
  bad "当前不是 macOS，无法构建 iOS；请改用 GitHub Actions 的 macos-15 runner"
fi

# -------------------------------------------------------------------- Xcode
head_ "2. Xcode"
if command -v xcodebuild >/dev/null; then
  ok "当前选中：$(xcodebuild -version | head -1)"
  echo "     $(xcodebuild -version | tail -1)"
  if [ -d /Applications ]; then
    echo "     本机已安装："
    ls -d /Applications/Xcode*.app 2>/dev/null | sed 's#^/Applications/#       #' || true
  fi
  XCODE_MAJOR="$(xcodebuild -version | head -1 | awk '{print $2}' | cut -d. -f1)"
  if [ "${XCODE_MAJOR:-0}" -ge 16 ]; then
    warn "Xcode 16+ 要求 deployment target >= 12.0（工程已统一到 13.0）"
  fi
  if [ "${XCODE_MAJOR:-0}" -ge 16 ]; then
    warn "Xcode 16 需要 Flutter >= 3.24.4（Flutter 3.24.4 才修好 xcode_backend.sh）"
  fi
else
  bad "未安装 Xcode：https://developer.apple.com/download/"
fi

# ------------------------------------------------------------------- Flutter
head_ "3. Flutter"
if command -v flutter >/dev/null; then
  FLUTTER_VER="$(flutter --version 2>/dev/null | head -1)"
  ok "$FLUTTER_VER"
  FV="$(flutter --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  MAJOR="$(echo "$FV" | cut -d. -f1)"
  MINOR="$(echo "$FV" | cut -d. -f2)"
  if [ "${MAJOR:-0}" -lt 3 ] || { [ "${MAJOR:-0}" -eq 3 ] && [ "${MINOR:-0}" -lt 24 ]; }; then
    warn "Flutter $FV 与 Xcode 16 不兼容，请升级到 3.24.4 及以上"
  fi
else
  bad "未安装 Flutter SDK"
fi

# ---------------------------------------------------------------- CocoaPods
head_ "4. CocoaPods / Ruby"
if command -v pod >/dev/null; then
  ok "CocoaPods $(pod --version)"
else
  bad "未安装 CocoaPods：sudo gem install cocoapods"
fi
if command -v ruby >/dev/null; then
  RUBY_V="$(ruby --version)"
  ok "$RUBY_V"
  if echo "$RUBY_V" | grep -qE 'ruby (3\.[2-9]|[4-9])'; then
    warn "Ruby 3.2+ 移除了 File.exists?，工程 Podfile 已内置兼容补丁，无需额外处理"
  fi
fi

# --------------------------------------------------------------- 工程配置
head_ "5. 工程配置"
if [ -f "$APP_DIR/ios/Runner.xcodeproj/project.pbxproj" ]; then
  TGT="$(grep -m1 'IPHONEOS_DEPLOYMENT_TARGET' "$APP_DIR/ios/Runner.xcodeproj/project.pbxproj" | awk '{print $3}' | tr -d ';')"
  ok "Runner deployment target = $TGT"
  if [ "$(echo "$TGT < 12.0" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
    bad "deployment target 低于 12.0，Xcode 16 会直接报错"
  fi
  BUNDLE="$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER' "$APP_DIR/ios/Runner.xcodeproj/project.pbxproj" | awk -F'= ' '{print $2}' | tr -d ';')"
  ok "bundle id = $BUNDLE"
else
  bad "找不到 Runner.xcodeproj"
fi

# --------------------------------------------------------------- 签名身份
head_ "6. 签名材料（钥匙串）"
if command -v security >/dev/null; then
  IDS="$(security find-identity -v -p codesigning 2>/dev/null | grep -c ')' || true)"
  if [ "${IDS:-0}" -gt 0 ]; then
    ok "钥匙串里有 $IDS 个代码签名身份"
    security find-identity -v -p codesigning 2>/dev/null | sed 's/^/     /' | head -5
  else
    warn "钥匙串里没有代码签名身份"
    echo "     需要 Apple Developer Program（\$99/年），在 Xcode > Settings > Accounts 里登录"
  fi
  if [ -d "$HOME/Library/MobileDevice/Provisioning Profiles" ]; then
    N="$(ls -1 "$HOME/Library/MobileDevice/Provisioning Profiles" 2>/dev/null | wc -l | tr -d ' ')"
    ok "已安装 $N 个描述文件"
  else
    warn "没有描述文件目录（Ad Hoc / Development 分发需要 .mobileprovision）"
  fi
else
  warn "没有 security 命令（仅 macOS 提供）"
fi

# --------------------------------------------------------------- App Store
head_ "7. App Store Connect API Key（TestFlight 自动化分发）"
if [ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ] && [ -n "${APP_STORE_CONNECT_KEY_ID:-}" ]; then
  ok "环境变量里存在 Issuer ID / Key ID"
else
  warn "未配置 APP_STORE_CONNECT_ISSUER_ID / APP_STORE_CONNECT_KEY_ID"
  echo "     CI 自动化分发需要在仓库 Secrets 里补齐这三个："
  echo "       APP_STORE_CONNECT_ISSUER_ID / APP_STORE_CONNECT_KEY_ID / APP_STORE_CONNECT_KEY_CONTENT"
fi

head_ "结论"
cat <<'EOF'
  想要「能在真机上装的 IPA」，三件事缺一不可：
    1. Apple Developer Program 账号（$99/年）—— 签发证书与描述文件
    2. 一个 Mac 或 GitHub 的 macos-15 runner —— 跑 xcodebuild
    3. Flutter >= 3.24.4 —— 兼容 Xcode 16（工程当前锁定 3.0.0）

  只想验证「能不能编译通过」，不需要任何证书，跑未签名 IPA 即可。
  完整说明见 docs/iOS打包指南.md。
EOF
