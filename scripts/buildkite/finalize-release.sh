#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/buildkite/runner-path.sh
export GH_TOKEN="${GITHUB_RELEASE_TOKEN:?GITHUB_RELEASE_TOKEN is required}"
buildkite-agent artifact download 'dist/release/collected/*' . --step merged-collect-release
tag="$(node -p "JSON.parse(require('fs').readFileSync('dist/release/collected/manifest.json')).tag")"
commit="$(node -p "JSON.parse(require('fs').readFileSync('dist/release/collected/manifest.json')).commit")"
test "$commit" = "${BUILDKITE_COMMIT:?Buildkite commit required}"
test "$(git ls-remote origin "refs/tags/$tag^{}" | cut -f1)" = "$commit"
if ! gh release view "$tag" >/dev/null 2>&1; then
  gh release create "$tag" --verify-tag --title "Weiv $tag" \
    --notes "Verified by Buildkite build ${BUILDKITE_BUILD_URL:?}."
fi
for source in dist/release/collected/*.tgz dist/release/collected/SHA256SUMS dist/release/collected/manifest.json; do
  name="$(basename "$source")"
  if ! gh release view "$tag" --json assets --jq '.assets[].name' | grep -Fxq "$name"; then
    gh release upload "$tag" "$source"
  fi
done
download="$(mktemp -d)"
trap 'rm -rf "$download"' EXIT
gh release download "$tag" --dir "$download"
for source in dist/release/collected/*.tgz dist/release/collected/SHA256SUMS dist/release/collected/manifest.json; do
  cmp "$source" "$download/$(basename "$source")"
done
gh release view "$tag" --json tagName,url
