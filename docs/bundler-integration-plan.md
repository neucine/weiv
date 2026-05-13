# Bundler Integration Plan (Bun + Vite)

This plan defines the next delivery track after the VS Code extension:
first-class bundler integration for `.weiv` imports.

## Goals

- Allow importing `.weiv` files directly in Bun and Vite projects.
- Keep compiler semantics in `@weiv/compiler`; bundler plugins stay thin.
- Start with a reliable, easy-to-ship bridge (`CLI exec`) and then optimize.

## Target Packages

- `@weiv/compiler`
- `@weiv/bun-plugin`
- `@weiv/vite-plugin`

## Phase 1 (Now): Plugin POC via CLI Exec

Ship a minimal plugin for each bundler that:

1. intercepts `.weiv` requests
2. calls `weiv compile emit js <file>`
3. returns JavaScript to the bundler

Why first:

- zero native packaging work
- validates plugin surface, HMR behavior, diagnostics UX, and sourcemap plumbing
- fastest path to real user feedback

### Bun Plugin Scope

- plugin entry exports a `BunPlugin`
- use `onResolve` for `.weiv` specifiers
- use `onLoad` to compile `.weiv` to JS
- include watch-friendly rebuild behavior

### Vite Plugin Scope

- plugin factory `weiv()` returning a Vite plugin
- implement `resolveId`, `load`, and `transform` only where needed
- avoid framework magic; keep plugin behavior explicit and inspectable
- resolve virtual runtime imports:
  - `weiv:observable`
  - `weiv:router`

## Phase 2: Runtime + CSS + Sourcemaps

- runtime import rewriting and runtime availability in bundled output
- style handling strategy for `.weiv` `<style>` sections
- working sourcemaps from transformed `.weiv` sources
- author-facing diagnostics mapped to original source locations

## Phase 3: Distribution Upgrade

Replace CLI exec with one of:

- native prebuild distribution (fastest)
- wasm distribution (single artifact, slower, simpler install)

Keep the plugin API and user config stable across the swap.

## Acceptance Criteria

- Bun: demo app can import `.weiv` and run with watch rebuilds.
- Vite: demo app can import `.weiv` and run in dev + build.
- both: diagnostics report useful source locations.
- both: Kanib/Todo fixture smoke apps can run through plugin path.

## Out of Scope (This Track)

- SSR/hydration behavior
- framework-owned router adapters
- large plugin ecosystem abstractions
- re-architecting compiler internals
