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
