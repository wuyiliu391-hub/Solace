#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env.local"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

# 只发布 arm64-v8a 单架构包（手机端唯一会用到的 ABI）；
# 构建命令：flutter build apk --release --split-per-abi --target-platform android-arm64 --no-shrink
APK_SRC="$ROOT_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
PAGES_DIR="$ROOT_DIR/solace"
APK_DST="$PAGES_DIR/app-release.apk"
APK_GZ="$PAGES_DIR/app-release.apk.gz"
PROJECT_NAME="${CLOUDFLARE_PAGES_PROJECT:-solace-auth}"

WRANGLER_TMP_CONFIG=""
if [[ -n "${CLOUDFLARE_API_TOKEN:-}" && -z "${XDG_CONFIG_HOME:-}" ]]; then
  WRANGLER_TMP_CONFIG="$(mktemp -d)"
  export XDG_CONFIG_HOME="$WRANGLER_TMP_CONFIG"
  trap 'rm -rf "$WRANGLER_TMP_CONFIG"' EXIT
fi

if [[ ! -f "$APK_SRC" ]]; then
  echo "Missing APK: $APK_SRC"
  echo "Build it first with: flutter build apk --release --target-platform android-arm64"
  exit 1
fi

mkdir -p "$PAGES_DIR"
cp "$APK_SRC" "$APK_DST"
gzip -9 -c "$APK_DST" > "$APK_GZ"

if command -v sha1sum >/dev/null 2>&1; then
  sha1sum "$APK_DST" | awk '{print $1}' > "$APK_DST.sha1"
fi

# Cloudflare Pages 单文件上限 25MiB：大 APK 的 gz 需分片上传
# （app-release.apk.gz.aa / .ab / ...，worker 下载时按片拼接再解压）
# 分片清单写入 app-release.apk.gz.manifest，worker 按清单取片（不探测，
# Pages SPA 回退会让不存在路径返回 200，探测会超子请求上限）。
rm -f "$APK_GZ".*
if command -v split >/dev/null 2>&1; then
  split -b 24m "$APK_GZ" "$APK_GZ."
  # worker 只认分片，单片 gz 不传（会超 Pages 上限）
  rm -f "$APK_GZ"
  PARTS_JSON="["
  first=1
  for f in "$APK_GZ".*; do
    [ "$first" = 1 ] || PARTS_JSON="$PARTS_JSON,"
    PARTS_JSON="$PARTS_JSON\"$(basename "$f")\""
    first=0
  done
  PARTS_JSON="$PARTS_JSON]"
  echo "$PARTS_JSON" > "$PAGES_DIR/app-release.apk.gz.manifest"
  echo "GZ parts prepared: $(ls "$APK_GZ".* | wc -l) pieces"
else
  echo "WARN: split not found, uploading monolithic gz (may exceed Pages 25MiB limit)"
fi

echo "APK artifact prepared: $APK_DST"
echo "GZ artifact prepared: $APK_GZ"
rm -f "$APK_DST"

cd "$PAGES_DIR"
if command -v wrangler >/dev/null 2>&1; then
  wrangler pages deploy . --project-name "$PROJECT_NAME"
else
  npx --yes wrangler@latest pages deploy . --project-name "$PROJECT_NAME"
fi
