#!/usr/bin/env bash
# read-ios-channel.sh — 从 OEM 渠道配置读取 iOS 身份，输出 KEY=VALUE 到 stdout
#
# 背景：build-ios.yml / prepare-ios-project.yml 曾把 bundleId/appid/displayName/profileSpecifier
# 写死为 laiyima 渠道，导致打 rongyifu / xinglianyun 渠道包时内容错乱。
# 本脚本把 iOS 身份改为从 oem_config/<channel>/oem.json 的 ios 段读取，按渠道正确切换。
#
# 用法: bash read-ios-channel.sh <repo根目录> <channel>
#   <repo根目录> 指向 clone 出来的源码根（含 oem_config/<channel>/oem.json）
#   <channel>    laiyima / rongyifu / xinglianyun
# 输出（每行 KEY=VALUE）:
#   CHANNEL_IOS_BUNDLE_ID / CHANNEL_IOS_DISPLAY_NAME / CHANNEL_IOS_APPID / CHANNEL_IOS_PROFILE_SPECIFIER / CHANNEL_IOS_TOKEN
# 依赖: macOS runner 自带 python3。
set -euo pipefail

REPO="${1:?用法: read-ios-channel.sh <repo根目录> <channel>}"
CHANNEL="${2:?用法: read-ios-channel.sh <repo根目录> <channel>}"

CFG="$REPO/oem_config/$CHANNEL/oem.json"
[ -f "$CFG" ] || { echo "::error::渠道配置不存在: $CFG"; exit 1; }

python3 - "$CFG" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding='utf-8'))
channel = cfg.get('channelCode', '')
app = cfg.get('app', {}) or {}
ios = cfg.get('ios', {}) or {}
android = cfg.get('android', {}) or {}
# bundleId 优先 ios.bundleId，缺省回退 android.packageName（本项目 iOS bundleId = android 包名）
bundle_id = ios.get('bundleId') or android.get('packageName') or ''
display = ios.get('displayName') or app.get('name') or ''
appid = ios.get('appid') or app.get('appid') or ''
profile = ios.get('profileSpecifier') or ''
# 令牌仅用于校验渠道身份，不放任何敏感签名值
print(f"CHANNEL_IOS_BUNDLE_ID={bundle_id}")
print(f"CHANNEL_IOS_DISPLAY_NAME={display}")
print(f"CHANNEL_IOS_APPID={appid}")
print(f"CHANNEL_IOS_PROFILE_SPECIFIER={profile}")
PY
