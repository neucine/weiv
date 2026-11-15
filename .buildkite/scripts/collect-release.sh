#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source .buildkite/scripts/runner-path.sh
platforms=("$@")
test "${#platforms[@]}" -eq 3
for platform in "${platforms[@]}"; do
  destination="dist/release/candidates/$platform"
  mkdir -p "$destination"
  step="${CANDIDATE_STEP_PREFIX:-candidate}-$platform"
  buildkite-agent artifact download 'dist/release/artifacts/*' "$destination" --step "$step"
  buildkite-agent artifact download 'dist/release/state/plan.json' "$destination" --step "$step"
  buildkite-agent artifact download 'dist/release/state/verify.json' "$destination" --step "$step"
done
node .buildkite/scripts/collect-release.mjs "${platforms[@]}"
buildkite-agent artifact upload 'dist/release/collected/*'
