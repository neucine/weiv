# Weiv Authoring Helpers

## Purpose

This document defines a deferred design direction for explicit authoring helpers
in `weiv`.

The goal is not to introduce a heavy runtime reactivity API. The goal is to
give the compiler stronger facts in places where general TypeScript becomes too
ambiguous for reliable compile-time state analysis.

This is a design direction document, not a completed feature contract and not
the current next implementation step.

## Why This Exists

`weiv` already has a strong compiler-first template pipeline, but some of the
harder state-analysis cases are weak if they rely only on script text matching
or broad JS inference.

The main weak areas are:

- alias analysis
- callback ownership analysis
- local helper dependency extraction in richer cases
- imported helper purity assumptions

The current conclusion is:

- keep ordinary authoring ergonomic for simple cases
- stop pretending the compiler can infer arbitrary JS semantics
- prefer AST-backed script analysis before introducing explicit author syntax
- consider small explicit author signals only if important gaps remain after that

## Design Goals

Authoring helpers should be:

- compiler-first
- mostly runtime-free
- explicit only where ambiguity is real
- TypeScript-friendly
- inspectable in emitted plans and diagnostics

Authoring helpers should not turn `weiv` into:

- a proxy-first framework
- a signal-first framework
- a runtime subscription graph
- a macro-heavy DSL that replaces normal TS authoring everywhere

## Recommendation

Start with three semantic classes only:

1. state declaration
2. derived declaration
3. owned-boundary annotation

Do not design a large surface yet, and do not assume these must look like
runtime function calls.

## Syntax Families

There are three realistic syntax families for explicit compiler guidance.

### 1. Helper-Call Syntax

Examples:

```ts
let count = $state(0);
const doubled = $derived(() => count * 2);
$owned(() => externalStore.subscribe(() => {
  count += 1;
}));
```

Pros:

- concise
- easy to discover
- easy for IDE completion

Cons:

- looks like a runtime API even if it compiles away
- pulls `weiv` toward a signal/ref mental model
- risks making authors think in terms of helper machinery instead of compiler
  semantics

### 2. Declaration / Annotation Syntax

Examples:

```ts
/* @weiv-state */
let count = 0;

/* @weiv-derived */
function doubled() {
  return count * 2;
}

/* @weiv-owned */
function subscribeToStore() {
  return externalStore.subscribe(() => {
    count += 1;
  });
}
```

Pros:

- clearly compiler-facing
- does not look like a runtime primitive
- preserves plain value/function shapes in emitted JS

Cons:

- comments are weaker ergonomically
- more vulnerable to drifting out of sync with code intent
- less elegant than first-class syntax

### 3. Declaration-Form Syntax

Examples:

```ts
state let count = 0;
derived const doubled = count * 2;
owned function subscribeToStore() {
  return externalStore.subscribe(() => {
    count += 1;
  });
}
```

Pros:

- explicit without looking runtime-ish
- feels like compiler-owned semantics instead of helper calls
- keeps author intent close to the declaration

Cons:

- requires non-standard syntax or a preprocess/language extension
- highest implementation cost
- may complicate TS tooling the most

## Current Lean

`weiv` should avoid helper-call syntax as the primary model.

The current best fit is:

1. plain TypeScript for ordinary event-driven state
2. AST-backed compiler analysis as the first response to ambiguous cases
3. compiler-facing annotations or declaration-form syntax only if AST-backed
   analysis still leaves important precision gaps
4. runtime-looking helper calls only as a fallback option if authoring and
   tooling prove dramatically better

In other words, if explicit semantics are needed, they should feel like
"compiler declarations" more than "reactivity functions".

## 1. State Declaration

### Problem

The compiler needs a trustworthy way to know which bindings are intended to be
observable state, especially once author code becomes less trivial.

### Direction

Add a compile-time-recognized declaration or annotation that marks a binding as
observable component state.

Example shapes worth evaluating:

```ts
/* @weiv-state */
let count = 0;
```

```ts
state let count = 0;
```

### Recommendation

Prefer a declaration or annotation shape over a runtime-looking helper call.

Reason:

- it communicates compiler semantics more honestly
- it avoids pulling `weiv` toward a runtime-reactivity identity
- it keeps plain values as the mental model

