#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/buildkite/runner-path.sh
export GH_TOKEN="${GITHUB_RELEASE_TOKEN:?GITHUB_RELEASE_TOKEN is required}"
test "$(git rev-parse HEAD)" = "${BUILDKITE_COMMIT:?Buildkite commit required}"
test "${BUILDKITE_BRANCH:?Buildkite branch required}" = main
buildkite-agent artifact download 'dist/release/collected/*' . --step merged-collect-release
node scripts/buildkite/publish-release.mjs
