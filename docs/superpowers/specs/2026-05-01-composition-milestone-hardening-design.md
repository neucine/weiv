# Composition Milestone Hardening — Design

## Status

Draft, awaiting review.

## Purpose

Bring slot-based composition to the exit criteria defined in
[Composition Implementation](../../composition-implementation.md):

- default and named slots work end to end
- fallback content works end to end
- grouped `<template slot:name>` works end to end
- slot diagnostics are clear
- direct browser path supports projected content without regressing the
  compiler-driven direction

The composition codegen is already implemented. This milestone closes the
gap between "codegen exists" and "milestone exit criteria met" by adding
verification, diagnostics, and stable test coverage.

## Context

As of commit `b421a2f` ("direct emit dom"):

- parser, binder, IR, lowerer, and direct browser codegen all support
  slots end to end
- `examples/slots/CardUsage.weiv` (named slot via `<template slot:header>`
  + default slot) compiles and emits successfully
- update propagation is wired: parent `update()` calls
  `refs[id].update()` on each projected slot, which re-evaluates against
  parent scope via `instance.refresh()`
- two slot-related tests in `e2e_test.zig` are stale and failing
  (assert `__slot` but codegen emits `__slot_<id>`)
- one unrelated test (`unsupported-import`) is also failing, blocking
  `zig build test`
- no Cypress or render-harness coverage of slot behavior
- no slot-specific diagnostics

## Goal

Make slot composition production-grade enough to declare the milestone
complete, so the next milestone (public state/reactivity model) can start
without composition debt.

## Scope

### In scope

- Make `zig build test` and `zig build render-test` green
- Cypress coverage for the four exit-criteria browser cases
- New canonical fallback example (`EmptyState.weiv` + usages)
- Six new compiler diagnostics for slot misuse
- IR snapshot tests for `Panel.weiv`, `Card.weiv`, `EmptyState.weiv`
- Doc updates marking the milestone complete

### Out of scope (deferred per spec)

- Scoped slot props / `bind:value` on slot
- Dynamic slot names
- Async / portal / teleport composition
- Render-prop composition

## Architecture

No new packages. Four existing layers receive changes.

### Compiler — analyze (`src/compiler/analyze/binder.zig`)

Add cross-component slot validation. For each component reference the
binder already resolves, build a **child slot manifest**: the set of slot
names declared by that component (including whether a default slot
exists). Manifests are keyed by resolved component path and cached for
the duration of the build.

The manifest is built from the already-parsed normalized template of the
imported component — no new loader. If a thin accessor is needed to
expose the imported component's slot outlets, add it next to the
existing import resolution code.

