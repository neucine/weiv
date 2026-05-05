# Composition Model

## Purpose

This document defines the first-class composition model for `weiv`.

The main question is:

- how parent components provide child content
- how child components expose insertion points
- how that content remains analyzable in a compiler-first framework

The goal is to support composition without pulling `weiv` toward JSX-style render functions or opaque runtime magic.

Implementation checklist:

- see [Composition Implementation](./composition-implementation.md)

## Decision Summary

`weiv` should adopt a slot-style composition model.

Initial direction:

- child components expose `<slot>` insertion points
- parents provide content with `slot:name` on direct child nodes
- unnamed content maps to the default slot
- slot content stays template syntax, not render-function syntax
- slot content is compiled, not runtime-interpreted as an opaque callback tree

This should be the first composition model, not a later optional add-on.

## Why Slots

Slots fit `weiv` better than alternatives.

### Why Not Render Props First

Render props would push composition toward function-valued UI generation.

That creates problems for `weiv`:

- moves UI authoring back toward JS-driven templating
- weakens the template-first authoring model
- makes compile-time reasoning more complex
- pulls the framework closer to JSX-era composition patterns

That is not the direction we want for the default path.

### Why Not Implicit Children-Only Content First

A single anonymous child-content mechanism is too weak.

It would quickly run into:

- multiple insertion point needs
- layout/component shell patterns
- card/header/footer-style composition

So if `weiv` adds composition, it should add named structure early rather than a too-small placeholder model.

### Why Slots Fit

Slots preserve:

- declarative templates
- analyzable structure
- separation between provider and consumer
- compiler visibility into projected content

They also map cleanly onto:

- browser direct codegen
- SSR output later
- component boundary semantics

## Initial Syntax Direction

### Child Side

Child components expose insertion points with `<slot>`.

Default slot:

```html
<section class="panel">
  <slot />
</section>
```

Named slot:

```html
<header class="card-header">
  <slot name="header" />
</header>
```

Fallback content:

```html
<slot name="header">
  <h2>Untitled</h2>
</slot>
```

### Parent Side

Parents provide slot content through ordinary template nodes.

Default slot:

```html
<Card>
  <p>Hello</p>
</Card>
```

Named slot:

```html
<Card>
  <h2 slot:header>Dashboard</h2>
  <p>Main content</p>
</Card>
```

Multiple nodes in one named slot:

```html
<Card>
  <template slot:header>
    <h2>Dashboard</h2>
    <p>Daily overview</p>
  </template>

  <p>Main content</p>
</Card>
```

This implies one syntax addition:

- a special grouping `<template slot:name>` form inside component usage

That grouping form should only be valid in slot-provision contexts, not as a general-purpose nested template mechanism.

## Initial Rules

### 1. Default Slot

- unnamed direct children of a component usage go to the default slot
- if the child component has no default slot, extra unnamed content is a compile error

### 2. Named Slots

- `slot:name` assigns the node or template-group to the named slot
- repeated named slot groups for the same slot should concatenate in document order initially
- unknown slot names should be a compile error

### 3. Slot Fallback

- fallback content inside `<slot>` is rendered only when the parent does not provide that slot

### 4. Slot Scope

Initial version should keep slot scope simple:

- slot content resolves against the parent component scope
- it does not automatically see arbitrary child local bindings

This is important for predictability and compiler reasoning.

### 5. No Scoped Slot Props in Phase 1

Deferred:

- `<slot bind:value="...">`
- slot props
- scoped slots
- template parameters flowing from child to parent

Reason:

- that is a real feature, but it complicates scope rules substantially
- default and named slots should land first

## Compiler Consequences

Slots are not just syntax sugar. They affect several phases.

### Parse

Need to parse:

- `<slot>`
- optional `name`
- optional fallback children
- parent-side `slot:name`
- grouping `<template slot:name>`

### Analyze

Need to validate:

- slot names used by parent exist in the child
- slot placement is valid
- fallback content binds in child scope
- provided slot content binds in parent scope

This means slot resolution is a real binding concern, not only codegen.

### Lower

Need slot-aware intermediate representation.

Likely concepts:

- slot outlet node
- slot fallback subtree
- slot provision map on component usage

The browser lowering stage should eventually treat slot content like compiled child content regions, not runtime string blobs.

### Emit / Browser

The browser target should compile:

- child slot outlets
- parent-provided slot fragments
- fallback substitution behavior

This should stay compiler-driven and explicit.

## SSR Consequences

Slots should help, not hurt, SSR.

Because slots stay declarative and structural, SSR can later:

- render provided slot content directly
- render fallback content when absent
- preserve the same composition semantics as the browser target

That is another reason to prefer slots over render-prop-first composition.

## Deferred

Not in the first composition milestone:

- scoped slot props
- dynamic slot names
- portal/teleport composition
- async slot boundaries
- higher-order render functions as a composition primitive

These can be reconsidered later if the framework direction really needs them.

## Recommended Implementation Order

1. default slot outlet
2. named slots
3. fallback content
4. grouping `<template slot:name>`
5. diagnostics for unknown or duplicate slot usage

This order gives useful composition quickly while keeping the compiler work incremental.

## Decision

`weiv` should adopt:

- slots as the primary composition model
- default and named slots first
- parent-scope slot content
- no scoped slot props in the first implementation

That keeps composition aligned with the framework’s template-first, compiler-first direction.
