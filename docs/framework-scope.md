# Framework Scope

## Purpose

This document defines the feature scope for `weiv` in terms of:

- what is required for the framework direction
- what is valuable later but not core right now
- what is intentionally not a framework goal unless the project direction changes

The goal is to stop roadmap drift toward generic framework parity and keep decisions aligned with `weiv`'s compiler-first, direct-DOM direction.

## Direction Constraint

`weiv` is not trying to become:

- a generic VDOM framework
- a kitchen-sink app platform
- a framework that solves every frontend concern in core

`weiv` is trying to become:

- a compiler-first frontend framework
- direct-DOM by default
- small at runtime
- strong in authoring clarity
- strong in browser and SSR compilation targets

## Required

These are required if `weiv` is to become a serious framework in its own lane.

### 1. Formal Reactive and State Model

`weiv` needs:

- a clear public state/update model
- explicit rules for local mutable state
- a minimal story for cross-component state or shared state
- a model that fits compiler-driven updates rather than generic runtime magic

Without this, the runtime can work, but the framework still lacks a real authoring model.

### 2. Strong Browser Runtime Semantics

`weiv` needs:

- predictable event/update behavior
- reliable input/edit semantics
- stable component boundaries
- compiler-driven DOM patching as the primary browser path

This is core to the project direction, not optional polish.

### 3. Better Developer Workflow

`weiv` needs:

- `weiv dev` with watch/rebuild behavior owned by the framework
- a stable local preview loop
- good enough sourcemaps and diagnostics for real use

Without this, the framework remains impressive internally but awkward to use.

### 4. Better Diagnostics and Type Feedback

`weiv` needs:

- strong template binding errors
- clearer prop misuse diagnostics
- better source spans
- better TypeScript-facing authoring feedback

This is product work, not cleanup.

### 5. Composition Model

`weiv` needs:

- slots or an equivalent content projection model
- a clearer story for reusable component composition

Without this, component authoring stays narrower than it should be.

Current direction:

- use slots as the primary composition model
- ship default and named slots before more advanced composition features

### 6. SSR as a Real Target

If `weiv` wants to be a serious framework beyond interactive demos, it needs:

- SSR as an intentional compile target
- a server-side output contract that matches the compiler-first direction
- eventual hydration or a clear alternative browser/server integration model

This does not need to come before the browser path is strong, but it is still a required long-term capability.

## Later

These matter, but they are not the right first priorities.

### Browser Runtime Refinement

- more efficient keyed reconciliation
- less emitted helper noise
- stronger update caching and invalidation
- further cleanup of the browser DOM plan

### Form and Input Model

- richer input binding semantics
- better controlled/uncontrolled rules
- more complete event/form coverage

### Async and Loading Story

- async component boundaries
- loading/error surfaces
- code-splitting-aware component loading

### Tooling Polish

- stronger sourcemaps
- editor integration
- debugging ergonomics
- packaging/publishing polish

### Build and Module Graph Hardening

- cleaner asset handling
- more complete non-`.weiv` import support
- more robust production emission flow

These should come after the core compiler/runtime direction is fully stable.

## Not Planned

These are not core goals for `weiv` unless the project direction changes.

### 1. VDOM

Not planned:

- generic VDOM diffing
- a long-term runtime built around virtual tree reconciliation

This conflicts with the compiler-driven DOM direction.

### 2. Large Lifecycle API Surface

Not planned:

- many lifecycle hooks just to match other frameworks
- framework-wide lifecycle taxonomy without strong architectural need

The runtime should stay simpler than that.

### 3. Framework-Mandated Global Store

Not planned:

- a heavy built-in store system as part of the core identity

`weiv` may need a shared state story, but not a large opinionated store framework in core.

### 4. Full App Platform by Default

Not planned right now:

- framework-owned router
- data loader/action framework
- middleware conventions
- full-stack app conventions

Those are only worth doing if `weiv` intentionally expands from framework to app platform.

### 5. Native Renderer as a Near-Term Goal

Not planned:

- chasing native renderer targets early

The browser target and SSR target are the meaningful priorities first.

### 6. Plugin System Too Early

Not planned:

- extensibility architecture before the framework surface is stable

That would create more surface area before the core is settled.

## Priority Order

If choices become unclear, use this order:

1. browser direct codegen/runtime correctness
2. composition model
3. public state/reactivity model
4. `weiv dev` and diagnostics
5. SSR target
6. later tooling and ecosystem polish

## Current Implementation Order

Within the required set, the current order is:

1. composition model
2. public state/reactivity model
3. `weiv dev` workflow

The reasoning is:

- composition changes the component surface directly, so it should be settled before wider state APIs grow around the wrong component model
- state/reactivity should be designed after the composition boundary is clearer
- `weiv dev` remains required, but it is less architecturally foundational than the previous two

## Review Rule

When evaluating a feature request, ask:

1. Is this required for `weiv`'s compiler-first direction?
2. Is it useful later, but not worth current complexity?
3. Is it common elsewhere but not actually part of `weiv`'s goal?

If the answer is mostly "other frameworks have it", that is not enough.
