#!/usr/bin/env bash
# Thin wrapper - real script lives in scripts/deploy.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/deploy.sh" "$@"
