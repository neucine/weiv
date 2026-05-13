# NPM Single-Package Distribution (Optional Platform Binaries)

This repo now includes a scaffold for shipping `weivjs` as one installable package that
supports both CLI and bundler adapters.

## Package Layout

- `packages/weiv`
  - CLI launcher: `bin/weiv.mjs`
  - Bundler adapters:
    - `weivjs/vite`
    - `weivjs/bun`
  - virtual runtime module typing:
    - `weiv:observable`
    - `weiv:router`
  - Source modules under `src/` (including runtime and binary resolver)
- `packages/weiv-<platform>` (stubbed)
  - `@weivjs/weiv-darwin-arm64`
  - `@weivjs/weiv-darwin-x64`
  - `@weivjs/weiv-linux-x64-gnu`
  - `@weivjs/weiv-linux-arm64-gnu`
  - `@weivjs/weiv-win32-x64-msvc`

## Resolution Order

`packages/weiv/src/platform.mjs` resolves the executable in this order:

1. `WEIV_BINARY_PATH`
2. platform optional dependency package binary
3. fail with actionable guidance

(Download fallback is not wired yet; add later if desired.)

## Release Workflow (Target)

1. Build platform binaries from CI.
2. Replace placeholder files in `packages/weiv-*/bin`.
3. Publish platform packages first.
4. Publish `weivjs` package with `optionalDependencies` pointing to matching versions.

## Local Validation

From repo root:

```bash
npm run pkg:smoke
```

This validates:

- `weivjs` tarball packs correctly
- bundler adapter exports load (`weivjs/vite`, `weivjs/bun`)
- CLI launcher resolves and executes with `WEIV_BINARY_PATH`

## Important

`@weivjs/weiv-darwin-arm64` is now backed by a real binary path in this repo
and is suitable for macOS arm64 distribution. Other platform packages still
use placeholders and must be replaced with real binaries before full
cross-platform publishing.
