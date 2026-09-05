#!/usr/bin/env bash
# sync-ios-appicons.sh — 把 OEM 图标注入预集成 iOS 工程的 AppIcon.appiconset
#
# 背景：build-ios.yml 只把 uni-app 的 www 资源同步进预集成工程，图标从未进过 IPA，
# 导致 App Store Connect 上传报 "Missing required icon file (120/152/167)" 和
# "CFBundleIconName is missing"。
#
# 方案：使用 single-size AppIcon（Xcode 14+ 资产目录新格式）——Contents.json 只声明
# 一张 1024x1024 universal 图标，actool 编译时自动生成 120/152/167 等全部尺寸。
# 注意：不要用手工声明多尺寸的旧格式（容易写无效槽位，如 iphone 20@1x，
# actool 报 "unassigned children"，Apple 后台严格校验会判 Invalid Binary）。
#
# 用法: bash sync-ios-appicons.sh <源图标png> <ios-project/HBuilder-Hello 目录>
# 依赖: macOS 自带 sips；仅当 pbxproj 未引用 Assets.xcassets 时才需要 xcodeproj gem
set -euo pipefail

SRC="${1:?用法: sync-ios-appicons.sh <源图标png> <HBuilder-Hello目录>}"
PROJ="${2:?用法: sync-ios-appicons.sh <源图标png> <HBuilder-Hello目录>}"

APP_NAME="HBuilder-Hello"
APP_SRC="$PROJ/$APP_NAME"
ASSET_DIR="$APP_SRC/Assets.xcassets"
APPSET="$ASSET_DIR/AppIcon.appiconset"
XCODE_PROJ="$PROJ/$APP_NAME.xcodeproj"

[ -f "$SRC" ] || { echo "::error::源图标不存在: $SRC"; exit 1; }
[ -d "$XCODE_PROJ" ] || { echo "::error::Xcode 工程不存在: $XCODE_PROJ"; exit 1; }

mkdir -p "$APPSET"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1) 生成 1024x1024 主图标
# 源图标已是 1024x1024（oem.json ios.appIcon 要求 1024x1024 无透明通道），直接复制。
# 如果 sips 可用（macOS）则用 sips 校验并复制；否则用 cp。
if command -v sips >/dev/null 2>&1; then
  sips -z 1024 1024 "$SRC" --out "$APPSET/AppIcon-1024.png" >/dev/null
else
  cp "$SRC" "$APPSET/AppIcon-1024.png"
  # 校验是 PNG 文件
  file "$APPSET/AppIcon-1024.png" | grep -q "PNG" || { echo "::error::图标不是 PNG 格式"; exit 1; }
fi

# 2) single-size Contents.json（universal 1024，actool 自动生成 120/152/167 等全部尺寸）
cat > "$APPSET/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

# 3) Assets.xcassets 顶层 Contents.json（缺了 actool 不识别）
if [ ! -f "$ASSET_DIR/Contents.json" ]; then
  echo '{ "info" : { "author" : "xcode", "version" : 1 } }' > "$ASSET_DIR/Contents.json"
fi

# 4) 兜底：若 pbxproj 没引用 Assets.xcassets，用 xcodeproj gem 加进 resources build phase，
#    否则 actool 不编译图标、CFBundleIconName 依旧缺失。
if ! grep -q "Assets.xcassets" "$XCODE_PROJ/project.pbxproj"; then
  echo "::warning::pbxproj 未引用 Assets.xcassets，正在用 xcodeproj 添加引用…"
  gem install xcodeproj --no-document >/dev/null 2>&1 || true
  ruby -e '
    require "xcodeproj"
    proj = Xcodeproj::Project.open(ARGV[0])
    target = proj.targets.find { |t| t.product_type == "com.apple.product-type.application" }
    abort "!! app target not found" if target.nil?
    main = proj.main_group
    ref = main.new_file("HBuilder-Hello/Assets.xcassets")
    ref.last_known_file_type = "folder.assetcatalog"
    target.resources_build_phase.add_file_reference(ref)
    proj.save
    puts "Assets.xcassets 已加入 resources build phase"
  ' "$XCODE_PROJ"
fi

echo "✅ AppIcon 注入完成（single-size，1024 universal）: $APPSET"
ls -la "$APPSET"
