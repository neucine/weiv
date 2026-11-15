#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source .buildkite/scripts/runner-path.sh
node .buildkite/scripts/detect-merged-release.mjs
