# Weiv — v1 Roadmap

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

Goal: `npm install @weiv/compiler` + thin plugins for each bundler. Plugin intercepts `.weiv` imports, calls the compiler, returns compiled JS. Same pattern as `@vue/compiler-sfc` or `svelte/compiler`.

**Plugin architecture:**
```
@weiv/compiler          — core: source in, JS out
@weiv/bun-plugin        — hooks into Bun's plugin API
@weiv/vite-plugin       — hooks into Vite's plugin API
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

**Recommended path:** Start with CLI exec to validate the plugin hooks (resolve, HMR, source maps), then invest in WASM or NAPI-RS for proper npm distribution.

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
