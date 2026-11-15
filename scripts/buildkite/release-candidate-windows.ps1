$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '../..'))
# Apply repository line endings even when this agent reuses an older checkout.
git -c core.autocrlf=false checkout-index --all --force
if ($LASTEXITCODE -ne 0) { throw 'Checkout line ending setup failed' }
# Buildkite cleans untracked checkout files between builds. Keep compiler outputs
# outside the checkout and recreate only the directory junctions each time.
$cacheRoot = 'C:\neucine-tools\cache\weiv'
foreach ($cache in @(
  @{ Link = 'libs/parser-backend/target'; Store = 'cargo-target' },
  @{ Link = '.cyna-cache'; Store = 'cyna-cache' }
)) {
  $link = Join-Path (Get-Location).Path $cache.Link
  $store = Join-Path $cacheRoot $cache.Store
  New-Item -ItemType Directory -Force -Path $store | Out-Null
  if (Test-Path $link) {
    $item = Get-Item $link -Force
    if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      throw "Checkout cache path is a real directory: $link"
    }
    Remove-Item $link -Force
  }
  New-Item -ItemType Junction -Path $link -Target $store | Out-Null
  Write-Host "Persistent build cache: $link -> $store"
}
$env:CARGO_HOME = 'C:\neucine-tools\cargo'
$env:RUSTUP_HOME = 'C:\neucine-tools\rustup'
$env:CARGO_BUILD_JOBS = '1'
$env:PATH = "C:\msys64\mingw64\bin;C:\neucine-tools\node-v22.22.1-win-x64;C:\neucine-tools\bun-windows-x64;$(Join-Path $env:CARGO_HOME 'bin');$env:PATH"
if (-not $env:BUILDKITE_COMMIT -or (git rev-parse HEAD) -ne $env:BUILDKITE_COMMIT) {
  throw 'Checkout does not match Buildkite commit'
}
if ($env:BUILDKITE_BRANCH -match '^release/v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)$') {
  $version = $Matches[1]
} elseif ($env:BUILDKITE_BRANCH -eq 'main') {
  $version = buildkite-agent meta-data get release_version
  if ($LASTEXITCODE -ne 0 -or $version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?$') { throw 'Missing merged release version' }
} else {
  throw 'Expected release/vX.Y.Z or merged main build'
}
if (-not [Environment]::Is64BitOperatingSystem -or $env:OS -ne 'Windows_NT') {
  throw 'Windows x64 runner required'
}
$cynaVersion = if ($env:CYNA_VERSION) { $env:CYNA_VERSION } else { '0.5.3' }
$uri = "https://downloads.cyna.dev/distributions/$cynaVersion/x86_64-pc-windows-gnu.zip"
$env:HOME = $env:USERPROFILE
$install = Join-Path $env:HOME ".cyna\$cynaVersion"
$cynaExe = Join-Path $install 'bin/cyna.exe'
$ready = Join-Path $install '.complete'
if (-not (Test-Path $ready)) {
  $archive = Join-Path $env:TEMP "cyna-$cynaVersion-windows.zip"
  $staging = Join-Path $env:TEMP "cyna-weiv-$cynaVersion"
  if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $staging | Out-Null
  New-Item -ItemType Directory -Force -Path $install | Out-Null
  Invoke-WebRequest -Uri $uri -OutFile $archive
  tar -xf $archive -C $staging
  if ($LASTEXITCODE -ne 0) { throw 'Cyna distribution extraction failed' }
  Copy-Item -Path (Join-Path $staging 'x86_64-pc-windows-gnu/*') -Destination $install -Recurse -Force
  if (-not (Test-Path $cynaExe)) { throw 'Cyna distribution is incomplete' }
  Remove-Item $staging -Recurse -Force
  Remove-Item $archive
  New-Item -ItemType File -Path $ready -Force | Out-Null
}
if (-not (Test-Path $cynaExe)) { throw 'Cyna distribution is incomplete' }
$env:PATH = "$(Join-Path $install 'bin');$(Join-Path $install 'llvm/bin');$env:PATH"
cyna version
if ($LASTEXITCODE -ne 0) { throw 'Cyna distribution cannot start' }
rustup target add x86_64-pc-windows-gnu
if ($LASTEXITCODE -ne 0) { throw 'Windows Rust target setup failed' }
npm ci --ignore-scripts --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
npm ci --prefix packages/vscode-extension --ignore-scripts --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw 'extension install failed' }
npm test --prefix packages/vscode-extension
if ($LASTEXITCODE -ne 0) { throw 'extension tests failed' }
node tools/release.mjs plan --version=$version --preflight-only
if ($LASTEXITCODE -ne 0) { throw 'release preflight failed' }
npm run build:cyna
if ($LASTEXITCODE -ne 0) { throw 'Windows binary build failed' }
node tools/release.mjs plan --version=$version
if ($LASTEXITCODE -ne 0) { throw 'release plan failed' }
node tools/release.mjs verify
if ($LASTEXITCODE -ne 0) { throw 'release verification failed' }
buildkite-agent artifact upload 'dist/release/artifacts/*'
if ($LASTEXITCODE -ne 0) { throw 'artifact upload failed' }
buildkite-agent artifact upload 'dist/release/state/*.json'
if ($LASTEXITCODE -ne 0) { throw 'state upload failed' }
