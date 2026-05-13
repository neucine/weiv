# Weiv — v1 Roadmap

## Recently Closed

- [x] Ship single-package npm surface as `weivjs` with:
  - `weiv` CLI
  - `weivjs/vite` and `weivjs/bun` adapter exports
  - optional `weiv:*` typings (`weiv:observable`, `weiv:router`)
- [x] Publish macOS arm64 platform package (`@weivjs/weiv-darwin-arm64`) and `weivjs`
- [x] Add package-level clean-install E2E verification (`npm run test:package`)
- [x] Move VS Code extension into workspace packages and add publish scripts/docs

## Must-Have (blocking v1)

- [x] Reduce `evaluate(...)` fallbacks — compile dynamic expressions to direct access
- [ ] Diagnostics unification — structured author errors across all compiler phases
- [ ] App-scale verification — kanib as the primary confidence anchor
- [ ] `weiv dev` polish — solid authoring loop, rebuild clarity, process ergonomics

## Should-Have (v1 quality bar)

- [ ] Dependency precision — tighter dirty-region guards, reduce unnecessary updates
- [ ] Observable-to-region mapping — shared state wakes specific regions, not whole component
- [ ] IDE `emit` typing — virtual declarations from `export interface Emits`

## Bundler Integration

Goal: `npm install weivjs` with thin bundler adapters. Adapter intercepts `.weiv` imports, calls the compiler, and returns compiled JS.

**Current package architecture:**
```
weivjs                 — CLI + adapter exports
weivjs/bun             — Bun adapter surface
weivjs/vite            — Vite adapter surface
```

**Compiler distribution options (decision pending):**

| Option | How | Pros | Cons |
|--------|-----|------|------|
| WASM | Compile Zig+Rust to `wasm32-wasi`, ship `.wasm` in npm | Single artifact, all platforms, no native deps | Zig+Rust cross-toolchain WASM linking is unproven; ~10% slower |
| Native + NAPI-RS | Prebuilt binaries per platform via `optionalDependencies` | Fastest runtime, proven pattern (SWC, esbuild) | Platform matrix packaging, CI complexity |
| CLI exec | Plugin shells out to `weiv` binary on PATH | Works today, zero new infra | Users install `weiv` separately, process-per-file overhead |

**Industry reference:**
- Svelte, Vue, Angular — compiler is pure JS, direct import. No native code.
- SWC, esbuild, Lightning CSS, Turbopack — native code distributed as platform-specific npm packages via `optionalDependencies`, with optional WASM fallback.

**Weiv compiler stats:** ~9200 lines of Zig (parse → analyze → lower → emit) + ~1700 lines of Rust (Oxc parser backend). Rewriting to JS is not viable.

**Current path:** CLI-exec bridge is implemented inside `weivjs` adapters. Next step is performance/distribution hardening without changing the adapter API.

### Next Actions (Bun + Vite)

- [ ] Improve Bun adapter reliability for larger apps (watch rebuild behavior, diagnostics polish).
- [ ] Improve Vite adapter reliability for larger apps (watch rebuild behavior, diagnostics polish).
- [ ] Add minimal sample apps proving direct `.weiv` import works in Bun and Vite dev mode.
- [ ] Add CI smoke tests for both plugin paths (dev/build or equivalent non-interactive checks).
- [ ] Define migration path from CLI-bridge to native or wasm compiler distribution without changing plugin user API.
- [ ] Replace remaining non-mac platform placeholder binaries and publish full optional-dependency matrix.

See: `docs/archive/bundler-integration-plan.md`

## Post-v1

- SSR / hydration
- Forms package
- Transitions engine
- Public reactivity APIs (signal/ref/proxy)
- Testing helpers
- Async resource primitives

## VS Code Extension DX

- [ ] Diagnostics: run `weiv compile analyze --json` on save, show errors/warnings inline
- [ ] Hover: show type/prop interface on hover for `bind:` values and component tags
- [ ] Autocomplete: suggest script-declared functions/variables inside `bind:` and `on:` attributes
- [ ] Outline: show template structure + script declarations in sidebar symbol view
- [ ] Snippets: common `.weiv` patterns (component scaffold, props, emit)
- [ ] `weiv dev` HMR: hot reload on save instead of full page rebuild
- [ ] Error overlay: show compile errors in the browser during dev
