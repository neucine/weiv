#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/buildkite/runner-path.sh
platform="${1:?platform required}"
case "$platform:$(uname -s):$(uname -m)" in
  macos:Darwin:arm64|linux:Linux:x86_64) ;;
  *) echo "Wrong runner for $platform" >&2; exit 1 ;;
esac
buildkite-agent artifact download 'dist/release/collected/manifest.json' . --step merged-collect-release
node scripts/buildkite/published-smoke.mjs
