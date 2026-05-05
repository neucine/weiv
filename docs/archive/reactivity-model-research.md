# Reactivity Model Research

## Purpose

This document compares plausible public state/reactivity models for `weiv`.

Status: background research. The active direction is now documented in
[Compiler-Native State Model](./compiler-native-state-model.md), including the
region-based update model and detection/testing contract.

The goal is not to pick the most technically clever approach. The goal is to
pick the cleanest model that fits `weiv`'s existing direction:

- compiler-first
- direct DOM patching
- small runtime
- plain script authoring by default
- no public fine-grained reactivity primitives in the default path

This document is the research companion to the open item in
[remaining-work.md](./remaining-work.md): `define and document the stable compiler-native state/scheduling model`.

## Constraints

Any accepted direction should preserve these constraints:

1. Plain local variables should remain the default authoring path.
2. The runtime should stay small and explicit.
3. Compiler-owned update plans should remain the primary execution model.
4. The model should work for async and external callbacks without forcing a full signal-first API.
5. The model should be explainable in one short guide without hidden rules everywhere.

## Candidate Models

### A. Plain locals plus explicit invalidation

Authoring shape:

```ts
let count = 0;

setInterval(() => {
  count += 1;
  invalidate();
}, 1000);
```

Summary:

- plain locals stay the norm
- framework-wrapped template events can still auto-update
- non-framework async/external flows call `invalidate()`

### B. Plain locals plus compiler/runtime async wrapping

Authoring shape:

```ts
let count = 0;

setInterval(() => {
  count += 1;
});
```

Summary:

- framework/runtime tries to wrap timers, async continuations, subscriptions, or other callback boundaries automatically
- fewer explicit calls in user code
- more hidden runtime rules and edge cases

### C. Plain locals by default plus optional signal escape hatch

Authoring shape:

```ts
let count = 0;
const liveTime = signal(Date.now());

setInterval(() => {
  liveTime.set(Date.now());
}, 1000);
```

Summary:

- plain locals remain the default path
- explicit signals are only for hard async/external cases
- introduces a second mental model, but only as an opt-in escape hatch

### D. Signal-first public model

Authoring shape:

```ts
const count = signal(0);

function increment() {
  count.set(count.get() + 1);
}
```

Summary:

- technically clear
- easiest to make reactive in arbitrary contexts
- changes `weiv`'s authoring identity significantly

### E. Proxy-based runtime tracking

Authoring shape:

```ts
const state = reactive({ count: 0 });
state.count += 1;
```

Summary:

- familiar from other frameworks
- runtime-heavy
- fights the current compiler-first/direct-emitter direction

## Evaluation Scenarios

These scenarios are the minimum test set for any proposed model.

### Scenario 1: Local button state

```ts
let count = 0;

function increment() {
  count += 1;
}
```

Template event handlers should remain frictionless.

### Scenario 2: Async fetch lifecycle

```ts
let status = "idle";
let data = null;

async function load() {
  status = "loading";
  // ...
  data = await fetchJson();
  status = "done";
}
```

This is the most common real-world async case.

### Scenario 3: Timer-driven updates

```ts
let elapsed = 0;

setInterval(() => {
  elapsed += 1;
}, 1000);
```

This tests non-template callbacks.

### Scenario 4: External subscription

```ts
let latest = "";

socket.onmessage = (event) => {
  latest = event.data;
};
```

This tests integration with systems `weiv` does not own.

### Scenario 5: Browser observers

```ts
let visible = false;

const observer = new IntersectionObserver(([entry]) => {
  visible = entry?.isIntersecting ?? false;
});
```

This is a good proxy for Web APIs that hold long-lived callbacks.

### Scenario 6: Derived values in template expressions

```ts
let count = 0;
function doubled() {
  return count * 2;
}
```

The chosen model should keep derived values simple and compiler-friendly.

### Scenario 7: Child event updates

```ts
let todos = [];

function handleCreate(todo) {
  todos = [...todos, todo];
}
```

This tests normal component event flow, which should stay automatic.

### Scenario 8: TodoMVC-scale nested updates

The chosen model must scale from one local binding to:

- list filtering
- editing state
- child event propagation
- conditionals
- loops
- derived helper calls

without introducing a second large runtime subsystem.

## Evaluation Matrix

### A. Plain locals plus explicit invalidation

Strengths:

- best match with current authoring direction
- smallest runtime surface
- easiest to align with compiler-owned patch plans
- easiest to debug because update triggers are explicit

Weaknesses:

- explicit `invalidate()` can feel manual or leaky
- easy for users to forget in async/external code
- whole-component invalidation may feel blunt unless later refined

Teaching burden:

- low for normal events
- medium for async/external flows

Fit with `weiv`:

- strong

### B. Plain locals plus compiler/runtime async wrapping

Strengths:

- keeps author code very clean in the happy path
- preserves plain local variables

Weaknesses:

- hidden behavior becomes hard to explain
- coverage will always be incomplete
- increases runtime magic and edge cases
- debugging becomes harder when some callbacks auto-update and some do not

Teaching burden:

- high, because users must learn invisible boundaries

Fit with `weiv`:

- weak to medium

### C. Plain locals by default plus optional signal escape hatch

Strengths:

- keeps the default authoring story simple
- gives a strong answer for stubborn async/external cases
- avoids forcing the whole framework into a signal-first identity

Weaknesses:

- two state models exist
- docs and tooling need to explain when to stay plain and when to switch
- risks gradual drift toward signal-first usage everywhere

Teaching burden:

- medium

Fit with `weiv`:

- medium to strong

### D. Signal-first public model

Strengths:

- clean technical semantics
- async and external updates become straightforward
- easiest model for future fine-grained dirty tracking

Weaknesses:

- conflicts with current "plain script by default" direction
- increases ceremony for ordinary local state
- makes `weiv` feel more like a reactive runtime framework than a compiler-first one

Teaching burden:

- medium

Fit with `weiv`:

- weak

### E. Proxy-based runtime tracking

Strengths:

- ergonomic for object mutation

Weaknesses:

- runtime-heavy
- weak fit with direct compiled patching
- harder to reason about performance
- encourages hidden behavior

Teaching burden:

- medium

Fit with `weiv`:

- weak

## Recommendation

The cleanest direction for `weiv` is:

### Recommended direction

Plain locals by default, with a small explicit invalidation escape hatch for non-framework-owned async/external flows.

That means:

1. Template event handlers remain automatic.
2. Plain local variables remain the default state model.
3. Compiler-generated update paths remain the core mechanism.
4. Non-template async/external callbacks use a small explicit primitive at first.

Initial shape:

```ts
let latest = "";

socket.onmessage = (event) => {
  latest = event.data;
  invalidate();
};
```

This is not perfect, but it is the cleanest first stable model because:

- it matches the current repo direction
- it avoids large runtime magic
- it does not force `ref()`/`signal()` into every example
- it leaves room for future refinement without invalidating the default authoring story

## Recommended Refinements

The recommendation above should still be treated as a staged design, not a final API lock.

### Stage 1: explicit whole-component invalidation

Provide one explicit primitive:

```ts
invalidate();
```

Use it only for:

- timers
- async continuations
- manual DOM/browser API subscriptions
- sockets / observers / external stores

### Stage 2: evaluate whether a second escape hatch is needed

Only after Stage 1 is used on realistic examples should `weiv` consider:

- optional signal primitive
- more targeted invalidation
- compiler-recognized wrapped async helpers

Do not start with all three.

## Rejected Directions For Now

### Not recommended as the default model

- signal-first public API
- proxy-based reactive objects
- automatic runtime interception of arbitrary async boundaries

These may solve some edge cases, but they pull `weiv` away from its current strengths.

## Open Questions

These still need explicit design decisions before public documentation is finalized:

1. Is `invalidate()` globally available in component scope, or imported from a runtime helper?
2. Should `invalidate()` always refresh the whole component, or should the public API anticipate targeted invalidation later?
3. What exact guidance is given for async functions with multiple mutation points?
4. Should `invalidate()` be valid inside child event handlers, or should those always remain automatic?
5. Is an optional signal escape hatch worth prototyping after the first plain-local model lands?

## Suggested Next Research Step

Before locking the public model, implement or simulate the recommended direction against these concrete examples:

- basic counter
- async fetch status component
- interval clock
- websocket message viewer
- observer-driven visibility toggle
- TodoMVC nested interactions

Then judge the model by:

- number of explicit rules
- number of surprising failure modes
- amount of runtime magic
- clarity of the author-facing explanation

If plain locals plus `invalidate()` still feels too manual after that exercise, the next thing to test should be an optional signal escape hatch, not a signal-first rewrite.