This should be compile-time meaningful first. It should not force a runtime
wrapper object.

Preferred mental model:

- author declares state
- compiler owns scheduling and patch planning
- emitted JS may still use plain values where possible

## 2. Derived Declaration

### Problem

The compiler needs stronger facts for local helper dependency extraction and for
safe direct expression compilation.

### Direction

Add a declaration or annotation that marks a function/value as a pure derived computation
from observable inputs.

Example shapes worth evaluating:

```ts
/* @weiv-derived */
const doubled = () => count * 2;
```

```ts
/* @weiv-derived */
function visibleTodos() {
  if (filter === "active") return todos.filter((todo) => !todo.completed);
  if (filter === "completed") return todos.filter((todo) => todo.completed);
  return todos;
}
```

Alternative function-style shape:

```ts
derived function visibleTodos() {
  ...
}
```

### Recommendation

Prefer a derived declaration form over a generic helper call.

Reason:

- purity is easier to define for expression-returning helpers
- dependency extraction becomes more robust
- compiler diagnostics can be stricter
- the surface still reads as compiler semantics, not runtime machinery

This also gives `weiv` a clean distinction:

- state is mutable
- derived is declarative and compiler-readable

## 3. Owned-Boundary Annotation

### Problem

Some async and callback registration sites are not owned by `weiv`, so visible
mutations inside them become stale-risk behavior.

### Direction

Add an annotation/declaration that explicitly routes a callback registration through a
compiler/runtime-owned boundary.

Example shapes worth evaluating:

```ts
/* @weiv-owned */
function subscribeToStore() {
  return externalStore.subscribe(() => {
  count += 1;
  });
}
```

```ts
owned function subscribeToStore(flush) {
  return externalStore.subscribe(flush(() => {
    count += 1;
  }));
}
```

```ts
owned function onMessage(event) {
  items = event.items;
}
socket.addEventListener("message", onMessage);
```

### Recommendation

Do not start with a runtime-looking callback meta-system.

Start with a minimal declaration/annotation that means:

- this callback boundary is intentionally compiler-owned
- flush after sync execution
- flush after returned promise settlement when relevant

This should remain narrower than “wrap any arbitrary JS callback ecosystem.”

## Imported Helper Story

Imported helpers are another ambiguity point, but they should not be in the
first helper batch.

Longer term, `weiv` may want a way to mark imported helpers as argument-pure.

Example direction:

```ts
import { formatTitle } from "./format.js"; // @weiv-pure
```

or

```ts
import { pure } from "weiv/compiler";
const formatTitle = pure(importedFormatTitle);
```

But this should wait until the local helper and state helpers settle.

## Recommended Mental Model

The intended model should become:

- state declarations mark observable mutable state
- derived declarations mark compiler-readable derived computation
- owned-boundary declarations mark compiler-owned async/callback boundaries

Everything else is ordinary TypeScript, but `weiv` stays conservative when the
code falls outside what these helpers describe.

That gives the framework a better contract:

- compiler-trustworthy where explicit
- conservative where not explicit
- no requirement for broad runtime tracking

## What This Should Not Become

Do not let this drift into:

- every variable needing annotation
- every function needing decoration
- a public runtime object model like `.value`
- hidden macro magic that emitted JS cannot explain

If a helper exists, it should improve one of:

- dependency extraction
- scheduling ownership
- diagnostics clarity
- direct patch compilation

## Plain Vs Helper Examples

The most important design test is whether a snippet can stay plain or should
require an explicit helper.

The intended balance is:

- keep plain authoring for ordinary local event-driven state
- require helpers where script semantics become compiler-hostile
- use diagnostics to tell authors when they crossed that line

### Keep Plain

These should remain ordinary TypeScript without requiring helper syntax.

#### Plain local state and local event mutation

```ts
let count = 0;

function increment() {
  count += 1;
}
```

Why plain:

- mutation is local
- boundary ownership is obvious from template events
- dependency extraction is straightforward

#### Plain template-visible comparisons and formatting

```ts
let count = 0;
let limit = 10;
```

```html
<button bind:disabled="count >= limit">
  Increment
</button>
```

Why plain:

- direct expression compilation is feasible
- no extra semantic promise is needed

#### Plain child-event flows

