#!/usr/bin/env bash
# 在**你自己的 macOS** 上从源码构建并签名出「可安装」的 iOS IPA。
#
# 为什么不在 CI 做：
#   - Flutter 3.0.0（2022）与 macOS-15 runner 的 Xcode 16.4 / Ruby 3.3 /
#     CocoaPods 1.17 存在多层不兼容；
#   - 更关键的是 CI 没有你的 Apple 签名私钥和 provisioning profile，
#     未签名 IPA 无法安装到任何真机。
#
# 前置条件：
#   - macOS + Xcode（建议 Xcode 14；仓库的 ios/Podfile 已带 Ruby 3.2+
#     与 DT_TOOLCHAIN_DIR 兼容补丁，Xcode 15/16 也可尝试）
#   - Flutter 3.0.0 / Dart 2.17（与 pubspec.lock 一致）
#   - Apple Developer 账号，证书已导入登录钥匙串
#   - 与 bundle id `com.bililite.bililite` 匹配的 .mobileprovision
#
# 用法（在仓库根目录执行）：
#   ./scripts/build-ios-local.sh \
#       "Apple Development: Your Name (TEAMID)" \
#       ./BiliLite.mobileprovision \
#       BiliLite-1.2.0-signed.ipa
set -euo pipefail

CERT="${1:?用法: build-ios-local.sh <证书名> <profile.mobileprovision> [输出.ipa]}"
PROFILE="${2:?缺少 .mobileprovision 路径}"
OUT="${3:-BiliLite-1.2.0-signed.ipa}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/bili-lite/app"
[ "$(uname -s)" = "Darwin" ] || { echo "[!] 必须在 macOS 上运行"; exit 1; }
command -v flutter >/dev/null || { echo "[!] 未找到 flutter（需 3.0.0）"; exit 1; }
[ -f "$PROFILE" ] || { echo "[!] 描述文件不存在: $PROFILE"; exit 1; }

echo "[1/4] 依赖与 Flutter 版本"
( cd "$APP_DIR" && flutter --version | head -2 && flutter pub get )

echo "[2/4] 构建 iOS release（不签名）"
( cd "$APP_DIR" && flutter build ios --release --no-codesign )
APP="$APP_DIR/build/ios/iphoneos/Runner.app"
[ -d "$APP" ] || { echo "[!] 未产出 Runner.app"; exit 1; }

echo "[3/4] 打包未签名 IPA"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/ipa/Payload"
cp -R "$APP" "$WORK/ipa/Payload/"
( cd "$WORK/ipa" && zip -qry "$WORK/unsigned.ipa" Payload )

echo "[4/4] 用你的证书重签为可安装 IPA"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
"$ROOT/scripts/resign-ipa.sh" "$WORK/unsigned.ipa" "$CERT" "$PROFILE" "$OUT_ABS"

echo "[ok] 可安装 IPA: $OUT_ABS"
echo "     安装: xcrun devicectl device install app --device <UDID> \"$OUT_ABS\""
