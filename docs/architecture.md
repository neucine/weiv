# Weiv Architecture

## Direction

`weiv` is a compiler-first frontend framework.

The normalized vocabulary for this model lives in
[Terminology](./terminology.md).

The next implementation-focused upgrade for script-side precision is documented
in [AST Script Analysis Plan](./ast-script-analysis-plan.md).
The current next-direction for cross-component/shared state is documented in
[Shared Observable State Design](./shared-observable-state-design.md).

The current direction is:

- `.weiv` single-file components
- TypeScript script blocks
- template-first authoring
- scoped CSS
- direct DOM browser output
- small runtime helpers
- compiler-owned state scheduling and patch planning

`weiv` should not center its default model around signals, refs, proxies, a
virtual DOM, or public effect graphs.

Where plain TypeScript becomes too ambiguous for trustworthy compile-time state
analysis, `weiv` should first strengthen script-side precision through
AST-backed backend analysis and explicit diagnostics. For state that escapes
simple owned component boundaries, the current next-direction is explicit shared
observable state created at the source rather than trying to proxy plain shared
objects later inside consuming components.

Optional ecosystem/runtime companions are still valid, but they are no longer
part of the active top-level implementation track. The current architecture is
centered on the compiler/runtime foundation already on `main`.

The intended state split is:

- local owned state stays simple and compiler-first
- shared state beyond the component boundary should move through a Weiv-owned
  observable runtime contract

## Component Syntax

Current component shape:

```html
<template>
  ...
</template>

<script lang="ts">
  export interface Props {
    title: string;
  }

  export interface Emits {
    save: { id: number };
  }

  export let props: Props;

  function save() {
    emit("save", { id: 1 });
  }
</script>

<style>
  ...
</style>
```

Supported template features include:

- interpolation: `{{ expr }}`
- event binding: `on:click="handler"`
- attribute/property binding: `bind:disabled="expr"`
- conditionals: `if` / `else`
- loops: `for="item in items"`
- child components through capitalized tags
- slots: `<slot>`, named slots, fallback content, and `<template slot:name>`

## Component Contract

Component inputs use the conventional `props` binding:

```ts
export interface Props {
  title: string;
}

export let props: Props;
```

Component events use the Weiv-provided `emit` function:

```ts
export interface Emits {
  save: { id: number };
  cancel: null;
}

function save() {
  emit("save", { id: 1 });
}
```

`props` is explicit author code so TypeScript can name the input object. `emit`
is a framework-provided binding injected by Weiv. `export interface Emits` is
the conventional event contract for diagnostics and IDE tooling.

User-defined `emit` bindings conflict with the framework event facility and
produce a compiler diagnostic. The future IDE plugin should provide virtual
types for `emit` from `Emits` so normal TypeScript editing still works.

## Compiler Pipeline

The current pipeline is:

1. SFC parse
2. template parse
3. template normalization
4. Rust-backed TypeScript script analysis through FFI
5. template-to-script binding
6. IR lowering
7. browser-plan lowering
8. direct browser JS/CSS emission

Zig owns the compiler pipeline, diagnostics assembly, lowering, code emission,
CLI, and app bundling. The Rust backend currently owns parser-heavy TypeScript
analysis through `oxc`.

## Browser Output

The direct browser path emits retained DOM programs:

- `createDom(instance)`
- `updateDom(instance)`
- `destroyDom(instance)`
- region update functions such as `updateRegion_text_*`
- small structural helpers for boundaries, loops, slots, and movement

The direct path is the primary browser architecture. The older render/runtime
path remains useful for compatibility and comparison, but it is not the target
execution model.

## State And Scheduling

The state model is compiler-native scoped invalidation.

The mental model is:

- templates declare observation points
- the compiler defines update regions
- owned boundaries schedule updates
- dirty bindings select dirty regions when possible
- regions reevaluate their own expressions
- generated patch code mutates retained DOM directly

Current region kinds:

- `text`
- `attribute`
- `conditional`
- `loop`
- `child`
- `slot`

Current owned boundaries:

- template event handlers
- compiler-emitted child event handlers
- compiler-emitted slot update boundaries
- async functions invoked from owned event handlers
- component-local timer/frame callbacks wrapped in setup for `setTimeout`,
  `setInterval`, `queueMicrotask`, and `requestAnimationFrame`

Unsupported visible stale-risk patterns should diagnose instead of silently
compiling into stale UI behavior.

`weiv inspect invalidation-graph <path>` is the current inspectability command
for regions, dependencies, mutation sites, owned boundaries, and diagnostics.

## Composition

Slots are the current composition model.

Supported now:

- default slots
- named slots
- fallback content
- grouped named slots with `<template slot:name>`
- projected slot updates from parent-owned state
- switching between projected content and fallback after mount

Deferred:

- scoped slot props
- dynamic slot names
- portal/teleport semantics

## Diagnostics

Diagnostics are part of the product surface, not cleanup.

The compiler should prefer clear errors for patterns that look reactive but are
outside the owned scheduling model. Source-located diagnostics already exist for
several template and composition mistakes, and invalidation-graph diagnostics cover the
current stale-risk cases. `compile analyze component` now also summarizes
current warnings and rewrite guidance, so users do not need to rely only on
`inspect invalidation-graph` to understand the current precision model.

## Scheduling

The current direct-browser scheduling flow is documented in
[Runtime Scheduling](./runtime-scheduling.md).

That document is the source of truth for:

- owned-boundary flush timing
- shared-observable microtask flush timing
- subscription lifecycle
- current ordering semantics
- the exact guarantee around tracked captured references

## Inspectability Commands

Useful commands:

```sh
zig build run -- compile analyze component test/examples/todomvc/App.weiv
zig build run -- inspect ir test/examples/todomvc/App.weiv
zig build run -- inspect browser-plan test/examples/todomvc/App.weiv
zig build run -- inspect invalidation-graph test/examples/basic/basic-counter.weiv
zig build run -- compile emit js test/examples/basic/basic-counter.weiv
zig build run -- compile test/examples/todomvc/App.weiv .zig-cache/todomvc-out
```
