# Weiv Plan

## Purpose

This is the current implementation plan. Older plans are archived in
[archive](./archive/).

Use [Terminology](./terminology.md) for the normalized names of bindings,
regions, dirty work, owned boundaries, flushes, and patches.

## Near-Term Priorities

### 1. Finish Selective Region Scheduling

Current state:

- region update functions exist for all current region kinds
- owned boundaries route through `runOwnedBoundary`
- `dump-invalidation-graph` can explain region dependencies and mutation sites

Next work:

- add a runtime dirty binding set or dirty region queue
- map dirty bindings to region functions
- flush only relevant regions when possible
- keep coarse fallback behavior for uncertain cases
- preserve existing behavior through `zig build render-test`

### 2. Reduce `evaluate(...)`

Current state:

- dynamic expressions still use runtime `evaluate(...)`
- region functions provide a better place to migrate expression evaluation

Next work:

- replace hot update-path `evaluate(...)` calls with compiled direct access
- handle loop locals explicitly
- enforce generated-local collision rules
- keep event-handler migration as a follow-up

### 3. Harden State Diagnostics

Current state:

- hidden-state template calls are visible in `dump-invalidation-graph`
- expression-position mutations are diagnosed in the plan
- unowned callback mutation is diagnosed in the plan
- user-defined `emit` conflicts are diagnosed as framework binding conflicts

Next work:

- promote the most important invalidation-graph diagnostics into source-located compiler
  errors where appropriate
- improve local helper dependency analysis
- add targeted fixtures for alias and callback edge cases
- add IDE virtual typing for the Weiv-provided `emit` binding from
  `export interface Emits`

### 4. Improve `weiv dev`

Current state:

- `weiv dev` emits an app and serves it
- watch/rebuild ergonomics are still thin

Next work:

- add watch/rebuild loop
- preserve clear CLI diagnostics during rebuilds
- keep generated artifacts easy to inspect

### 5. Keep TodoMVC As The Forcing Function

TodoMVC should continue to verify:

- nested component updates
- child events
- conditionals
- loops
- input state
- direct DOM patching without root rerender

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
