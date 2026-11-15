$ErrorActionPreference = 'Stop'
$env:PATH = "C:\neucine-tools\node-v22.22.1-win-x64;C:\neucine-tools\bun-windows-x64;$env:PATH"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '../..'))
buildkite-agent artifact download 'dist/release/collected/manifest.json' . --step merged-collect-release
if ($LASTEXITCODE -ne 0) { throw 'Release manifest download failed' }
node .buildkite/scripts/published-smoke.mjs
if ($LASTEXITCODE -ne 0) { throw 'Published package smoke check failed' }
