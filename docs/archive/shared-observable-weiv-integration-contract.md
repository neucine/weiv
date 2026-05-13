# Shared Observable Weiv Integration Contract

This document defines the narrow bridge between the standalone shared
observable runtime and compiler-generated `.weiv` component code.

Use [Shared Observable State Design](./shared-observable-state-design.md) for
the broader direction. This document is about the actual contract the compiler
is allowed to depend on.

## Goal

Keep the public runtime surface small while still giving the compiler a stable
integration seam.

The public `weiv:observable` story should stay simple:

- `observable(value)`

The compiler should not need a broad public helper API just to consume shared
observable state.

## Public Runtime Surface

Current intended public package surface:

1. `observable(value)`

That is the source-side contract for shared state modules.

## Compiler-Stable Internal Contract

Compiler-generated component code is allowed to rely on:

1. a stable observable brand identity
2. stable observable metadata attached to branded observable objects

Today that means:

- a hidden brand symbol
- metadata reachable through that symbol
- metadata containing at least what generated code needs to:
  - recognize an observable
  - register a listener
  - remove a listener later

The compiler should **not** rely on unrelated runtime implementation details
such as:

- exact queue storage
- exact snapshot cloning internals
- arbitrary helper wrappers that may remain non-public

## Current Integration Shape

When a `.weiv` component imports shared observable state:

1. the shared module creates the value with `observable(...)`
2. generated component setup preserves that imported observable value
3. generated component mount subscribes the instance through the observable
   metadata contract
4. generated component destroy unsubscribes the instance
5. observable notifications wake the existing component update path

## Recognition Rule

The current conservative rule is:

- only imported values that are already branded observables participate in the
  shared observable integration path

That keeps the model explicit and avoids retroactive wrapping of arbitrary plain
shared objects.

## Scheduling Rule

The first integration pass remains conservative:

- observable change notifies the subscribed component instance
- Weiv runs the existing instance update path

Weiv still owns:

- component instance lifecycle
- region scheduling
- DOM patch execution

## Non-Goals

This contract does not imply:

- local component state should become observable
- components should manually call `subscribe()` or `snapshot()`
- the public package surface needs to expose every internal helper

## Why This Boundary Is Useful

It gives Weiv a clean split:

- **user/shared-module contract**: `observable(...)`
- **compiler contract**: brand + metadata

That keeps the compiler relatively independent from the public runtime API
shape, while keeping shared-state creation explicit and teachable.
