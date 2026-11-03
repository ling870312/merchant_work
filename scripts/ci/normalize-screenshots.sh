#!/usr/bin/env bash
# Maestro 截图在部分模拟器上会比目标尺寸少 1 像素（如 1178x2556）。
# 用 sips 补边到 App Store 要求尺寸，避免上传时报“文件尺寸无效”。
set -eu

normalize() {
  f="$1"; tw="$2"; th="$3"
  [ -f "$f" ] || return 0
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/ {print $2}')
  h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/ {print $2}')
  if [ "$w" != "$tw" ] || [ "$h" != "$th" ]; then
    sips --padToHeightWidth "$th" "$tw" --padColor FFFFFF "$f" >/dev/null
    echo "normalized $f: ${w}x${h} -> ${tw}x${th}"
  fi
}

for f in screenshots/iphone-6.7-*.png; do
  [ -f "$f" ] || continue
  normalize "$f" 1290 2796
done
for f in screenshots/iphone-6.5-*.png; do
  [ -f "$f" ] || continue
  normalize "$f" 1242 2688
done
for f in screenshots/iphone-6.3-*.png; do
  [ -f "$f" ] || continue
  normalize "$f" 1206 2622
done
for f in screenshots/iphone-6.1-*.png; do
  [ -f "$f" ] || continue
  normalize "$f" 1179 2556
done
