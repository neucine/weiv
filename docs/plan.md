# Weiv Plan

## Purpose

This is the current implementation plan. Older plans are archived in
[archive](./archive/).

Use [Terminology](./terminology.md) for the normalized names of bindings,
regions, dirty work, owned boundaries, flushes, and patches.

Use [AST Script Analysis Plan](./ast-script-analysis-plan.md) as the current
direction for the next script-side precision upgrade.
Use [Shared Observable State Design](./shared-observable-state-design.md) for
the active next-direction for cross-component/shared state.
Use [Compiler Diagnostics Architecture](./compiler-diagnostics-architecture.md)
for the planned diagnostics collection and IDE/LSP reuse model.
Use [Testing Implementation Plan](./testing-implementation-plan.md) for the
concrete rollout of the larger flagship verification app.

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
- preserve existing behavior through `zig build component-test`

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

### 4. Unify Compiler Diagnostics Collection

Current state:

- script and binding phases already emit structured diagnostics
- several parse and emit failures still stop on the first thrown author error
- CLI still owns some special-case formatting for thrown compiler errors

Next work:

- introduce one canonical compiler diagnostic type and bag
- return structured build reports with partial progress and fatal diagnostics
- move parse/template author errors into structured diagnostics where practical
- make CLI and future IDE tools consume the same diagnostic objects
- keep thrown errors for infrastructure failures and internal invariants only

### 5. Improve `weiv dev`

Current state:

- `weiv dev` emits an app, serves it, and watches the source tree for rebuilds
- it defaults to an ephemeral preview port unless `PORT` is set
- rebuilds wait briefly for files to settle before re-emitting
- rebuild failures preserve the last good output and print diagnostics

Next work:

- tighten shutdown behavior and longer-running process ergonomics
- preserve clear CLI diagnostics during rebuilds
- keep generated artifacts easy to inspect

### 6. Strengthen Verification Structure

Current state:

- the suite has many focused compiler/runtime fixtures
- TodoMVC is still the main app-like verification example
- `test/examples/kanib` is now the flagship medium-scale verification app

Next work:

- keep TodoMVC as a smaller app-scale example, not the whole strategy
- broaden kanib into fuller inspect and regression coverage
- use the larger app to expose:
  - direct strengths
  - conservative update sites
  - inspectability quality
  - remaining composition/state-model gaps
- make the larger app part of both `zig build test` and `zig build component-test`
- land it incrementally:
  - build-through coverage first
  - render/bundle verification next
  - inspect assertions after that

### 7. Clarify Shared-State / Runtime Direction

Current state:

- the public shared-state story is now:
  - `import { observable } from "@weiv/runtime"`
  - create shared state at the source
  - consume imported observables automatically in components
- the standalone observable runtime exists and is verified independently
- the first imported-observable component integration path is working
- router work and broader companion-library questions remain deferred

Next work:

- preserve plain local component authoring as the default path
- keep the public runtime surface minimal, centered on `observable()`
- document and harden the compiler-stable brand/metadata contract
- keep imported observable updates correct while exploring whether more precise
  observable-to-region scheduling is worthwhile later
- validate any chosen shared-state/runtime path in one bounded area of the
  larger verification app
- defer `@weiv/router` until the shared-state/runtime boundary is settled

## Verification Policy

Every behavior change should run:

```sh
zig build test
zig build component-test
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
