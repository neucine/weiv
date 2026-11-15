#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
version="${CYNA_VERSION:-0.5.3}"
test "$(git rev-parse HEAD)" = "${BUILDKITE_COMMIT:?Buildkite commit required}"
node --test .buildkite/scripts/publish-release.test.mjs
for host in "aarch64-apple-darwin" x86_64-unknown-linux-gnu x86_64-pc-windows-gnu; do
  extension=tar.gz
  if [ "$host" = x86_64-pc-windows-gnu ]; then extension=zip; fi
  curl --fail --head --location --retry 2 --silent --show-error \
    "https://downloads.cyna.dev/distributions/$version/$host.$extension" >/dev/null
  echo "Cyna $version distribution available for $host"
done
