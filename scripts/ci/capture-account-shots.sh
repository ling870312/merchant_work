#!/usr/bin/env bash
# 用 Maestro 登录测试账号并截取业务页面。
# 参数：$1=模拟器 UDID  $2=Bundle ID  $3=截图前缀（iphone-6.7 / iphone-6.1 / iphone-6.5）
# 账号密码来自 GitHub Secrets：SCREENSHOT_USERNAME / SCREENSHOT_PASSWORD
set -eu

UDID="$1"
BUNDLE_ID="$2"
PREFIX="$3"
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
OUT_DIR="$WORKSPACE/maestro-output/$PREFIX"
SHOT_DIR="$WORKSPACE/screenshots"

mkdir -p "$OUT_DIR" "$SHOT_DIR"
export PATH="$HOME/.maestro/bin:$PATH"

echo "Maestro 登录并截取 ${PREFIX} 业务页面..."
set +e
maestro test "$WORKSPACE/scripts/ci/maestro/account-shots.yaml" \
  --device="$UDID" \
  --test-output-dir="$OUT_DIR" \
  -e APP_ID="$BUNDLE_ID" \
  -e PREFIX="$PREFIX" \
  -e SCREENSHOT_USERNAME="$SCREENSHOT_USERNAME" \
  -e SCREENSHOT_PASSWORD="$SCREENSHOT_PASSWORD"
MAESTRO_EXIT=$?
set -e

# 无论成功失败都把已生成的截图/诊断产物拷出来
find "$OUT_DIR" -name "*.png" -type f | while read -r f; do
  cp "$f" "$SHOT_DIR/$(basename "$f")"
done
echo "业务页面截图："
ls -la "$SHOT_DIR" | tail -25
exit "$MAESTRO_EXIT"
