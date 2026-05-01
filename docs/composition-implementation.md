# Composition Implementation

## Purpose

This document turns the slot-based composition decision into an implementation checklist.

It answers:

- what has to change in each compiler stage
- what should land first
- what diagnostics and fixtures are needed
- what stays deferred

It follows the composition direction defined in [Composition Model](./composition-model.md).

## Scope

This checklist covers the first composition milestone only:

- default slots
- named slots
- fallback content
- grouped named-slot content through `<template slot:name>`

Deferred:

- scoped slot props
- dynamic slot names
- async slot semantics
- portal/teleport composition

## Milestone Goal

Make slots a real framework feature that works end to end through:

- parse
- analyze
- lower
- browser emission
- TodoMVC-scale verification discipline

## Phase 1: Parse

### Required parser support

- recognize `<slot>`
- recognize `<slot name="header">`
- preserve fallback children inside `<slot>`
- recognize parent-side `slot:name`
- recognize `<template slot:name>` only inside component usage

### Parser rules

- `<slot>` is treated as a reserved template tag
- `<slot>` may contain fallback children
- `<slot>` may optionally use `name="..."`
- parent-side `slot:name` is not a normal DOM attribute
- nested `<template>` remains invalid except for slot grouping use

### Parser outputs needed

- slot outlet node
- optional slot name
- fallback child nodes
- slot assignment metadata on projected nodes
- explicit template-group node for `<template slot:name>`

### Parser tests

- default slot outlet parses
- named slot outlet parses
- fallback content parses
- named slot provision parses
- grouped slot provision parses
- invalid nested `<template>` outside slot grouping fails

## Phase 2: Analyze

### Required semantic work

- distinguish child-side slot outlets from ordinary nodes
- distinguish parent-side projected slot content from ordinary component children
- validate slot names
- track slot scope boundaries

### Scope rules

- slot fallback content binds in child scope
- slot-provided content binds in parent scope
- slot content does not see child locals in the first version

### Diagnostics

- unknown named slot
- duplicate invalid slot syntax
- `slot:name` used outside component child context
- `<template slot:name>` used in invalid position
- invalid `name` usage on `<slot>`

### Analyzer tests

- default slot content binds in parent scope
- fallback binds in child scope
- unknown slot name fails clearly
- invalid slot placement fails clearly

## Phase 3: Lower

### Required lowered concepts

- slot outlet node
- slot fallback subtree
- slot provision map on component usage

### Lowering rules

- unnamed projected nodes lower into default slot content
- `slot:name` nodes lower into named slot provision entries
- grouped `<template slot:name>` lowers into a named slot provision with multiple children
- fallback content lowers as the child-side default subtree when no provision exists

### IR concerns

The existing IR likely needs:

- explicit slot outlet representation
- component child content separate from ordinary element children

This should not be hacked into generic attributes or generic child arrays if that obscures ownership.

### Lowering tests

- component usage with default slot lowers predictably
- named slots lower into stable provision records
- fallback content is preserved in the lowered form

## Phase 4: Browser Emit

### Required browser behavior

- child component receives compiled slot content from parent
- default slot renders when provided
- fallback renders when absent
- named slots resolve correctly
- slot content updates with parent scope

### Direct browser target requirements

- slot content should remain compiler-emitted content
- no opaque callback tree
- no runtime template interpretation introduced just for slots

### Likely runtime/codegen shape

- child instance owns slot outlet anchors or insertion handles
- parent passes compiled slot provision data or compiled fragment factories
- browser emitter mounts projected content into the child slot outlet regions

### Browser tests

- default slot mount/update
- named slot mount/update
- fallback render when absent
- switching parent state updates projected content correctly

## Phase 5: Fixtures and Verification

### Add canonical examples

At minimum:

1. `Panel.weiv`
   - default slot
2. `Card.weiv`
   - named `header` and default slot
3. `EmptyState.weiv`
   - fallback slot content
4. parent fixture using `<template slot:header>`

### Add checks

- parser fixtures
- analyzer diagnostics
- lowered output snapshots
- direct browser runtime checks
- one Cypress interaction case if slot content participates in updates

## Recommended Implementation Order

1. parse default `<slot>`
2. analyze/lower default slot
3. emit default slot in browser target
4. add named slots
5. add fallback content
6. add grouped `<template slot:name>`
7. tighten diagnostics and fixtures

This order keeps the complexity incremental while still moving toward the full first milestone.

## Exit Criteria

The first composition milestone is complete when:

- default and named slots work end to end
- fallback content works end to end
- grouped `<template slot:name>` works end to end
- slot diagnostics are clear
- the direct browser path supports projected content without regressing the compiler-driven direction

## Status

Completed on 2026-05-01 by the composition milestone hardening plan
(`docs/superpowers/plans/2026-05-01-composition-milestone-hardening.md`).

- default and named slots: verified in Cypress + IR snapshot tests
- fallback content: verified in Cypress (SlotShowcase) and IR snapshots
- grouped `<template slot:name>`: verified in CardUsage IR snapshot + Cypress reactive test
- diagnostics: 6 codes implemented and unit-tested
  - `slot.unknown_name`
  - `slot.duplicate_outlet`
  - `slot.assign_outside_component`
  - `slot.template_outside_component`
  - `slot.duplicate_provision`
  - `slot.default_not_supported`
- direct browser path supports projected content end to end, including
  parent-state-driven updates without remount (DOM identity verified by
  Cypress)

## Explicitly Deferred

Do not add in this milestone:

- scoped slot props
- slot functions
- render-prop composition
- dynamic slot names
- portal-like projection

Those should wait until the first slot model is stable and tested.
