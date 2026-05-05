# Compiler-Native State Execution Plan

## Purpose

This plan turns [Compiler-Native State Model](./compiler-native-state-model.md)
into an implementation sequence.

The goal is not to build a generic reactivity engine. The goal is scoped
invalidation for retained DOM regions:

- compiler-defined update regions
- compiler-owned dependency and mutation analysis
- runtime dirty queues for owned boundaries
- diagnostics for unsupported stale-risk patterns
- inspectability through `dump-state-plan`

## MVP Decisions

Current decisions to implement first:

- update unit: compiler-defined region
- region kinds: `text`, `attribute`, `conditional`, `loop`, `child`, `slot`
- scheduling source: owned boundary
- first owned boundaries: template events, compiler-emitted child events, slot
  update boundaries, async functions invoked from owned events
- dependency precision: use visible binding dependencies where available, but
  keep correctness at the region level
- dirty marker placement: immediately after supported mutation statements
- runtime flushing: collect during a boundary, flush once at boundary end, flush
  again when an async boundary promise settles
- unsupported visible stale-risk patterns: hard diagnostic in MVP

## Phase 1: State Plan Introspection

### Goal

Build `weiv dump-state-plan` before changing runtime behavior.

This gives us a stable artifact for testing the compiler's understanding of:

- regions
- expression ownership
- binding dependencies
- mutation sites
- callback boundary ownership
- unsupported patterns

### Deliverables

- `dump-state-plan` CLI command
- state-plan data model
- formatter for human-readable output
- compiler tests for representative fixtures
- no runtime behavior changes yet

### Initial output shape

The exact format can evolve, but the dump should include:

```text
regions
  #1 text source=examples/basic-counter.weiv:8:3 deps=[count]
  #2 attribute source=examples/basic-counter.weiv:9:11 deps=[count]

mutations
  count assignment source=examples/basic-counter.weiv:4:3 boundary=template-event

boundaries
  template-event click source=examples/basic-counter.weiv:8:9 owned=true

diagnostics
  imported hidden-state helper getThemeLabel source=... unsupported
```

### Fixtures

Add fixtures for:

- primitive interpolation
- bound attribute/property
- `if` condition
- `for` iterable
- child prop
- default/named slot projection
- imported pure helper with visible args
- imported no-arg hidden-state helper diagnostic

### Exit criteria

- `zig build test` passes
- `zig build render-test` passes
- `dump-state-plan` can explain regions and dependencies for the core examples
- unsupported imported hidden-state helpers produce clear diagnostics

## Phase 2: Mutation Detection Without Runtime Scheduling

### Goal

Teach the compiler to identify mutation sites for template-observable bindings.

This phase still only reports through `dump-state-plan` and diagnostics.

### Supported mutation shapes

- `binding = value`
- `binding += value`
- `binding++` and `binding--`
- `objectBinding.property = value`
- `arrayBinding[index] = value`
- statement-position known mutating methods

Known mutating method groups:

- `Array`: `push`, `pop`, `shift`, `unshift`, `splice`, `sort`, `reverse`,
  `copyWithin`, `fill`
- `Map`: `set`, `delete`, `clear`
- `Set`: `add`, `delete`, `clear`

### Diagnostics

Diagnose for MVP:

- expression-position mutation of template-observable bindings
- unsupported visible alias mutation if alias tracking is not implemented
- reflective mutation of template-observable bindings

### Exit criteria

- state-plan output lists mutation sites and affected root bindings
- mutation-site source locations are accurate
- supported mutation fixtures are covered
- unsupported mutation fixtures fail clearly
- `zig build test` and `zig build render-test` pass

## Phase 3: Boundary Ownership Analysis

### Goal

Classify mutation sites by scheduling boundary ownership.

### MVP owned boundaries

- template events
- compiler-emitted child event handlers
- compiler-emitted slot update boundaries
- async functions invoked from template-owned event handlers

### Not owned in MVP

