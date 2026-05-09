# Weiv Companion Libraries

## Purpose

`weiv` core should stay plain-state-first and compiler-first.

That does not mean the ecosystem should stop at core local state.

This document defines the companion-library design space around Weiv's first
official shared-state/runtime answer.

These should be optional companions, not part of the core framework identity.

Use [Shared-State Companion Research](./store-companion-research.md) for the
current candidate comparison before locking the first official shared-state
answer.

## Design Principle

The core framework should remain centered on:

- local mutable state
- child event flow
- compiler-owned scheduling
- direct DOM patching

Companion libraries should exist for cases where larger apps need:

- shared state
- cross-region coordination
- navigation state

But those companions should integrate with Weiv's scheduler and inspect model
instead of dragging the framework into a different mental model.

## Candidate First Companion: `@weiv/store`

One candidate first companion is a small shared-state library.

Why first:

- shared state is a common next need for larger apps
- it directly exercises callback ownership and boundary scheduling
- it provides a realistic companion for the larger verification app
- router design will likely depend on a shared-state story anyway

Use [Store Companion Spec](./store-companion-spec.md) for the current draft API
surface and integration contract.
Use [Store Companion Implementation Plan](./store-companion-implementation-plan.md)
for the staged runtime and verification work behind that contract.

That draft direction is now under active comparison against stronger shared
state and runtime candidates before we finalize the official answer.

## Candidate Direction For `@weiv/store`

The intended model is:

- tiny API
- explicit readable/writable state
- explicit subscription
- no proxy-heavy magic
- no hook-first assumptions
- integration points that can cooperate with Weiv-owned boundaries

Good influences:

- tiny vanilla stores such as Nano Stores

But the recommendation is to borrow the shape, not adopt a third-party library
as the official answer.

## Candidate API Shape

The initial target should stay small.

Possible core primitives:

- `store(initial)`
- `myStore.value`
- `store.subscribe(listener)`
- derived store when `store(...)` receives a function

Optional Weiv-facing integration helpers can come later if needed, but should
stay narrow and explicit.

Example direction:

```ts
import { store } from "@weiv/store";

export const selectedId = store<string | null>(null);
export const items = store<Item[]>([]);

export const visibleItems = store(() => {
  const id = selectedId.value;
  return items.value.filter((item) => item.ownerId === id);
});
```

The intent is:

- one constructor
- explicit shared-state containers
- derived stores through function input
- no required `get()` / `set()` surface

## Normal Usage Boundary

`@weiv/store` should usually be authored in normal `.ts` modules, not inline in
`.weiv` files.

That keeps the boundary clear:

- `.weiv` stays focused on component UI and local state
- `@weiv/store` is for shared/external state between components

Typical usage should be:

1. define stores in a `.ts` module
2. import them into `.weiv` components
3. use them only where shared state is genuinely needed

## What `@weiv/store` Should Test

The companion store should help verify:

- shared state across sibling regions
- callback ownership around store subscriptions
- inspectability of owned vs unowned subscription paths
- whether conservative behavior remains correct when updates originate outside
  direct template events

## What `@weiv/store` Should Not Become

It should not become:

- the default required way to write Weiv apps
- a proxy-first runtime
- a giant state ecosystem before the core model settles
- a replacement for normal local component state

The intended product stance is:

- local component state first
- `@weiv/store` only when shared state is required

## Later Companion: `@weiv/router`

Router work should come after the store companion direction is clear.

Why later:

- router state also needs a clean shared-state story
- router transitions will interact with scheduler ownership
- we should not design store and router simultaneously without proving one
  integration path first

The intended order remains:

1. settle the shared-state/runtime direction
2. validate it in one bounded area of the larger verification app
3. validate diagnostics / inspectability / owned-boundary behavior
4. then design `@weiv/router`

## Verification Role

The larger flagship verification app should eventually use `@weiv/store` in one
bounded area.

That use should be:

- small
- deliberate
- easy to inspect
- not dominant over the app's normal local-state model

This keeps the ecosystem direction honest:

- core Weiv remains plain-state-first
- companion state is real and supported
- larger apps have a recommended path without redefining the framework
