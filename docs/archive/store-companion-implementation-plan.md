# `@weiv/store` Implementation Plan

## Purpose

This document turns the store companion spec into staged implementation work.

It is retained as an exploratory candidate plan, not as the settled current
roadmap.

It answers:

- what runtime pieces `@weiv/store` needs
- what v1 should deliberately keep small
- how derived stores should work internally
- how store-driven updates should interact with Weiv boundaries
- what we need to verify before using the store in the larger flagship app

Use [Store Companion Spec](./store-companion-spec.md) for the public-facing API
contract.
Use [Shared-State Companion Research](./store-companion-research.md) for the
current comparison that may supersede this candidate.

## Scope

This plan is only for the first optional companion library:

- `@weiv/store`

It is not a router plan, persistence plan, or broad external-state ecosystem.

## Product Goal

`@weiv/store` should give larger Weiv apps a small, explicit answer for shared
or external state without changing the core framework model.

The intended product stance remains:

1. local component state first
2. child event / prop flow next
3. `@weiv/store` only when shared state is genuinely required

## V1 Public Surface

The v1 surface stays intentionally small:

```ts
store(initial)
store(() => derivedValue)
```

Writable store:

- `.value`
- `subscribe(listener): () => void`

Derived store:

- readonly `.value`
- `subscribe(listener): () => void`

No additional effect, reducer, action, persistence, or router API belongs in
v1.

## Internal Runtime Pieces

The implementation should be small but explicit.

Required internal pieces:

1. Base writable store record
- current value
- subscriber set
- change notification

2. Derived store record
- derivation function
- cached value
- dependency subscriptions
- invalidation / recompute path

3. Dependency collection context
- active derived computation
- store-read registration when `.value` is read during derivation

4. Subscription lifecycle
- subscribe
- unsubscribe
- dependency teardown for derived stores

5. Equality / change gate
- avoid notifying when value did not actually change under chosen equality rule

The initial rule should stay simple:

- strict identity / `Object.is`-style change gate

## Writable Store Semantics

Writable stores should behave like explicit shared containers.

Required behavior:

- reading `.value` returns the current value
- assigning `.value = next` updates the stored value
- unchanged assignment does not notify subscribers
- changed assignment notifies subscribers synchronously
- `subscribe(listener)` returns an unsubscribe function

Initial subscription behavior should stay explicit and boring:

- v1 should not require eager initial callback invocation

If eager invocation is ever added later, it should be a separate deliberate
API choice, not an accidental side effect of `subscribe`.

## Derived Store Semantics

Derived stores should be compiler-friendly and runtime-boring.

Desired public mental model:

- a derived store is created from `store(() => ...)`
- reading `.value` gives the current derived value
- subscribing reacts to changes in upstream stores

Internal model for v1:

1. run the derivation function
2. record which writable or derived stores were read through `.value`
3. subscribe to those dependencies
4. recompute when any dependency changes
5. notify downstream subscribers only when the derived value changed

This gives us:

- explicit dependency capture
- no public effect graph API
- no framework hook requirement

## Dependency Tracking Rules

Dependency tracking should stay intentionally narrow:

- only store reads through `.value` inside a running derivation are tracked
- ordinary property reads on plain objects are not tracked
- non-store external reads remain outside store dependency tracking

This is good for v1 because it keeps the model explainable:

- store graph tracking is explicit and local to the companion library
- Weiv core compiler analysis remains a separate concern

## Ownership And Boundaries

This is the most important integration question.

`@weiv/store` itself should stay framework-light, but it must not hide update
ownership.

The initial split should be:

1. Store mutation semantics
- store writes are synchronous
- subscriber callbacks are invoked synchronously

2. Weiv integration semantics
- a store update that happens inside an already-owned Weiv boundary should flush
  correctly because the surrounding boundary is already owned
- a raw store subscription callback remains an external callback unless Weiv
  later wraps it intentionally

That means v1 should remain compatible with both:

- simple raw store subscriptions
- future Weiv-owned subscription helpers

## Owned vs Unowned Store Usage

We should treat these differently in both docs and tests.

Owned-enough path:

- component event handler mutates `myStore.value`
- sibling or imported consumers observe updated store value
- update stays correct because the mutation started in a Weiv-owned boundary

Unowned path:

- external code subscribes to a store and mutates component-visible state from
  that callback
- Weiv should stay conservative and inspectable about that boundary

The store companion should not pretend to solve the second path automatically
in v1.

## Suggested Package Layout

Keep the library extremely small at first.

Suggested shape:

- `packages/store/`
- `packages/store/src/index.ts`
- `packages/store/src/store.ts`
- `packages/store/src/derived.ts`
- `packages/store/src/types.ts`
- `packages/store/README.md`

The exact package location can change, but the implementation should stay
compact enough that the whole library is easy to inspect in one sitting.

## Suggested Type Shapes

The public types can stay close to the spec:

```ts
export type StoreListener<T> = (value: T) => void;

export interface WritableStore<T> {
  value: T;
  subscribe(listener: StoreListener<T>): () => void;
}

export interface DerivedStore<T> {
  readonly value: T;
  subscribe(listener: StoreListener<T>): () => void;
}

export declare function store<T>(initial: T): WritableStore<T>;
export declare function store<T>(derive: () => T): DerivedStore<T>;
```

The implementation can use internal classes or closure records. That choice is
secondary to keeping the semantics small and explicit.

## Verification Plan

We should prove the store in layers, just like the core framework.

### Phase 1. Runtime Unit Coverage

Prove:

- writable `.value` read/write
- unchanged writes do not notify
- changed writes do notify
- unsubscribe works
- derived store recomputes when dependencies change
- derived store does not notify on unchanged derived output

### Phase 2. Integration Sanity With Weiv

Prove:

- a component can import a writable store from a `.ts` module
- store-driven reads render correctly
- a Weiv-owned event can mutate the store and update dependent regions
- sibling consumers stay in sync

### Phase 3. Boundary Honesty

Prove:

- raw external subscription paths stay conservative and inspectable
- store use does not hide unowned callback boundaries
- invalidation/inspect output remains truthful when store-driven state crosses
  component boundaries

### Phase 4. Larger Flagship App Use

Only after the earlier phases are green:

- use `@weiv/store` in one bounded region of `examples/workspace-app`
- keep the rest of the app mostly local-state-first
- use the store region to verify shared-state behavior rather than to define the
  whole app architecture

## Non-Goals For V1

Do not expand v1 into:

- selector APIs
- transaction APIs
- async resource APIs
- persistence
- devtools protocol
- router integration
- deep proxy tracking
- auto-owned subscription magic

If the core store works, later versions can add narrow helpers. V1 should prove
the smallest useful answer first.

## Immediate Next Tasks

1. choose the package location for `@weiv/store`
2. implement the minimal writable store
3. implement the minimal derived store
4. add runtime tests for the store package itself
5. add one small integration example imported from `.ts` into `.weiv`
6. reserve one bounded store region in `examples/workspace-app`

## Exit Criteria

`@weiv/store` is ready enough for the larger verification app when:

- the runtime tests are green
- import/use from `.weiv` works cleanly
- owned event-driven store writes update dependent regions correctly
- unowned store-driven paths remain honest in diagnostics / inspect output
- the API still feels obviously optional rather than core-required
