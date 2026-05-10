# Weiv Testing Implementation Plan

## Purpose

This document turns the testing strategy into concrete implementation work.

It answers:

- what the larger verification app should be
- how it should be introduced
- how it should be tested
- what should land first versus later

Use [Testing Strategy](./testing-strategy.md) for the high-level rationale.
Use [Testing Capability Matrix](./testing-capability-matrix.md) for the
framework-first coverage target the app must satisfy.

## Target

Add a larger flagship verification app above TodoMVC.

Working name:

- `test/examples/workspace-app`

The goal is not to choose the perfect product domain. The goal is to create a
verification app that is meaningfully broader than TodoMVC and exposes more of
`weiv`'s real strengths and gaps.

## Why This App

TodoMVC is strong at:

- root-owned list state
- nested child events
- editing and filtering flows

TodoMVC is weaker at:

- many independent update regions on one screen
- denser composition trees
- richer slot/projection patterns
- dashboard/workspace-style layouts
- broader helper-derived display patterns
- async/callback boundary variety beyond normal UI events

The larger verification app should deliberately cover those missing areas.

## Proposed Shape

The first version should be a single larger app, not a router or multi-page
system.

It should still fit within one emitted app bundle and one render-test target.

Recommended sections:

1. Workspace shell
- app header
- sidebar/nav
- content area
- one or two secondary panels

2. Dashboard overview
- several cards/widgets
- independent summary regions
- small filtered lists

3. Activity/feed section
- list rendering
- per-item actions
- conditional empty states
- at least one delayed or queued UI update

4. Detail panel
- selected-item summary
- nested child components
- conditional subsections
- one async transition such as save/pending/complete state

5. Reusable projected surfaces
- cards, panels, empty states, or drawer-like sections using slots/projection

6. Boundary stress area
- one local owned callback path such as `setTimeout`, `queueMicrotask`, or
  `requestAnimationFrame`
- one async event handler path
- one intentionally unowned external-style callback registration that remains
  conservative and inspectable
- one small proxy-tracked shared-state region

## Required Feature Coverage

The app should intentionally exercise:

- props across multiple child boundaries
- local mutable state in multiple sibling regions
- helper-derived display values
- parent/child event flows
- async event-driven state transitions
- owned callback wrappers such as timers or microtasks
- at least one unowned callback boundary that should diagnose conservatively
- one small proxy-tracked shared-state integration path
- conditionals
- loops
- slot/default/named projection
- independent updates in different regions of the same screen
- realistic scoped CSS density

These are still implementation-facing summaries. The canonical framework-first
coverage list now lives in [Testing Capability Matrix](./testing-capability-matrix.md).

## File Layout

Recommended first-pass structure:

- `test/examples/workspace-app/App.weiv`
- `test/examples/workspace-app/README.md`
- `test/examples/workspace-app/WorkspaceShell.weiv`
- `test/examples/workspace-app/WorkspaceHeader.weiv`
- `test/examples/workspace-app/WorkspaceSidebar.weiv`
- `test/examples/workspace-app/DashboardSection.weiv`
- `test/examples/workspace-app/MetricGrid.weiv`
- `test/examples/workspace-app/MetricCard.weiv`
- `test/examples/workspace-app/ActivityFeed.weiv`
- `test/examples/workspace-app/ActivityItem.weiv`
- `test/examples/workspace-app/DetailPanel.weiv`
- `test/examples/workspace-app/DetailSection.weiv`
- `test/examples/workspace-app/EmptyState.weiv`
- `test/examples/workspace-app/Panel.weiv`

The exact names can change, but the shape matters:

- shell components
- dense overview components
- list/detail components
- reusable composition/projection components

## Data Model Guidance

Keep the data static and local for the first version.

Do not introduce:

- server fetching
- router state
- persistence

The first version should focus on compiler/runtime verification, not product
infrastructure.

One exception is intentionally allowed:

- a very small proxy-tracked shared-state area

That area should be:

- isolated to one feature area
- small enough to understand locally
- present to test boundary behavior, not to define the app's whole state model
- typically defined in a `.ts` module and imported into `.weiv` components

Recommended state:

- selected item id
- active tab/section
- sidebar collapse toggle
- item filter/search text
- one or two local editing states
- one pending/settled async state
- one queued callback-driven state
- one shared tracked-object state slice
- derived counts/summaries

## Shared-State Guidance

If the larger verification app uses shared state beyond plain local owned
bindings, it should do so in one bounded area using the current proxy-state
direction.

Good uses:

- selection state shared across sibling regions
- presence/notification state
- a small feed/status model updated outside direct template events

Bad uses:

- moving the whole app into shared-state-first architecture
- replacing normal local state everywhere
- hiding callback ownership issues instead of exposing them

Recommended usage style:

- define the shared tracked object in a normal `.ts` module
- import it into the relevant `.weiv` components
- keep most component state local even when one bounded shared tracked area
  exists

If shared-state runtime work broadens again later, it should be aligned with
the current proxy-state direction rather than reviving the older archived
store-companion draft by default.

## Verification Plan

### Phase 1. Build-Through Coverage

Add `zig build test` checks that:

- all workspace-app components build through the current pipeline
- the root app resolves expected component imports
- binding diagnostics stay at zero for the valid app

This is the first gate.

### Phase 2. Compiler Output Checks

Add focused checks for the larger app:

- app root emits expected child component imports
- selected sections expose expected direct-browser structure markers
- app bundle emission succeeds

These should not start as giant brittle snapshots.

Prefer:

- structured presence assertions
- one or two carefully chosen snapshots only where signal is high

### Phase 3. Render Verification

Extend `zig build render-test` coverage so the larger app proves:

- render-to-string produces stable expected structure
- direct browser mount succeeds
- a few representative interactions update the DOM without root replacement

Focus on a few high-signal interactions:

- selecting a detail item
- toggling a sidebar or panel section
- filtering a feed/list
- switching a local dashboard segment
- completing an async local action and observing the settled UI
- triggering a local owned callback update and observing region-local patching
- updating one proxy-tracked shared-state region and observing the resulting
  boundary/diagnostic behavior

### Phase 4. Inspect Verification

Add assertions for:

- browser-plan shape
- invalidation-graph shape
- a few known conservative sites if any remain
- owned async/callback boundaries being visible where expected
- unowned callback diagnostics being visible where expected
- the bounded shared-state integration being inspectable with tracked roots,
  tracked paths, or intentionally conservative behavior, depending on its
  integration model

This is important because the larger app should also become the place where we
see whether inspect output stays useful at scale.

## Rollout Sequence

Recommended landing order:

1. Create the app skeleton and component tree.
2. Add build-through tests only.
3. Add bundle/render verification.
4. Add direct browser interaction checks in render-test.
5. Add inspect assertions.
6. Only then consider snapshots if they still add value.

This keeps the rollout incremental and debuggable.

## Guardrails

Do not let the larger app become:

- a router prototype
- a data-fetching experiment
- a styling showcase detached from compiler concerns
- a giant snapshot fixture that is painful to evolve

The app should be:

- broad enough to expose scaling issues
- small enough to understand
- stable enough to become a long-term regression asset

## Success Criteria

This work is successful when:

- `test/examples/workspace-app` exists and is readable as an app
- it is clearly larger and broader than TodoMVC
- it participates in both `zig build test` and `zig build render-test`
- it reveals useful compiler/runtime behavior beyond the current small fixtures
- it becomes a normal part of verification, not a side demo
