# Compiler-Native State Model

## Purpose

This document defines the intended state/update direction for `weiv`.

The key decision is:

- `weiv` should treat reactivity as compiler-owned scheduling and patch planning
- `weiv` should not center its public model around runtime reactive primitives
- `weiv` should preserve plain script authoring as much as possible

This is the state-model companion to:

- [Framework Scope](./framework-scope.md)
- [Compiler Architecture](./compiler-architecture.md)
- [Browser Codegen Direction](./browser-codegen.md)
- [Compiler-Native State Execution Plan](./compiler-native-state-execution-plan.md)

## Decision Summary

`weiv` should not default to:

- signal-first authoring
- ref-first authoring
- proxy-based reactive objects
- explicit effect graphs as the main public model

Instead, `weiv` should aim for:

- plain component-local state in ordinary script
- compiler-known template read sites
- compiler-inserted scheduling around owned mutation paths
- compiled DOM patch plans that execute updates directly

In this model, "reactivity" is mostly scoped invalidation plus compiled patch
execution. It is an implementation detail of the compiler/runtime boundary, not
the primary concept the user has to think in.

## Why This Direction

Most major frontend frameworks expose a public reactivity model because they need the runtime to discover or track state changes.

Examples:

- signals
- refs
- reactive proxies
- effect/watch APIs

Those models work, but they pull the framework's center of gravity toward runtime state machinery.

`weiv` is already moving toward a different center of gravity:

- compiler-first lowering
- direct DOM patching
- explicit instance layouts
- emitted `create` / `update` / `destroy`
- shrinking runtime helpers

If the compiler already owns:

- where UI reads state
- where DOM updates happen
- which blocks/components depend on which expressions

then the framework does not need to expose a large public runtime reactivity surface by default.

## Broader UI Inspiration

`weiv` should not frame this work as "invent another web reactivity system."

The stronger framing is scoped invalidation for retained UI:

- SwiftUI and Jetpack Compose show that state changes should invalidate scoped
  parts of the UI, not necessarily an entire screen.
- Flutter shows the value of separating description, retained identity, update,
  and teardown.
- Elm shows that update causes should be explainable and debuggable.
- QML shows that UI expressions can behave like local bindings from data to
  visible properties.
- immediate-mode UI shows that reevaluating a small region can be simpler and
  more reliable than building a perfect dependency graph.

The design shift for `weiv` is:

- think in invalidation scopes, not reactive containers
- preserve retained DOM identity, not virtual rerender identity
- make update causes inspectable, not magical
- use dependency analysis as a scheduling optimization, not as the foundation of
  correctness

This keeps `weiv` closer to a compiled UI system than a runtime reactivity
framework.

## Core Principles

### 1. State is ordinary script state

The default authoring model should remain close to:

```ts
let count = 0;

function increment() {
  count += 1;
}
```

The author should not need to wrap local state in a special primitive just to make template updates work.

### 2. Templates declare observation points

Templates tell the compiler what the UI reads.

Examples:

- text interpolation reads
- attribute/property reads
- conditional expressions
- loop iterable expressions
- child prop expressions
- slot projection expressions

This gives the compiler a static map of dynamic UI observation sites.

### 3. The compiler owns update planning

The compiler should emit:

- what can update
- where it lives in the DOM
- how to patch it
- what block/component boundaries it belongs to

This is stronger than generic rerendering and narrower than a generic runtime reactive graph.

### 4. Scheduling is a framework/runtime concern, not a public state primitive by default

The hard problem is not only "what changed?"

It is also:

- when to run the compiled update program
- which owned boundary should flush
- how to batch multiple changes

`weiv` should treat that as scheduler design, not automatically as a reason to introduce signals or refs into authoring.

## Intended Mental Model

The intended user mental model should be:

1. write ordinary component-local state
2. mutate it in ordinary code
3. let the framework/compiler schedule the right update work

The intended user mental model should not be:

1. create reactive containers
2. thread those containers through all state reads/writes
3. think in terms of a public dependency graph

