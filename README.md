# weiv

Frontend, with room to breathe.

`weiv` is a compiler-first frontend framework built around single-file components, TypeScript-friendly authoring, and direct DOM codegen.

The project direction is:

- clear separation of template, script, and style
- no JSX requirement
- no framework-wide dependence on `ref()`-style authoring primitives
- a small runtime with more work pushed into the compiler
- browser execution that trends toward compiler-driven DOM updates rather than VDOM

## Status

`weiv` is already runnable, but still early.

Current state:

- Zig compiler pipeline
- Rust-backed TypeScript analysis with `oxc`
- browser emission and preview flow
- scoped CSS emission
- TodoMVC verification app
- workspace-app verification scaffold
- compiler, component, and browser interaction checks

Current runtime status:

- good enough for verification and iteration
- not yet the final browser architecture
- moving from subtree rerendering toward compiler-driven DOM patching
- proxy-tracked shared roots now exist for imports, `props`, and a narrow local-object slice

## What Exists Today

- `.weiv` single-file component parsing
- template parsing, normalization, and binding
- TypeScript script analysis over FFI
- lowered compiler IR
- browser module emission
- generated app bundles with Bun preview support
- a working TodoMVC example used as the main smaller app-scale verification app
- a larger `workspace-app` scaffold used to widen framework capability coverage

## Direction

`weiv` is not trying to become another generic VDOM framework.

The long-term target is:

- compiled `create`
- compiled `update`
- stable component instance records
- minimal browser runtime helpers
- direct DOM operations emitted by the compiler

The current browser runtime is a bridge toward that model.

## Quick Start

Requirements:

- `zig`
- `bun`
- `cargo`

Build and verify:

```bash
zig build test
zig build component-test
```

`zig build render-test` remains as a compatibility alias for the component-test layer.

Optional browser e2e runners live under `test/cypress/`.

Preview TodoMVC:

```bash
zig build run -- dev test/examples/todomvc/App.weiv
```

Preview the workspace app:

```bash
zig build run -- dev test/examples/workspace-app/App.weiv
```

Useful compiler commands:

```bash
zig build run -- compile analyze component test/examples/todomvc/App.weiv
zig build run -- inspect ir test/examples/todomvc/App.weiv
zig build run -- compile emit js test/examples/todomvc/App.weiv
zig build run -- compile test/examples/todomvc/App.weiv .zig-cache/todomvc-out
zig build run -- compile test/examples/workspace-app/App.weiv .zig-cache/workspace-app-out
```

## Repository Layout

```text
docs/      architecture, planning, and design notes
test/component/  Bun component tests over emitted browser modules
test/cypress/    browser e2e runners
test/examples/   verification fixtures and example apps
test/fixtures/   expected bundle/runtime fixtures
libs/      Rust parser backend
src/       Zig compiler, CLI, tests, and FFI layer
tools/     small repo utilities
```

## Key Documents

- [Docs Index](./docs/README.md)
- [Framework Vision](./docs/framework-vision.md)
- [Current Architecture](./docs/architecture.md)
- [Terminology](./docs/terminology.md)
- [Current Status](./docs/status.md)
- [Current Plan](./docs/plan.md)

## Near-Term Focus

- keep selective region scheduling correct and inspectable as the direct DOM path matures
- keep slot composition stable through nested/component-heavy fixtures
- keep compiler-native state scheduling inspectable through `inspect invalidation-graph`
- harden diagnostics and rebuild ergonomics on top of the new `weiv dev` watch loop
- keep TodoMVC as a useful forcing-function app while broadening `workspace-app` into the larger flagship verification app
- preserve a small runtime boundary and move complexity into compiler output
