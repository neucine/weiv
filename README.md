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
- compiler, render, and interaction checks

Current runtime status:

- good enough for verification and iteration
- not yet the final browser architecture
- moving from subtree rerendering toward compiler-driven DOM patching

## What Exists Today

- `.weiv` single-file component parsing
- template parsing, normalization, and binding
- TypeScript script analysis over FFI
- lowered compiler IR
- browser module emission
- generated app bundles with Bun preview support
- a working TodoMVC example used as the main smaller app-scale verification app

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
zig build render-test
```

Preview TodoMVC:

```bash
zig build run -- dev examples/todomvc/App.weiv
```

Useful compiler commands:

```bash
zig build run -- compile analyze component examples/todomvc/App.weiv
zig build run -- inspect ir examples/todomvc/App.weiv
zig build run -- compile emit js examples/todomvc/App.weiv
zig build run -- compile examples/todomvc/App.weiv .zig-cache/todomvc-out
```

## Repository Layout

```text
docs/      architecture, planning, and design notes
examples/  verification fixtures and example apps
libs/      Rust parser backend
spec/      framework spec
src/       Zig compiler, CLI, tests, and FFI layer
tools/     render harness and test fixtures
```

## Key Documents

- [Docs Index](./docs/README.md)
- [Current Architecture](./docs/architecture.md)
- [Terminology](./docs/terminology.md)
- [Current Status](./docs/status.md)
- [Current Plan](./docs/plan.md)
- [Framework Spec](./spec/framework-spec.md)

## Near-Term Focus

- keep selective region scheduling correct and inspectable as the direct DOM path matures
- keep slot composition stable through nested/component-heavy fixtures
- keep compiler-native state scheduling inspectable through `inspect invalidation-graph`
- harden diagnostics and rebuild ergonomics on top of the new `weiv dev` watch loop
- keep TodoMVC as a useful forcing-function app while defining a larger flagship verification app
- preserve a small runtime boundary and move complexity into compiler output