## What This Means In Practice

### Update regions, not perfect dependency graphs

The baseline update unit should be a compiler-defined region, not a whole
component and not an exact semantic dependency graph.

Examples of regions:

- interpolation or bound attribute site
- conditional block
- loop block
- child component boundary
- slot outlet or projected slot boundary

The compiler can still use binding dependencies to schedule regions more
selectively, but correctness should come from reevaluating dirty regions and
patching their own DOM sites directly.

This avoids making perfect dependency extraction the foundation of the model.
Opaque expressions can reduce precision for one region without invalidating the
entire architecture.

### MVP region taxonomy

The current MVP region kinds are:

- `text`: interpolation text node
- `attribute`: bound attribute or property
- `conditional`: `if` / `else-if` / `else` block
- `loop`: `for` block
- `child`: child component boundary
- `slot`: slot outlet or projected slot boundary

This taxonomy is the starting point for `dump-state-plan`, diagnostics, and
eventual region update emission. It can be refined later if real fixtures show
that a region is too coarse or too fine.

### Template events

Template event handlers are framework-owned entrypoints.

That means `weiv` can schedule updates automatically after their mutations.

Example:

```ts
let count = 0;

function increment() {
  count += 1;
}
```

```html
<button on:click="increment">Increment</button>
```

The compiler/runtime already owns this boundary.

### Direct update path

Compiled update code should continue moving toward:

- explicit dynamic sites
- local no-op guards
- smaller helper use
- eventual binding-aware selective execution

This is where most of the "reactivity work" should live.

### Async and external callbacks

Async and external callbacks are the hardest part of the model because the framework may not own the boundary automatically.

This does **not** mean `weiv` must immediately fall back to:

- public signals
- public refs
- public effect/watch APIs

It means `weiv` needs a scheduling story for mutation paths it can own or transform.

## Detection Contract

This section defines the initial contract for what `weiv` should be able to
detect and what tests should cover.

The goal is not exact runtime tracking. The goal is conservative dirtying of
template-relevant update regions.

### Observable state

Only state that can affect template expressions is observable.

Examples:

- interpolation reads
- bound attributes and properties
- `if` directive expressions
- `for` iterable expressions
- child component prop expressions
- slot projection expressions

Bindings that are never read by template regions do not need dirty
instrumentation.

### Imported helpers in templates

Imported helpers used in template expressions are treated as pure transforms
over visible arguments.

Current MVP rule:

- imported calls with visible component-state arguments are allowed
- region dependencies come from those visible arguments
- imported calls with no visible component-state dependency are rejected
- local no-argument helpers are allowed only when their dependencies are
  analyzable from component script

Supported:

```html
<p>{formatPrice(total)}</p>
<p>{formatUser(user)}</p>
```

The region dependencies come from the visible arguments, such as `total` and
`user`.

Unsupported for MVP:

```html
<p>{getThemeLabel()}</p>
<p>{store.currentUserName()}</p>
<p>{Date.now()}</p>
```

These expressions hide external state behind a call. The compiler cannot know
when they should update without a separate ownership contract.

The recommended authoring shape is to bring external state into component
visible state first, then use imported helpers as formatting or calculation
helpers.

### MVP dependency collection

The current MVP dependency collector should derive region dependencies from:

- direct identifiers that resolve to template-visible script bindings
- member or index expressions rooted at template-visible bindings
- function call arguments
- imported helper calls with visible component-state arguments
- local no-argument helpers only when script analysis can derive their visible
  binding reads

It should not treat an opaque call itself as a binding dependency.

If an expression has no visible component-state dependency and may read hidden
external state, it should be rejected or diagnosed rather than mapped to every
binding.

### Directly detectable mutations

These should be detected and instrumented when rooted at a template-observable
binding.

```ts
count = next;
count += 1;
count++;
enabled = !enabled;
```

```ts
user.name = "Ada";
items[index] = nextItem;
items[0].done = true;
```

