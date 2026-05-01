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
- a working TodoMVC example used as the main verification app

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
zig build run -- analyze-component examples/todomvc/App.weiv
zig build run -- dump-ir examples/todomvc/App.weiv
zig build run -- emit-js examples/todomvc/App.weiv
zig build run -- emit-app examples/todomvc/App.weiv .zig-cache/todomvc-out
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

- [Framework Spec](./spec/framework-spec.md)
- [Execution Plan](./docs/execution-plan.md)
- [Compiler Architecture](./docs/compiler-architecture.md)
- [Browser Codegen Direction](./docs/browser-codegen.md)
- [Composition Model](./docs/composition-model.md)
- [Composition Implementation](./docs/composition-implementation.md)
- [Framework Scope](./docs/framework-scope.md)
- [Syntax Decisions](./docs/syntax-decisions.md)
- [FFI Design](./docs/ffi-design.md)
- [Backend API: Script Analysis](./docs/backend-api-script-analysis.md)

## Near-Term Focus

- replace generic browser subtree rerendering with compiled DOM update paths
- add a real composition model, likely slots or an equivalent content projection mechanism
- define the public state/reactivity model after composition is clearer
- harden `weiv dev` into a stronger watch/rebuild workflow
- keep TodoMVC as the forcing-function verification app
- preserve a small runtime boundary and move complexity into compiler output