Parent-side diagnostics (#3, #4, #5 below) operate on the parent's own
normalized template and do not need the manifest.

Cross-component diagnostics (#1, #6 below) read the manifest.

Child-side diagnostic (#2) is computed while building the manifest.

### Compiler — emit (`src/compiler/emit/browser/direct_component_js/`)

No design change. Codegen output is correct; only stale test assertions
need updating to match the current `__slot_<id>` variable naming.

### Tests — Zig (`src/e2e_test.zig`)

- Fix two stale slot assertions
- Repair the `unsupported-import` test so it asserts the failure
  (matching against the `lodash-es` error path) rather than treating the
  failure as a build break
- Add IR snapshot tests for the three canonical slot examples
- Add binder diagnostic tests, one per new diagnostic code

### Tests — Cypress (`cypress/e2e/`)

New file `slots-direct.cy.js`, modelled on `todomvc-direct.cy.js`. Boots
a fixture page that mounts each slot example and asserts DOM shape after
mount and after parent state mutation.

### Examples (`examples/slots/`)

- `EmptyState.weiv` — single named slot `message` with fallback, plus a
  default slot with fallback
- `EmptyStateUsage.weiv` — provides only the `message` slot, exercises
  the default slot's fallback
- `EmptyStateFallbackUsage.weiv` — provides nothing, exercises both
  fallbacks
- `ReactiveCardUsage.weiv` — local mutable state + button + interpolation
  flowing into a named slot, drives the parent-state-update Cypress test

### Render harness (`tools/run_cypress_direct.ts`, `spec/render_check.ts`)

Reuse the existing harness. It already supports multi-module emit
output (verified — `emit-app` produces `Card.mjs` + `CardUsage.mjs`).
Feed it the new slot fixtures and add `expected/` snapshots if the flow
uses them.

## Diagnostics Catalog

All diagnostics are emitted from the analyze phase with source spans
that point into the original `.weiv` file.

| # | Code                              | Trigger                                                                                                          |
|---|-----------------------------------|------------------------------------------------------------------------------------------------------------------|
| 1 | `slot.unknown_name`               | Parent uses `slot:foo` but the resolved child component has no `<slot name="foo">`                               |
| 2 | `slot.duplicate_outlet`           | A child component declares two `<slot>` outlets with the same name (or two unnamed default outlets)              |
| 3 | `slot.assign_outside_component`   | `slot:name` appears on a node that is not a direct child of a component usage                                    |
| 4 | `slot.template_outside_component` | `<template slot:name>` appears outside a component-child context                                                 |
| 5 | `slot.duplicate_provision`        | Parent provides the same slot name twice on one component usage without using `<template slot:name>` for grouping |
| 6 | `slot.default_not_supported`      | Parent provides unnamed children to a component whose only `<slot>` is named (no default outlet)                  |

Each diagnostic has at least one binder unit test asserting message + span.

Note on #5: per `composition-model.md` the spec says repeated named-slot
groups concatenate in document order, but only when explicitly grouped.
Loose duplicate `slot:name` on bare nodes is ambiguous and is rejected
to keep authoring intent unambiguous.

## Test Plan

### Zig

- Fix two stale `__slot` assertions to match `__slot_<id>` naming
- Repair `unsupported-import` test to assert failure on `lodash-es`
- IR snapshot tests for `Panel.weiv`, `Card.weiv`, `EmptyState.weiv`
- Six binder diagnostic tests (one per code), each asserting code + span

### Cypress (`cypress/e2e/slots-direct.cy.js`)

1. **Default slot mount** — `PanelUsage` renders parent's `<p>` inside
   Panel's slot region
2. **Named slot mount** — `CardUsage` renders `<h2>` into header, `<p>`
   into default
3. **Default fallback** — `EmptyStateFallbackUsage` shows fallback text
   for both slots
4. **Named fallback** — `EmptyStateUsage` shows fallback only for the
   omitted default slot
5. **Parent state update** — `ReactiveCardUsage` button click mutates
   parent state; projected slot interpolation updates without
   re-mounting (assert same DOM node, changed `textContent`)
6. **Mixed update** — same fixture, also asserts a non-slot interpolation
   in the parent updates in step with the slot one

### Acceptance

- `zig build test` green
- `zig build render-test` green
- `cypress run` green for `slots-direct.cy.js`
- All six diagnostics fire on hand-crafted invalid `.weiv` files
- Every checkbox in `composition-implementation.md` "Exit Criteria"
  is satisfied

## Implementation Order

Each step is independently testable.

1. Unblock the test gate — fix stale `__slot` assertions; flip
   `unsupported-import` test to assert the failure path
2. IR snapshot tests for existing slot examples (Panel, Card) — locks
   the current lowered shape before diagnostic work begins
3. Add `EmptyState.weiv` + usages and its IR snapshot test
4. Parent-side diagnostics (#3, #4, #5) — single-template checks, no
   manifest cache
5. Child slot manifest cache + #2 (`duplicate_outlet`) — simplest
   manifest consumer
6. Cross-component diagnostics (#1, #6) — uses the manifest from step 5
7. Cypress slot spec — covers all four exit-criteria browser cases; add
   `ReactiveCardUsage.weiv` here
8. Doc updates — mark composition milestone complete in
   `docs/execution-plan.md` and `docs/composition-implementation.md`

## Risks

- **Manifest cache scope creep.** Cross-component validation needs the
  binder to read imported `.weiv` files. The binder already resolves
  component refs; reuse that resolution rather than adding a new loader.
  If the resolved import doesn't yet expose its normalized template, add
  a thin accessor as part of step 5 — not a new pipeline.

- **Slot update propagation may have subtle bugs only visible in
  Cypress.** The wiring looks correct in the emitted JS but has not been
  browser-verified. Keep the Cypress reactive test minimal (one button,
  one interpolation) so when it fails, the diff is small and the codegen
  path is obvious.

- **`<template slot:name>` grouping with mixed children.** Multi-node
  groups are exercised by `CardUsage` (title + eyebrow). Add one more
  text + element mix in `EmptyState` usages to widen coverage.

- **Diagnostic span fidelity.** Spans on `slot:name` directives must
  point at the directive, not the parent element. Verify
  `template/directives.zig` preserves directive spans; if not, fix that
  in step 4 before emitting #3, #4, #5.

- **Render harness divergence.** The harness already serves multi-module
  output (verified — `emit-app` produces both component bundles). No
  change expected, but flag if a slot example surfaces a harness
  assumption.

## Deferred (explicitly)

Per the composition spec, do not add in this milestone:

- scoped slot props
- slot functions
- render-prop composition
- dynamic slot names
- portal-like projection

## Exit Criteria

The milestone is complete when:

- All Zig tests pass
- Render-harness tests pass
- The new Cypress spec passes
- All six diagnostics are implemented and tested
- The composition-implementation doc's exit checklist is fully checked
- `docs/execution-plan.md` records the milestone as done