Expected dirty unit:

- `count` dirties regions that depend on `count`
- `enabled` dirties regions that depend on `enabled`
- `user.name = ...` dirties regions that depend on root binding `user`
- `items[index] = ...` dirties regions that depend on root binding `items`

### MVP dirty mark placement

The current MVP decision is to insert dirty marks immediately after each
supported mutation statement.

Conceptually:

```ts
count += 1;
__weiv_dirty("count");

user.name = "Ada";
__weiv_dirty("user");
```

The runtime should dedupe dirty binding names until the owned boundary flushes.

This keeps the transform straightforward:

- mutation detection stays local to the statement
- ordering is easy to reason about
- multiple writes to the same binding in one boundary do not cause repeated
  region updates

### Expression-position mutations

Statement-position mutations are the MVP target.

Supported first:

```ts
count += 1;
items.push(todo);
user.name = "Ada";
```

Expression-position mutations are harder because the transform must preserve
the expression value and exact evaluation order.

Examples:

```ts
const next = count++;
return user.name = "Ada";
items.push(todo) && save();
```

Current MVP decision:

- support statement-position mutations first
- diagnose expression-position mutation of template-observable bindings unless
  the transform can preserve value and ordering clearly
- add expression-position support later only with focused fixtures

### Known container mutations

Known mutating methods should dirty the root observable binding.

Arrays:

- `push`
- `pop`
- `shift`
- `unshift`
- `splice`
- `sort`
- `reverse`
- `copyWithin`
- `fill`

Maps:

- `set`
- `delete`
- `clear`

Sets:

- `add`
- `delete`
- `clear`

Typed arrays and other platform containers are out of MVP scope unless a real
fixture needs them.

### Conservative call dirtying

If a template-observable mutable binding is passed to an unknown or imported
function in component script, the compiler should conservatively dirty that
binding after the call.

```ts
normalizeUser(user);
sortTodos(todos);
```

Conceptually:

```ts
normalizeUser(user);
__weiv_dirty("user");

sortTodos(todos);
__weiv_dirty("todos");
```

This may over-update a region, but it avoids stale UI when a function mutates a
passed object or container.

Primitive arguments do not need this conservative dirtying unless the call is
passed an assignable reference, which JavaScript does not expose for primitives.

### Detectable local aliases

Simple same-scope aliases may be supported after direct mutation coverage is in
place.

```ts
const u = user;
u.name = "Ada";
```

If supported, this dirties `user`.

This is not required for the first MVP pass. If it is not supported, the
compiler should either emit a diagnostic for observable aliases used in mutation
positions or document the case as unsupported.

### Not detectable for MVP

These cases should not be silently promised in MVP.

```ts
const u = user;
passSomewhere(u);
```

```ts
const mutate = () => {
  user.name = "Ada";
};
external.register(mutate);
```

```ts
Reflect.set(user, "name", "Ada");
Object.assign(user, nextUser);
```

```ts
JSON.parse(raw);
globalStore.currentUser = next;
```

These cases either hide mutation behind alias escape, reflective APIs, external
ownership, or module-global state. They need later design if real examples
require them.

## Async And Callback Mutation Contract

Async and callback mutation needs a separate contract because detecting a write
is only half of the problem. `weiv` must also own a scheduling boundary that can
flush dirty regions after the mutation.

Owning a boundary means one of these is true:

- the compiler generated the callback wrapper
- the compiler rewrote a recognized callback registration
- the runtime created the callback wrapper through a framework-owned lifecycle
  API

An owned boundary must be able to:

- start dirty collection before the callback runs
- run the user callback
- flush dirty regions after synchronous mutations
- if the callback returns a promise, flush again when it settles

### Boundary ownership table

MVP-owned:

- template event handlers such as `on:click`
- child component event handlers emitted by the compiler
- projected slot callbacks emitted by the compiler
- async functions invoked by template-owned event handlers

Candidate compiler-rewritten boundaries:

