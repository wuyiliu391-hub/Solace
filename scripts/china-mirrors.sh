#!/usr/bin/env bash
set -euo pipefail

export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

echo "export PUB_HOSTED_URL=$PUB_HOSTED_URL"
echo "export FLUTTER_STORAGE_BASE_URL=$FLUTTER_STORAGE_BASE_URL"
echo "Gradle and npm mirrors are configured in the project files."