```ts
function saveTodo(payload: SavePayload) {
  todos = todos.map((todo) =>
    todo.id === payload.id ? { ...todo, title: payload.text } : todo
  );
}
```

Why plain:

- boundary ownership is compiler-emitted
- mutation is local and visible

### Prefer Explicit Declaration / Annotation

These are good candidates for explicit compiler-facing helpers.

#### Derived computation with meaningful dependency value

```ts
/* @weiv-derived */
function visibleTodos() {
  if (filter === "active") return todos.filter((todo) => !todo.completed);
  if (filter === "completed") return todos.filter((todo) => todo.completed);
  return todos;
}
```

Why helper:

- makes purity/dependency intent explicit
- reduces fragile helper-body inference
- gives the compiler a better scheduling contract

#### Nested local derived helpers

```ts
/* @weiv-derived */
const doubled = () => count * 2;

/* @weiv-derived */
const message = () => `value: ${doubled()}`;
```

Why helper:

- dependency chaining becomes trustworthy
- graph output can explain the result directly

#### Explicit owned callback boundary

```ts
/* @weiv-owned */
function subscribeToStore() {
  return externalStore.subscribe(() => {
    count += 1;
  });
}
```

Why helper:

- external registration is not compiler-owned by default
- helper makes flush ownership explicit

### Diagnose Instead Of Guess

These should not silently compile as if they are fully understood.

#### Alias mutation

```ts
const alias = user;
alias.name = "Ada";
```

Preferred behavior:

- diagnose unsupported alias-sensitive mutation unless the author uses a future
  explicit declaration form the compiler understands

#### Imported hidden-state helper

```ts
import { getThemeLabel } from "./theme.js";
```

```html
<p>{{ getThemeLabel() }}</p>
```

Preferred behavior:

- diagnose hidden-state ambiguity instead of pretending the call is reactive

#### Arbitrary callback registration through external code

```ts
external.register(() => {
  items.push(nextItem);
});
```

Preferred behavior:

- diagnose unowned callback mutation unless routed through an explicit owned
  boundary helper

### Borderline Cases

These need product judgment, because either plain or helper-first designs could
be defensible.

#### Plain local derived function

```ts
function doubled() {
  return count * 2;
}
```

Possible policy:

- allow plain local helpers for small cases
- recommend `$derived(...)` once helper logic gets richer

This is probably the best compromise between ergonomics and compiler trust.

#### Imported formatting helper with visible arguments

```ts
import { formatTitle } from "./format.js";
```

```html
<h1>{{ formatTitle(props.title) }}</h1>
```

Possible policy:

- allow conservatively
- or prefer a future explicit “argument-pure imported helper” annotation

### Current Recommendation

If `weiv` wants the best balance, the policy should likely be:

1. plain for local event-driven state and small local helpers
2. explicit-declaration-preferred for derived computations that carry real dependency meaning
3. explicit-declaration-required for owned async/callback boundaries outside the compiler's
   built-in owned set
4. diagnose alias/hidden-state/unowned patterns rather than guessing

## Proposed Rollout

### Phase 1

Design only:

- choose helper names
- decide syntax style
- decide whether helpers are imported, injected, or keyword-like
- decide what appears in diagnostics and `inspect invalidation-graph`

### Phase 2

Implement the smallest useful helper:

- likely `$derived(...)` or the state helper

This should prove:

- backend/compiler can recognize the helper shape
- invalidation graph becomes more trustworthy
- emitted JS stays simple

### Phase 3

Add owned-boundary helper support for real stale-risk callback cases.

## Open Questions

1. Should helper names be `$state`, `$derived`, `$owned`, or use non-`$`
   names?
2. Should helpers be imported from a compile-time module, or treated as
   framework-recognized builtins?
3. Should helper use be optional sugar, or the preferred model for non-trivial
   state authoring?
4. Should `inspect invalidation-graph` show helper-origin metadata explicitly?
5. Should some unsupported unannotated patterns become compiler errors once
   helpers exist?

## Current Recommendation

The best next move is:

1. keep the current compiler-first direct DOM architecture
2. stop extending fragile text-heuristic state analysis much further
3. design a minimal explicit helper model
4. use those helpers to strengthen the compiler contract without introducing a
   heavy runtime reactivity system
