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

APK_SRC="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
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

APK_MB=$(node -e "console.log((require('fs').statSync(process.argv[1]).size/1024/1024).toFixed(1))" "$APK_DST")
GZ_MB=$(node -e "console.log((require('fs').statSync(process.argv[1]).size/1024/1024).toFixed(1))" "$APK_GZ")
echo "APK: ${APK_MB}MB -> GZ: ${GZ_MB}MB"
rm -f "$APK_DST"

cd "$PAGES_DIR"
if command -v wrangler >/dev/null 2>&1; then
  wrangler pages deploy . --project-name "$PROJECT_NAME"
else
  npx --yes wrangler@latest pages deploy . --project-name "$PROJECT_NAME"
fi
