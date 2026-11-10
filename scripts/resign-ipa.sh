#!/usr/bin/env bash
# 把 CI 产出的未签名 IPA 用你自己的 Apple 开发者证书重签成可安装 IPA。
#
# 为什么需要这一步：iOS 要求每个 .app 必须由 Apple 签发的证书签名，并携带
# 与 bundle id、设备列表匹配的 provisioning profile。CI 上没有你的私钥和
# 描述文件，产出的 BiliLite-1.2.0-UNSIGNED.ipa 无法直接装到真机。
#
# 前置条件（在 macOS 上执行）：
#   - Xcode + Command Line Tools（提供 codesign / security / plutil）
#   - Apple Developer 账号（个人 / 公司，$99/年）
#   - 证书已导入登录钥匙串：Apple Development / Apple Distribution / iPhone Developer
#   - 与 bundle id com.bililite.bililite 匹配的 .mobileprovision
#       · Development / Ad Hoc：描述文件里需包含目标设备 UDID
#       · Enterprise / App Store：走对应分发渠道
#
# 用法：
#   ./scripts/resign-ipa.sh \
#       BiliLite-1.2.0-UNSIGNED.ipa \
#       "Apple Development: Your Name (TEAMID)" \
#       ./BiliLite.mobileprovision \
#       BiliLite-1.2.0-signed.ipa
#
# 安装方式（重签后）：
#   xcrun devicectl device install app --device <UDID> <signed.ipa>   # Xcode 15+
#   或 ios-deploy -b Payload/Runner.app / Apple Configurator / Xcode Devices
set -euo pipefail

IPA_IN="${1:?用法: resign-ipa.sh <unsigned.ipa> <证书名> <profile.mobileprovision> [signed.ipa]}"
CERT="${2:?缺少证书名，例如 'Apple Development: Zhang San (ABCDE12345)'}"
PROFILE="${3:?缺少 .mobileprovision 路径}"
IPA_OUT="${4:-BiliLite-1.2.0-signed.ipa}"
BUNDLE_ID="com.bililite.bililite"

for cmd in security codesign plutil unzip zip; do
  command -v "$cmd" >/dev/null || { echo "[!] 缺少 $cmd，请在 macOS + Xcode 环境运行"; exit 1; }
done
[ -f "$IPA_IN" ]   || { echo "[!] IPA 不存在: $IPA_IN"; exit 1; }
[ -f "$PROFILE" ]  || { echo "[!] 描述文件不存在: $PROFILE"; exit 1; }
security find-identity -v -p codesigning | grep -F -- "$CERT" >/dev/null \
  || { echo "[!] 钥匙串中找不到证书: $CERT"; security find-identity -v -p codesigning; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT_ABS="$(cd "$(dirname "$IPA_OUT")" && pwd)/$(basename "$IPA_OUT")"

echo "[1/6] 解包 $IPA_IN"
unzip -q "$IPA_IN" -d "$WORK/in"
APP="$(find "$WORK/in/Payload" -maxdepth 1 -name '*.app' -type d | head -1)"
[ -n "$APP" ] || { echo "[!] Payload/ 中没有 .app"; exit 1; }
echo "      app = $(basename "$APP")"

echo "[2/6] 从描述文件导出 entitlements"
security cms -D -i "$PROFILE" > "$WORK/profile.plist"
plutil -extract Entitlements xml1 -o "$WORK/entitlements.plist" "$WORK/profile.plist"
TEAM_FROM_PROFILE="$(plutil -extract TeamIdentifier.0 raw -o - "$WORK/profile.plist" 2>/dev/null || true)"
echo "      team = ${TEAM_FROM_PROFILE:-unknown}"

echo "[3/6] 替换描述文件并清除旧签名"
cp "$PROFILE" "$APP/embedded.mobileprovision"
rm -rf "$APP/_CodeSignature"

echo "[4/6] 签名内嵌 frameworks"
if [ -d "$APP/Frameworks" ]; then
  find "$APP/Frameworks" -maxdepth 1 -type d \( -name '*.framework' -o -name '*.dylib' \) | while read -r fw; do
    echo "      $(basename "$fw")"
    codesign --force --sign "$CERT" --timestamp=none "$fw"
  done
fi

echo "[5/6] 签名主 app"
codesign --force --sign "$CERT" \
  --entitlements "$WORK/entitlements.plist" \
  --bundle-identifier "$BUNDLE_ID" \
  --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -4

echo "[6/6] 重新打包"
( cd "$WORK/in" && zip -qry "$OUT_ABS" Payload )
echo "[ok] 已生成: $OUT_ABS"
echo "     校验: unzip -l \"$OUT_ABS\" | head"
echo "     安装: xcrun devicectl device install app --device <UDID> \"$OUT_ABS\""
