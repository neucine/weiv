# Next Stage Priorities

This document tracks the highest-priority implementation and verification work
for the current Weiv architecture checkpoint.

The project now has a coherent compiler/runtime direction, a working direct-DOM
browser path, observable shared state integration, runtime routing, and growing
verification infrastructure.

The next stage is no longer about proving that the framework concept works.
The next stage is about increasing precision, confidence, inspectability,
verification breadth, and developer ergonomics.

## Priority Model

- P0: foundational correctness and verification
- P1: precision and architecture hardening
- P2: tooling and ergonomics
- P3: ecosystem and advanced delivery modes

---

# P0 — Foundational Correctness And Verification

## 1. Stabilize Verification Baseline

The current verification shape is improving, but still uneven.

Required baseline commands:

```sh
zig build test
zig build component-test
zig build runtime-test
zig build test-all
```

Goals:

- keep all checkpoints green on `main`
- reduce regressions during compiler precision work
- make runtime/compiler failures easier to isolate

## 2. Expand App-Scale Verification

`workspace-app` / `kanib` should become the primary app-scale verification
anchor instead of relying mainly on TodoMVC.

Priority areas:

- nested composition
- async ownership boundaries
- route transitions
- shared observable flows
- slot-heavy component trees
- destroy/remount correctness
- browser navigation semantics

## 3. Remove Stale Documentation Drift

The docs should describe what is true now.

High-priority cleanup areas:

- remove outdated "routing can be deferred" language
- keep architecture/runtime docs aligned with actual emitted behavior
- separate historical notes from active implementation direction

---

# P1 — Precision And Architecture Hardening

## 4. Reduce Remaining `evaluate(...)` Fallbacks

The direct browser path still falls back to runtime evaluation for some dynamic
expressions.

Priority:

- reduce fallback frequency
- improve inspectability of fallback causes
- preserve correctness-first behavior when precision is uncertain

## 5. Improve Dependency Precision

The invalidation model is already selective, but still conservative in places.

Goals:

- reduce unnecessary region updates
- improve dependency tracking precision
- tighten dirty-region selection
- improve local helper dependency expansion

## 6. Observable-To-Region Mapping

Shared observable integration currently wakes the broader component update path.

Future direction:

- map observable dependencies to specific regions
- reduce broad component invalidation
- preserve explicit shared-state semantics

## 7. Diagnostics Unification

Diagnostics are becoming a core product surface.

Remaining work:

- unify parse/bind/emit diagnostics under one structured model
- reduce first-error abort behavior
- improve warning/info consistency
- improve rewrite guidance
- improve inspect output consistency

---

# P2 — Tooling And Ergonomics

## 8. Dev Server Ergonomics

Current watch/rebuild behavior works, but still needs polish.

Priority areas:

- reduce polling rough edges
- improve rebuild responsiveness
- improve long-running process ergonomics
- improve terminal output clarity

## 9. IDE And Type Integration

The compiler/runtime model is becoming stable enough for stronger editor
integration.

Priority areas:

- virtual declarations for `emit`
- stronger template symbol diagnostics
- editor integration hooks
- inspect-to-editor workflows

## 10. Inspectability UX

`inspect invalidation-graph` is becoming a defining architecture feature.

Future work:

- cleaner graph summaries
- source-grouped diagnostics
- region visualization
- dependency-path visualization
- machine-readable inspect output

---

# P3 — Ecosystem And Delivery Modes

These are important, but should follow architecture stabilization.

Possible future tracks:

- SSR
- hydration/resume strategies
- testing helpers
- forms package
- async resource primitives
- adapters

These should build on the stabilized compiler/runtime foundation rather than
pulling the architecture in multiple directions too early.
