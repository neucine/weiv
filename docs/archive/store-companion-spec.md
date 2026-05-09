# `@weiv/store` Companion Spec

## Status

Exploratory draft.

This records one candidate first companion-library contract for `weiv`.

It is optional and is not part of core component authoring.

Use [Companion Libraries](./companion-libs.md) for the broader ecosystem
direction.
Use [Store Companion Implementation Plan](./store-companion-implementation-plan.md)
for the staged runtime and verification work behind this API.
Use [Shared-State Companion Research](./store-companion-research.md) for the
current comparison that may supersede this draft direction.

## Purpose

`@weiv/store` exists for shared or external state.

It should be the recommended companion when:

- state must be shared across components
- state must live outside one component
- updates may originate outside direct template events

It should not replace normal local component state.

## Product Position

The intended hierarchy is:

1. local component state first
2. child event / prop flow next
3. `@weiv/store` only when shared state is genuinely required

This keeps `weiv` plain-state-first while still giving larger apps a clear
shared-state path.

## Authoring Boundary

`@weiv/store` should normally be authored in `.ts` modules, not inline in
`.weiv` files.

Typical usage:

1. define stores in a `.ts` module
2. import them into `.weiv` components
3. use them only where shared/external state is needed

## Core API

The v1 surface should stay deliberately small.

### Constructor

```ts
store(initial)
store(() => derivedValue)
```

Rules:

- value input creates a writable store
- function input creates a derived store

## Store Shape

Writable store:

```ts
type WritableStore<T> = {
  value: T;
  subscribe(listener: (value: T) => void): () => void;
};
```

Derived store:

```ts
type DerivedStore<T> = {
  readonly value: T;
  subscribe(listener: (value: T) => void): () => void;
};
```

The point of `.value` is:

- explicit shared-state container semantics
- easy AST recognition
- easier compiler/diagnostic integration than clever overloaded APIs

## Example

```ts
import { store } from "@weiv/store";

export const selectedId = store<string | null>(null);
export const items = store<Item[]>([]);

export const visibleItems = store(() => {
  const id = selectedId.value;
  return items.value.filter((item) => item.ownerId === id);
});
```

In `.weiv`:

```ts
<script lang="ts">
  import { selectedId, visibleItems } from "./workspace-state.ts";

  export interface Props {}
  export let props: Props;
</script>
```

## Derived Semantics

For v1, derived stores should stay simple.

Goals:

- derived values recompute from store reads
- no giant effect/runtime graph API exposed to users
- no requirement that core `weiv` components use stores internally

The implementation may use dependency tracking internally, but the public mental
model should remain:

- writable store with `.value`
- derived store from `store(() => ...)`

## Subscription Contract

`subscribe(listener)` should:

- synchronously register the listener
- return an unsubscribe function
- invoke listeners whenever the store value changes

The spec does not require immediate initial invocation in v1. If we choose one
behavior, it should be documented explicitly and tested.

## Integration With Weiv

This is the critical part.

`@weiv/store` is not just a data structure library. It must integrate with
Weiv's scheduler and diagnostics model.

Desired integration properties:

- store-originated updates remain correct
- owned vs unowned subscription paths are inspectable
- conservative fallback remains honest
- the larger verification app can show the difference clearly

## Owned vs Unowned Store Boundaries

The first version does not need to solve every subscription pattern.

But it should make the distinction clear:

- plain raw `subscribe(...)` may still be unowned unless intentionally wrapped
- Weiv can later add a narrow owned-subscription integration helper if needed

This means the store spec should stay compatible with both:

- simple raw subscription usage
- future Weiv-owned subscription helpers

## Non-Goals

V1 should not include:

- proxy-based deep reactivity
- action/reducer architecture
- framework hook integrations
- a broad effect API
- router semantics
- persistence APIs

## Verification Requirements

Before calling the companion ready enough for the larger verification app, we
should prove:

- writable store reads/writes behave as expected
- derived store values update correctly
- subscription/unsubscribe works
- at least one shared-state example works across sibling regions
- inspect/diagnostic output stays honest for store-driven updates

## Relationship To `@weiv/router`

`@weiv/router` should come later.

The store companion should be proven first, because router state and transitions
will likely depend on the same shared-state and boundary-integration story.
