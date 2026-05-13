# NPM Single-Package Distribution (Optional Platform Binaries)

This repo now includes a scaffold for shipping `weiv` as one installable package that
supports both CLI and bundler adapters.

## Package Layout

- `packages/weiv`
  - CLI launcher: `bin/weiv.mjs`
  - Bundler adapters:
    - `weiv/vite`
    - `weiv/bun`
  - virtual runtime module typing:
    - `weiv:observable`
    - `weiv:router`
  - Source modules under `src/` (including runtime and binary resolver)
- `packages/weiv-<platform>` (stubbed)
  - `@weiv/weiv-darwin-arm64`
  - `@weiv/weiv-darwin-x64`
  - `@weiv/weiv-linux-x64-gnu`
  - `@weiv/weiv-linux-arm64-gnu`
  - `@weiv/weiv-win32-x64-msvc`

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
4. Publish `weiv` package with `optionalDependencies` pointing to matching versions.

## Local Validation

From repo root:

```bash
npm run pkg:smoke
```

This validates:

- `weiv` tarball packs correctly
- bundler adapter exports load (`weiv/vite`, `weiv/bun`)
- CLI launcher resolves and executes with `WEIV_BINARY_PATH`

## Important

Current platform packages are placeholders and intentionally exit with an error.
They must be replaced with real binaries before publishing.
