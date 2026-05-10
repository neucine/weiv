# Weiv Testing Strategy

## Purpose

`weiv` needs more than lots of small checks.

The current suite is strong at narrow regressions, but weaker at showing:

- where the compiler/runtime model scales cleanly
- where conservative behavior starts to accumulate
- where composition and state patterns interact in realistic ways

This document defines the intended testing shape for the repo.

## Testing Layers

### 1. Narrow Compiler Fixtures

These are the existing focused tests around:

- parsing and normalization
- binding diagnostics
- slot validation
- IR/browser-plan formatting
- direct-expression compilation
- invalidation-graph diagnostics

These should stay small and surgical. Their job is to catch specific
regressions quickly.

### 2. Golden Example Apps

These are app-like examples that are larger than the narrow fixtures and more
composition-dense than TodoMVC.

A good golden example should combine:

- nested components
- parent/child events
- async event-driven state changes
- local callback-wrapped updates such as timers or microtasks
- at least one intentionally unowned external-style callback boundary
- one small shared-state/store integration area
- conditionals
- loops
- helper-driven derived display
- slots or projection
- local mutable state across multiple regions
- realistic styling and composition density

Golden examples are not only "does it work?" fixtures. They are also the main
way to observe:

- what compiles directly
- where conservative guards still broaden updates
- where diagnostics remain noisy or unclear

### 3. Verification Apps

These are end-to-end examples that prove the framework works as an actual app.

They should continue to prove:

- the framework is usable as an actual app
- direct browser output survives realistic interaction flow
- compiler/runtime changes do not silently break broader behavior

But they should not be the only showcase of the framework's strengths or gaps.

## Current Gap

Right now the suite is too flat:

- many small focused fixtures
- TodoMVC as the main app-like verification example

What is still missing is a fully integrated larger flagship verification app.

That gap matters because TodoMVC is:

- excellent for list-heavy local-state interaction
- weaker at exposing richer composition density
- weaker at exposing slot-heavy or dashboard-like layout patterns
- weaker at exposing many independently updating regions on one screen
- still too small to reveal the next class of coordination and scaling issues
- familiar enough that it can hide framework-specific blind spots

## Recommended Structure

The repo should aim for this testing pyramid:

- narrow fixtures for compiler/runtime contracts
- one or two app-scale golden examples
- one larger flagship verification app

Concretely:

- keep `test/examples/todomvc` as a useful smaller app-scale example
- keep small focused fixtures for sharp regression coverage
- keep expanding the dedicated larger verification-app track above TodoMVC

## Larger Verification App

The next important piece is a larger app, not just a denser single screen.

Recommended shape:

- multiple top-level sections or pages worth of composition
- multi-panel or multi-section layout
- nested reusable child components
- one or more slot/projection surfaces
- filtered collections
- detail/summary regions
- a few local helper-derived values
- several independent update regions on one screen
- enough breadth that one feature area can regress without obviously breaking
  the whole app

Working name:

- `test/examples/workspace-app`

The first scaffold now exists. What remains is deeper component-test coverage,
inspect assertions, and broader interaction verification.

The point is not the exact product domain. The point is to create an example
that is rich enough to show:

- where direct DOM emission is already strong
- where selective scheduling is still conservative
- where owned async/callback boundaries behave well
- where unowned callback boundaries still diagnose or fall back conservatively
- how one bounded proxy-tracked shared-state area integrates with Weiv without
  dominating the core authoring model
- where inspect output is useful
- where authoring or diagnostics still feel rough

## Verification Expectations

For the larger verification app, we should eventually have:

- build-through coverage in `zig build test`
- app bundle/component coverage in `zig build component-test`
- inspect snapshots or assertions for:
  - browser-plan shape
  - invalidation-graph shape
  - conservative fallback sites

The larger verification app should become part of the normal regression story,
not just a one-off demo.

Use [Testing Implementation Plan](./testing-implementation-plan.md) for the
concrete rollout steps.
Use [Testing Capability Matrix](./testing-capability-matrix.md) for the
required Weiv feature coverage of the flagship app.

## Policy

- Small fixtures prove isolated contracts.
- App-scale golden examples prove framework character.
- Larger verification apps prove scaling and end-to-end viability.

`weiv` needs all three.
