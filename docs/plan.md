# Weiv Plan

## Purpose

This is the current implementation plan. Older plans are archived in
[archive](./archive/).

Use [Terminology](./terminology.md) for the normalized names of bindings,
regions, dirty work, owned boundaries, flushes, and patches.

Use [AST Script Analysis Plan](./ast-script-analysis-plan.md) as the current
direction for the next script-side precision upgrade.
Use [Authoring Helpers](./authoring-helpers.md) as a deferred design direction,
not as the current implementation plan.
Use [Proxy State Graph Design](./proxy-state-graph-design.md) for the current
consolidated design around proxy-backed tracked state for escaping /
externalized mutation.
Use [Testing Implementation Plan](./testing-implementation-plan.md) for the
concrete rollout of the larger flagship verification app.
Use [Companion Libraries](./companion-libs.md) for the optional ecosystem
direction and the current open shared-state/runtime question.
Use [Shared-State Companion Research](./store-companion-research.md) for the
current candidate comparison and recommendation path.
Use [Store Companion Spec](./store-companion-spec.md) and
[Store Companion Implementation Plan](./store-companion-implementation-plan.md)
as retained candidate drafts, not as the settled roadmap.

## Near-Term Priorities

### 1. Tighten Selective Region Scheduling

Current state:

- region update functions exist for all current region kinds
- owned boundaries route through `runOwnedBoundary`
- `inspect invalidation-graph` can explain region dependencies and mutation sites
- direct browser output now flushes through selective dirty region guards

Next work:

- keep shrinking conservative region guards toward more minimal affected sets
- improve region dependency precision for helper-driven expressions
- keep coarse safe fallback behavior for uncertain cases
- preserve existing behavior through `zig build render-test`

### 2. Reduce `evaluate(...)`

Current state:

- dynamic expressions still use runtime `evaluate(...)`
- region functions provide a better place to migrate expression evaluation
- `inspect invalidation-graph` can now show which regions are `eval=direct` versus
  `eval=fallback`
- fallback regions now carry a coarse reason such as `callback-argument`

Next work:

- replace hot update-path `evaluate(...)` calls with compiled direct access
- handle loop locals explicitly
- use invalidation-graph fallback reporting to drive the next reduction passes
- enforce generated-local collision rules
- keep event-handler migration as a follow-up

### 3. Harden State Diagnostics

Current state:

- hidden-state template calls are visible in `inspect invalidation-graph`
- expression-position mutations are diagnosed in the plan
- unsupported simple alias mutation is diagnosed in the plan
- unowned callback mutation is diagnosed in the plan
- user-defined `emit` conflicts are diagnosed as framework binding conflicts
- local helper dependency expansion now feeds both scheduling and graph output

Next work:

- move helper/mutation/alias/callback precision onto AST-backed backend facts
- stop extending fragile text heuristics much further in blurry script cases
- promote the most important invalidation-graph diagnostics into source-located compiler
  errors where appropriate
- improve local helper dependency analysis through structured backend records
- add targeted fixtures for alias and callback edge cases
- add IDE virtual typing for the Weiv-provided `emit` binding from
  `export interface Emits`

### 4. Improve `weiv dev`

Current state:

- `weiv dev` emits an app, serves it, and watches the source tree for rebuilds
- it defaults to an ephemeral preview port unless `PORT` is set
- rebuilds wait briefly for files to settle before re-emitting
- rebuild failures preserve the last good output and print diagnostics

Next work:

- tighten shutdown behavior and longer-running process ergonomics
- preserve clear CLI diagnostics during rebuilds
- keep generated artifacts easy to inspect

### 5. Strengthen Verification Structure

Current state:

- the suite has many focused compiler/runtime fixtures
- TodoMVC is still the main app-like verification example
- there is no clearly larger flagship verification app above it

Next work:

- define and build a larger flagship verification app
- keep TodoMVC as a smaller app-scale example, not the whole strategy
- use the larger app to expose:
  - direct strengths
  - conservative update sites
  - inspectability quality
  - remaining composition/state-model gaps
- make the larger app part of both `zig build test` and `zig build render-test`
- land it incrementally:
  - build-through coverage first
  - render/bundle verification next
  - inspect assertions after that

### 6. Clarify Shared-State / Runtime Direction

Current state:

- the larger verification-app plan now reserves one bounded shared-state area
- there is now a candidate `@weiv/store` draft and implementation sketch
- there is also an active research path toward broader Weiv-owned runtime or
  MobX-like observability semantics
- the current active tracking direction for escaping / externalized state is a
  narrow proxy-backed state graph
- router work is still intentionally deferred

Next work:

- decide whether the first official answer is:
  - a custom optional companion store
  - a Weiv-owned runtime/reactivity layer
  - or an officially supported external runtime model
- keep correctness independent of decorators/markers, treating explicit
  reactivity as a precision/optimization surface
- preserve plain local component authoring as the default path
- continue tightening the proxy-backed state graph around:
  - canonical tracked state roots
  - dirty-path marking
  - compiler-owned region mapping
  - escape diagnostics and rewrite guidance
- build on the current compiler/runtime contract:
  - emitted root metadata
  - emitted path ids and ancestry
  - region/path dependency tables
  - canonical proxy initialization
  - dirty-path consumption by the existing scheduler
- current proxy-state work already landed through the existing invalidation pipeline:
  - inspect-visible tracked roots
  - inspect-visible tracked paths
  - region-to-tracked-path mapping
  - `updateDirtyRegions(...)` dirty-path support
  - runtime proxy-backed dirty-path production for current tracked-root slices
  - CLI analysis summaries with tracked-root kinds and rewrite guidance
- keep proxy-backed tracking focused on out-of-boundary / externalized state,
  not all local component state by default
- keep local tracked-root promotion intentionally narrow until broader rules are proven
- widen escape diagnostics only where the compiler can stay honest and actionable
  - current warning coverage focuses on concrete Weiv tracking gaps such as
    alias escape and unowned callback mutation
- validate any chosen shared-state/runtime path in one bounded area of the
  larger verification app
- defer `@weiv/router` until the shared-state/runtime boundary is settled

## Verification Policy

Every behavior change should run:

```sh
zig build test
zig build render-test
```

Prefer behavioral render checks for runtime correctness. Use generated-code
string assertions only for compiler contracts that are hard to observe
behaviorally.

## Not Current Focus

Do not expand into these until the browser/compiler foundation is stable:

- SSR
- hydration
- router
- forms stack
- public state library
- transitions engine
- broad platform callback ownership
- signal/ref/proxy public reactivity APIs