- `setTimeout(callback, ...)`
- `setInterval(callback, ...)`
- `queueMicrotask(callback)`
- `requestAnimationFrame(callback)`
- `target.addEventListener(type, callback, options)` when `target` is a direct
  identifier or member expression visible in component script
- `new ResizeObserver(callback)`
- `new IntersectionObserver(callback)`
- direct property callback assignments such as `socket.onmessage = callback`

Not owned in MVP:

- arbitrary imported registration APIs such as `subscribe(callback)`
- callbacks passed through aliases before registration
- callbacks registered inside imported functions
- reflective callback registration
- hidden external state read by imported template helpers

These cases need a later ownership contract before `weiv` can promise automatic
updates from them.

### Supported MVP boundaries

Template event handlers are supported scheduling boundaries.

```ts
let count = 0;

function increment() {
  count += 1;
}
```

```html
<button on:click="increment">Increment</button>
```

The compiler/runtime owns the event boundary, so it can flush dirty regions
after the handler runs.

Async functions called from template-owned event handlers should also be in MVP
scope.

```ts
let status = "idle";
let data = null;

async function load() {
  status = "loading";
  data = await fetchData();
  status = "done";
}
```

```html
<button on:click="load">Load</button>
```

The scheduling rule should be conservative:

- flush after synchronous mutations before the first `await`
- flush after the async handler settles
- later, consider flushing after each continuation if the compiler/runtime can
  instrument it cleanly

This keeps common loading states correct without requiring a public
`invalidate()` API.

### MVP flush timing

The current MVP scheduling decision is:

- collect dirty bindings during an owned boundary
- flush dirty regions once at the end of the owned boundary
- if the boundary callback returns a promise, also flush when the promise settles
- nested owned boundaries should be batched into the outer boundary when possible

For async template event handlers, this means:

- synchronous mutations before the async function yields should become visible
  promptly
- final mutations after the promise settles should become visible
- flushing after every async continuation is future work

This is a conservative starting point. The timing can be adjusted later if
fixtures show that users need more immediate continuation-level updates.

### Scheduler reentrancy

The current MVP decision is:

- flushing consumes the current dirty binding set
- if patch code or child boundary updates mark more bindings dirty during a
  flush, the scheduler runs another pass
- repeated passes should have a safety limit and produce a diagnostic if the
  limit is exceeded

This makes cascading updates deterministic without allowing an accidental
infinite update loop.

### Destroyed instances

Pending async or callback work should not update a destroyed component.

The current MVP decision is:

- destroyed instances ignore boundary-settle flushes
- dirty marks after destroy are ignored
- region replacement should destroy child, loop, conditional, and slot handles
  before removing their DOM boundaries

This keeps async handlers that settle after unmount from patching detached DOM.

### Later instrumentable boundaries

These are good candidates for later support, but should not be promised until
the runtime/compiler owns the callback boundary explicitly.

```ts
setTimeout(() => {
  count += 1;
}, 1000);
```

```ts
setInterval(() => {
  elapsed += 1;
}, 1000);
```

```ts
window.addEventListener("resize", () => {
  width = window.innerWidth;
});
```

```ts
socket.onmessage = (event) => {
  latest = event.data;
};
```

```ts
const observer = new IntersectionObserver(([entry]) => {
  visible = entry?.isIntersecting ?? false;
});
```

These are not hard because mutation detection is impossible. They are hard
because the framework needs a reliable callback boundary where it can flush
dirty regions.

### Unsupported without ownership

These should not be treated as automatically reactive.

```ts
externalLibrary.register(() => {
  count += 1;
});
```

```ts
import { subscribe } from "./store";

subscribe(() => {
  count += 1;
});
```

```ts
import { getThemeLabel } from "./theme";
```

```html
<p>{getThemeLabel()}</p>
```

Without a known callback boundary or visible component state dependency, `weiv`
cannot know when to schedule the region.

### Async and callback test matrix

Tests should cover:

