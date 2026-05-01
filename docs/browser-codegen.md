# Browser Codegen Direction

## Purpose

This document defines the long-term browser runtime direction for `weiv`.

The key decision is:

- `weiv` should emit compiler-driven DOM programs
- `weiv` should not settle on a permanent VDOM architecture
- the current browser runtime is transitional infrastructure for validation, not the final execution model

## Decision Summary

The browser target should evolve toward:

- compiled `create`
- compiled `update`
- optional compiled `destroy`
- stable component instance records
- small runtime helpers for mounting, scheduling, and list/anchor primitives

The browser runtime should not remain a generic template interpreter.

## Why This Direction

`weiv` already owns the full template compile pipeline:

- parse
- analyze
- lower
- emit

That gives the compiler enough knowledge to precompute:

- static DOM shape
- dynamic text slots
- dynamic attribute/property slots
- event attachment points
- conditional anchors
- list anchors and reconciliation keys

If the compiler already knows those things, a generic VDOM layer is unnecessary overhead.

## Current State

Today the browser target works like this:

- templates lower into a generic IR tree
- emitted modules use a shared runtime walker
- local updates rerender the affected component boundary
- root-owned updates rerender the root component boundary

This is good enough for:

- verification examples
- runtime behavior bring-up
- TodoMVC-scale iteration

But it is not the intended end state because updates still rebuild component subtrees rather than patching precise DOM slots.

## Target Architecture

The browser target should compile each component into three conceptual parts.

### 1. Instance Layout

Each mounted component instance should own explicit references such as:

- root nodes or root anchors
- text nodes
- element nodes
- conditional block anchors
- list block anchors
- child component handles
- cached values needed for change checks

Example shape:

```js
{
  scope,
  nodes: {
    root,
    titleText,
    countText,
    submitButton,
  },
  blocks: {
    detailsIf,
    itemsFor,
  },
  children: {
    footer,
  },
  cache: {
    title,
    count,
    disabled,
  }
}
```

The exact JS shape can change, but the important point is that node ownership is explicit and stable.

### 2. Create Program

The compiler should emit imperative code that:

- creates DOM nodes once
- stores references on the instance
- attaches static attributes once
- attaches event listeners once
- mounts initial conditional/list blocks
- mounts child components

This should be specialized per component, not interpreted from a generic tree at runtime.

### 3. Update Program

The compiler should emit imperative update code that:

- reevaluates only relevant expressions
- compares against cached values
- patches text nodes in place
- patches attributes/properties in place
- toggles conditional branches through anchors
- reconciles list blocks
- forwards updates into child components without rebuilding unrelated DOM

This is the main performance-critical path.

## Runtime Boundary

The browser runtime should shrink to a helper layer.

### Runtime Should Own

- mount entrypoints
- scheduling/batching
- anchor helpers
- keyed list reconciliation helpers
- component boundary plumbing
- optional event delegation helpers

### Runtime Should Not Own

- template walking
- generic node interpretation for every update
- discovery of dynamic slots at runtime
- framework-wide VDOM diffing

The compiler should emit the update plan. The runtime should only execute small primitives.

## Compiler Pipeline Mapping

This direction changes the emphasis of the existing pipeline, especially `lower` and `emit/browser`.

### `parse`

No major conceptual change.

Still responsible for:

- SFC structure
- template syntax
- directive syntax

### `analyze`

Should continue to provide:

- binding resolution
- scope information
- component tag resolution
- expression ownership

It may later need to expose more information about:

- stable update dependencies
- event handler requirements
- list key candidates

### `lower`

This is the stage that should evolve most.

The current generic render IR is acceptable as a bridge, but the long-term browser lowering should move toward an operation-oriented model such as:

- static element declarations
- text slots
- attribute/property slots
- event slots
- conditional block records
- list block records
- child component mount/update slots

In other words, `lower` should stop thinking mainly in terms of a render tree and start thinking in terms of a DOM program.

### `emit/browser`

`emit/browser` should eventually target compiler-driven instance code rather than a shared runtime walker.

Likely output responsibilities:

- emit component instance factory
- emit create function
- emit update function
- emit destroy function where needed
- emit runtime imports only for browser primitives

## Recommended Lowered Browser Model

The next browser-specific lowered form should probably be a `BrowserDomPlan`.

Suggested categories:

- `CreateOp`
- `UpdateOp`
- `BlockPlan`
- `ListPlan`
- `ChildComponentPlan`

Example direction:

```text
BrowserDomPlan
  create_ops
  update_ops
  root_handles
  text_slots
  prop_slots
  event_slots
  conditional_blocks
  list_blocks
  child_components
```

This plan should still be compiler-owned and inspectable.

## Update Granularity

The intended progression is:

1. root rerender
2. component-boundary rerender
3. node/attribute/text patching within a component
4. keyed block/list reconciliation

`weiv` is currently at step 2.

The target for competitive browser performance is step 3 plus step 4, with compiled update code rather than a generic runtime interpreter.

## Conditionals

Conditionals should compile to anchor-based blocks.

The instance should keep:

- start anchor
- end anchor
- active branch id
- branch-local child/component handles if needed

Updates should:

- evaluate the condition
- keep the branch if unchanged
- otherwise swap only the affected block range

## Lists

Lists should not stay as naive rerendered loops.

The compiler/runtime contract should support:

- anchor-delimited list regions
- optional key extraction
- keyed reconciliation helpers
- per-row child/component reuse where possible

Keyed lists are necessary if `weiv` wants to be competitive beyond small demos.

## Events

Event listeners should be attached during create and remain stable across ordinary updates.

Updates should not require rebinding listeners unless:

- the element itself is replaced
- the listener identity model explicitly requires it

The compiler should prefer stable closures with instance access over reevaluating generic event expressions on every mount.

## Inputs And Form State

This area should be treated as a first-class browser-codegen concern.

Compiler-driven DOM updates should preserve:

- focus
- selection
- in-progress typing
- checked/selected state

That gets much easier once updates patch existing DOM instead of replacing component subtrees.

## Component Boundaries

Components remain useful as:

- ownership boundaries
- lifecycle boundaries
- list item reuse boundaries
- devtools/debug boundaries

But they should not become the permanent granularity of every update.

The ideal model is:

- compiler-driven patching inside a component
- component boundaries for composition and lifecycle

## Near-Term Implementation Plan

The next browser work should not try to optimize everything at once.

Recommended order:

1. Define `BrowserDomPlan`
2. Prototype direct codegen for:
   - static element creation
   - dynamic text
   - dynamic attribute/property
3. Emit `create` + `update` for a narrow component subset
4. Add anchor-based conditional patching
5. Add keyed list reconciliation helpers
6. Migrate TodoMVC paths onto the compiled browser target

## Success Criteria

This direction is working if:

- `emit/browser` no longer depends on a generic runtime walker for ordinary components
- text and attribute changes patch in place
- event listeners remain stable across updates
- list updates preserve row identity when keyed
- TodoMVC interactions work without component subtree replacement as the default update path

## Non-Goals For The First Browser Codegen Pass

- full SSR/browser unification
- native target design
- generalized reactive graph engine
- aggressive compile-time memoization everywhere

The first win is simpler:

- emit direct DOM code for browser components
- keep the runtime small
- prove the model on the verification app
