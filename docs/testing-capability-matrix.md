# Weiv Testing Capability Matrix

## Purpose

This document defines the framework capability coverage required from the
larger flagship verification app.

The app domain is secondary. The primary goal is to ensure one medium-scale app
exercises a wide enough slice of `weiv` itself.

Use [Testing Strategy](./testing-strategy.md) for the overall testing shape and
[Testing Implementation Plan](./testing-implementation-plan.md) for rollout
sequencing.

## Coverage Rule

The flagship app should be designed from the framework surface inward:

- choose a component/section only if it covers one or more important Weiv capabilities
- avoid product-domain features that do not increase framework coverage
- prefer one app area that exercises several framework features together over
  several fake isolated features

## Required Capability Coverage

The flagship app should exercise all of these categories.

### Parsing And Analysis

- SFC parsing
- template parsing
- script analysis
- binding resolution
- component import resolution
- `.ts` helper import resolution

### Composition

- nested component composition
- props across multiple boundaries
- child event emission
- local helper-derived display
- multi-region updates inside one screen

### Template Semantics

- direct expressions
- conditionals
- loops
- nested update regions
- dynamic text and attribute updates

### Routing

- runtime router usage
- route params
- nested routes with preserved shared shell
- route-driven view switching
- link interception and navigation behavior

### Projection

- default slot projection
- named slot projection
- fallback slot content
- nested projected content

### State And Mutation

- local mutable state
- derived/helper reads
- owned template-event mutation
- owned async callback mutation such as `setTimeout` or `queueMicrotask`
- async event handler mutation
- one intentionally unowned callback boundary that stays conservative and inspectable
- one bounded shared-state area

### Runtime And Emission

- scoped CSS emission across several components
- direct browser module emission
- app bundle emission
- selective DOM patching without root rerender for representative interactions
- imported JS helper copying
- imported TS helper transpilation

### Shared-State / Tracking

- explicit shared observable behavior through `observable()` source creation
- imported observable consumption through compiler-generated subscription
- tracking-gap analysis reporting
- concrete alias or unowned-callback tracking-gap visibility

### Inspectability

- `compile analyze component` output quality
- `inspect invalidation-graph` usefulness at medium scale
- `inspect browser-plan` usefulness at medium scale

## Suggested App Areas

These are not product requirements. They are coverage vehicles.

### Shell Area

Good for:

- multi-level composition
- props through multiple boundaries
- scoped CSS density
- sidebar collapse / header actions / section switching

### Dashboard Area

Good for:

- many independent update regions
- helper-derived summaries
- card/panel composition
- local sibling-region updates

### Feed Or List Area

Good for:

- loops
- filtered subsets
- child events
- conditional empty states
- per-item actions

### Detail Area

Good for:

- selected-item rendering
- conditional subsections
- nested child composition
- async pending/settled UI

### Projection Area

Good for:

- default slots
- named slots
- fallback content
- nested projected trees

### Boundary Stress Area

Good for:

- owned callback wrappers
- async event mutation
- one intentionally unowned callback registration
- one bounded shared-state slice

## Verification Mapping

The flagship app should be verified across several layers.

### `zig build test`

Use for:

- component build-through coverage
- import resolution
- binding diagnostics
- selected browser-plan / invalidation-graph assertions
- selected direct-emission string/structure assertions

### `bun test`

Use for:

- component mount/update behavior
- app bundle behavior
- representative interaction flows
- proof that selective updates patch instead of replacing the root

### Cypress

Use for:

- browser-level smoke interactions
- CSS/layout sanity on a denser app
- confidence that the emitted app survives a realistic user path

## Minimum Success Shape

The first version of the flagship app is successful if:

- it covers the required capability categories above
- it is broader than TodoMVC in composition and update-region density
- it remains readable enough to debug
- it becomes part of normal `zig build test` and `zig build component-test`
- it exposes at least one concrete conservative / inspectable boundary case

## Anti-Goals

Do not let the flagship app become:

- a product mockup optimized for domain realism instead of framework coverage
- a fake backend integration harness
- a shared-state-first architecture rewrite
- a drag-and-drop or animation-heavy stress test before the core browser path needs it