- sync template event mutation schedules only relevant regions
- async template event mutation before `await` schedules visible loading state
- async template event mutation after settle schedules final state
- timer mutation is either diagnosed as unsupported or covered by an explicit
  instrumented-boundary implementation
- manual DOM listener mutation is either diagnosed as unsupported or covered by
  an explicit instrumented-boundary implementation
- imported hidden-state template call is rejected or diagnosed

Until later boundaries are implemented, tests should prefer clear diagnostics
over silent partial behavior.

## User-Facing Reasoning Model

The internal model is compiler-owned regions and scheduling boundaries.

The user-facing model should be simpler:

> Template state updates the UI when it changes inside `weiv`-owned code.

Owned code includes:

- template event handlers
- compiler-emitted child event handlers
- compiler-emitted slot update boundaries
- async functions invoked by owned event handlers
- later, recognized platform callbacks after compiler rewrite support lands

This rule should be documented before the feature ships. Users should not need
to learn the full region scheduler to understand why their UI updates.

### Trust rule

`weiv` should not allow silent partial reactivity.

If template-observable state is mutated in code that `weiv` cannot schedule,
the compiler should prefer a diagnostic over allowing code that looks reactive
but may leave stale UI.

### Diagnostic goals

Diagnostics should explain:

- which template-observable binding was mutated
- where the mutation happened
- why `weiv` does not own the scheduling boundary
- how to move the mutation into an owned boundary

Example message shape:

```text
mutation of template state `count` happens inside an unowned callback
weiv cannot schedule UI updates from this callback yet
move this mutation into a template event, a compiler-owned lifecycle boundary,
or a supported callback boundary
```

### MVP diagnostic severity

Unsupported visible stale-risk cases should be hard errors in MVP.

Warnings are not enough for cases where code appears reactive but may leave the
UI stale. A hard error is preferable when the compiler can see:

- template-observable state is mutated
- the mutation happens inside an unowned boundary
- no supported scheduling path exists

This policy can soften later only if there is a clear adapter or ownership story
for the pattern.

### Stale UI classification

When UI does not update, the framework should make it easy to classify the case:

- expected non-reactive code
- unsupported boundary with diagnostic
- compiler/runtime defect

Expected non-reactive code:

- hidden external state read from an imported template helper
- mutation inside an unowned callback that the compiler can see and diagnose
- mutation through unsupported reflective or alias-escape patterns

Compiler/runtime defect:

- mutation of template-observable state inside an owned boundary does not dirty
  the expected region
- dirty region is scheduled but its patch code does not update the DOM
- async template event mutation before `await` or after settle does not flush as
  promised
- unsupported mutation is silently accepted even though the compiler can see the
  unowned boundary

This distinction should guide tests and issue triage. A stale UI report should
usually become one of:

- improve diagnostics for an unsupported pattern
- add support for a new owned boundary
- fix dirty marking or region patching for a supported pattern

### Inspectability goals

The compiler should eventually expose enough debug output to answer:

- which template regions exist in this component
- which bindings can dirty each region
- which mutation sites insert dirty marks
- which callback boundaries are owned
- which expressions or callbacks are rejected as unsupported

For MVP, this should be a CLI command, likely:

```sh
weiv dump-state-plan path/to/Component.weiv
```

The command should print the compiler-owned state plan without requiring the
generated JavaScript to run.

The dump should include:

- update regions and their source locations
- expressions owned by each region
- visible bindings that can dirty each region
- mutation sites that insert dirty marks
- owned and unowned callback boundaries
- diagnostics for unsupported hidden dependencies

Emitting a structured `__weiv_state_plan` object in dev JavaScript may be useful
later for tests, browser tooling, or bug reports, but it is not required for the
first implementation.

### Cases that should diagnose

When detectable, these should produce clear diagnostics before MVP support is
claimed:

```ts
externalStore.subscribe(() => {
  count += 1;
});
```

```ts
externalLibrary.register(function onChange() {
  user.name = "Ada";
});
```

