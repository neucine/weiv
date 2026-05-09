# Runtime Scheduling

This document records the current direct-browser runtime scheduling flow on
`main`.

It exists for two reasons:

- make the current timing model explicit
- give future scheduler changes a concrete baseline to compare against

## Scope

This describes the current direct browser path:

- component-local invalidation graphs
- proxy-tracked roots
- owned-boundary flushes
- tracked-path microtask flushes

It does **not** describe a future global app scheduler.

## Current Model

The current model is a hybrid:

- Weiv decides when to enqueue work
- the JavaScript engine owns microtask timing
- Weiv runs synchronous component updates inside the flush

Conceptually:

1. a mutation happens
2. Weiv either:
   - flushes at the end of an owned boundary
   - or schedules a microtask for proxy-tracked path dirtiness
3. the flush iterates subscribed component instances
4. each instance updates synchronously through its own compiled region graph

## Component Scope

The invalidation graph is component-scoped, not global.

Each compiled component module has:

- its own `trackedStateGraph`
- its own region-to-path mapping
- its own subscribed instances

If multiple components observe the same underlying shared object, each component
still uses its own compiled graph to decide which of its own regions update.

## Subscription

Tracked-root subscription is explicit in generated code, but internal to Weiv.

When a component instance is created, generated code registers it:

```js
__weiv_registerTrackedSubscriber(instance);
```

When the instance is destroyed, generated code unregisters it:

```js
__weiv_unregisterTrackedSubscriber(instance);
```

Users do not subscribe manually.

## Two Flush Paths

There are currently two main scheduling paths.

### 1. Owned-boundary flush

Owned boundaries include things like:

- template event handlers
- wrapped callbacks such as `setTimeout`, `queueMicrotask`,
  `requestAnimationFrame`, and `setInterval`

The current flow is:

1. clone `beforeScope`
2. run the callback
3. refresh the instance scope
4. compute:
   - dirty bindings
   - currently pending dirty tracked paths
5. synchronously call:
   - `instance.updateDirty({ bindings, paths }, scope)`
   - or `instance.update()` as fallback

For async owned boundaries:

- Weiv flushes once after the synchronous part
- then flushes again in `finally(...)` after the promise settles

## 2. Proxy-tracked microtask flush

Proxy-tracked roots use:

- `set` trap
- `deleteProperty` trap

When a tracked write happens:

1. Weiv marks matching tracked path ids dirty
2. Weiv schedules one microtask if none is already pending:

```js
globalThis.queueMicrotask(...)
```

3. when the microtask runs:
   - pending path ids are drained
   - subscribed instances are iterated
   - each instance refreshes scope
   - each instance updates synchronously through `updateDirty(...)`

So the flush is:

- asynchronous relative to the mutation site
- synchronous once the flush begins

## Ordering

There is no strong semantic update-order contract today.

In practice, tracked subscribers are iterated in registration order, so:

- earlier registered instances are usually updated first

But this is an implementation detail, not a promised framework guarantee.

Current correctness should **not** depend on:

- parent-before-child
- child-before-parent
- sibling update order

## Timing Semantics

Current timing can be summarized as:

- owned-boundary flush: same turn, synchronous after boundary execution
- proxy-tracked flush: next microtask, synchronous inside that flush

So Weiv currently has:

- no custom task queue beyond pending-flush coalescing
- no global topological scheduler
- no deterministic cross-component ordering contract

## Tracked Reference Guarantee

The key guarantee is:

- Weiv tracks the visible captured binding/reference it owns

It does **not** guarantee:

- following arbitrary unrelated JS reference replacement elsewhere

That means:

- mutation on the tracked captured reference is observable
- unrelated detached-reference behavior remains ordinary JavaScript semantics

This is why current diagnostics stay focused on concrete Weiv tracking gaps like:

- alias mutation the compiler cannot follow precisely
- unowned callback mutation timing

and avoid trying to warn on every generic JS reference pitfall.

## Current Runtime Pieces

The concrete implementation lives primarily in:

- [helpers.zig](../src/compiler/emit/browser/direct_component_js/helpers.zig)
- [direct_component_js.zig](../src/compiler/emit/browser/direct_component_js.zig)
- [setup.zig](../src/compiler/emit/browser/direct_component_js/setup.zig)
- [node_codegen.zig](../src/compiler/emit/browser/direct_component_js/node_codegen.zig)

## Future Change Questions

If Weiv changes scheduler policy later, these are the main decision points:

- do tracked-path flushes stay microtask-based?
- does cross-component order become stable/defined?
- does Weiv introduce parent/child ordering rules?
- does Weiv keep component-scoped graphs but add a stronger shared-state runtime?
- do owned-boundary and proxy-tracked flushes stay unified at `updateDirty(...)`?

Any future change should update this document first or alongside the code.