- arbitrary imported registration APIs
- callback aliases passed to unknown registrations
- callbacks registered inside imported functions
- reflective registration

### Diagnostics

Hard-error visible stale-risk patterns:

```ts
externalStore.subscribe(() => {
  count += 1;
});
```

```ts
const cb = () => {
  items.push(next);
};

external.register(cb);
```

### Exit criteria

- `dump-state-plan` lists owned and unowned boundaries
- visible unowned callback mutations of template state diagnose
- owned template-event mutations are classified correctly
- async template-event handlers are classified as owned
- `zig build test` and `zig build render-test` pass

## Phase 4: Runtime Dirty Queue And Region Scheduler

### Goal

Add runtime scheduling without replacing existing direct DOM patching all at
once.

### Runtime shape

- each instance has a dirty binding set or dirty region queue
- owned boundaries collect dirty marks during callback execution
- boundary end schedules relevant regions
- async boundary settle schedules another flush if needed
- destroyed instances ignore pending dirty marks and async settle flushes
- repeated flush passes have a safety limit

### Implementation strategy

Start by routing existing `instance.update()` through the boundary scheduler,
then progressively narrow from component-level update to region-level update.

This preserves behavior while the region update functions are introduced.

### Exit criteria

- existing interaction tests remain green
- sync template event mutations still update UI
- async template event fixtures cover loading and final states
- destroyed-instance async settle fixture does not patch detached DOM
- `zig build test` and `zig build render-test` pass

## Phase 5: Region Update Emission

### Goal

Move from component update passes to region update functions.

### Work items

- emit region update functions for `text`
- emit region update functions for `attribute`
- emit region update functions for `conditional`
- emit region update functions for `loop`
- emit region update functions for `child`
- emit region update functions for `slot`
- map dirty bindings to region functions
- keep local no-op guards at DOM-write boundaries

### Exit criteria

- related regions update after mutation
- unrelated regions do not run in behavior-oriented fixtures where observable
  instrumentation can prove it
- fallback/coarse invalidation remains correct for uncertain cases
- `dump-state-plan` matches emitted region functions
- `zig build test` and `zig build render-test` pass

## Phase 6: Platform Callback Rewrite Candidates

### Goal

Add explicit support for selected platform callback boundaries only after MVP
region scheduling is stable.

### Candidate order

1. `setTimeout`
2. `setInterval`
3. `queueMicrotask`
4. `requestAnimationFrame`
5. direct `addEventListener`
6. `ResizeObserver` / `IntersectionObserver`
7. direct property callbacks like `socket.onmessage`

Each candidate must add:

- rewrite support
- state-plan boundary output
- diagnostics for unsupported variants
- behavior tests

### Exit criteria

- no global monkey patching
- only recognized syntax becomes owned
- unsupported registration shapes stay diagnostic or explicitly unsupported
- `zig build test` and `zig build render-test` pass

## Phase 7: Inspectability And Debugging Polish

### Goal

Make stale UI reports easy to classify.

### Work items

- improve `dump-state-plan` formatting
- add source-located diagnostics for hidden external template calls
- add source-located diagnostics for unowned callback mutation
- add debug output for region scheduling if needed
- consider dev-only emitted `__weiv_state_plan` metadata later

### Exit criteria

- a stale UI issue can be classified as unsupported code, missing diagnostic, or
  compiler/runtime defect
- tests cover both supported behavior and unsupported diagnostics
- docs show how to inspect the state plan

## Verification Policy

Every implementation phase should run:

- `zig build test`
- `zig build render-test`

Prefer behavioral tests for update correctness. Use string-shape assertions only
for compiler contracts that cannot be observed through runtime behavior.

## Non-Goals For First Pass

- public signals, refs, effects, or proxy-reactive state
- global monkey patching of platform APIs
- full alias analysis
- hidden external state tracking
- expression-position mutation support unless exact value/order preservation is
  implemented
- production emitted state-plan metadata