```ts
const cb = () => {
  items.push(next);
};

external.register(cb);
```

The compiler may not catch every hidden case, especially through imported
functions, but it should diagnose the common visible cases rather than allowing
surprising stale UI.

### Future adapter story

If real apps need mutation from boundaries `weiv` cannot infer, the project may
need a small adapter story.

That adapter should be framed as external-system ownership, not as the main
state model.

The default should remain plain component-local state plus compiler-owned
regions.

### Testing Matrix

The state/scheduling tests should cover at least these cases:

- primitive assignment dirties only relevant regions
- compound assignment and increment dirty the binding
- object property assignment dirties the root binding
- array index assignment dirties the root binding
- array mutating methods dirty the root binding
- `Map` and `Set` mutating methods dirty the root binding
- unknown call with observable object argument dirties that argument
- imported pure helper in template depends on visible arguments
- imported no-argument hidden-state helper in template is rejected or diagnosed
- unsupported alias escape is diagnosed or explicitly documented as outside MVP

The preferred assertions are behavioral:

- unrelated regions do not update
- related regions update after the mutation
- unsupported hidden dependencies fail clearly

String-shape assertions are useful only for compiler contracts that are hard to
observe behaviorally.

## Preferred Direction For Async / External Mutation

The preferred long-term direction is:

- plain authoring
- compiler-inserted scheduling where mutation sites are owned and transformable
- explicit framework/runtime ownership of scheduling, not public reactivity containers by default

This implies a likely staged path:

### Stage 1

Get the direct DOM patch path strong enough that component update execution is cheap and predictable.

### Stage 2

Expand compiler-owned scheduling around obvious mutation paths in component-local code.

### Stage 3

Define a minimal fallback for mutation paths the framework cannot safely infer, only after the compiler-native model is tested against real examples.

That fallback might still be explicit, but it should be chosen later and kept minimal.

## Non-Goals

This direction is intentionally not trying to make `weiv` into:

### A signal-first framework

Not the default goal:

```ts
const count = signal(0);
```

### A proxy-reactivity framework

Not the default goal:

```ts
const state = reactive({ count: 0 });
```

### A large public effect graph API

Not the default goal:

- watch/effect as the core user abstraction
- user-managed dependency wiring everywhere

These may be useful in limited future cases, but they should not define the framework's main identity.

## Tradeoff Acknowledgement

This direction is attractive because it is aligned with `weiv`.

It is also harder.

Compared with adopting signals or proxies, this path has:

- more compiler complexity
- more need for code transformation discipline
- more subtle ownership rules around async/external mutation

So the choice is not "easy and novel."

It is:

- more aligned
- potentially more differentiated
- more research-heavy

That is acceptable if the project wants a truly compiler-native model rather than a familiar runtime-reactivity model.

## Evaluation Rule

When considering a future reactivity/state feature, ask:

1. Does this preserve plain script authoring by default?
2. Does this keep reactivity primarily compiler-owned?
3. Does this reduce or increase runtime magic?
4. Does this strengthen or weaken direct DOM patch planning?
5. Are we introducing a public primitive because it is truly necessary, or because other frameworks already have one?

If a proposed feature mainly pulls `weiv` toward runtime-reactivity parity with other frameworks, it should be treated skeptically.

## Next Work

To make this direction real, the next steps are:

1. Continue shrinking generic browser update behavior in favor of compiler-emitted patch paths.
2. Define the owned scheduling boundaries that already exist today.
3. Research how far compiler-inserted scheduling can go before author-facing fallback APIs become necessary.
4. Validate the model against real examples, especially TodoMVC-scale interactions plus async/external flows.

## Current Status

This is the intended direction, not a fully locked end-state API.

What is locked:

- plain authoring should remain the default
- runtime reactive primitives should not define the framework by default
- compiler-owned scheduling and patch planning is the preferred path

What is still open:

- exact scheduling mechanics for async/external mutation
- how much script transformation is acceptable
- whether a minimal explicit fallback is needed later
