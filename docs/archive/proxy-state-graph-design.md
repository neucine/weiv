# Proxy State Graph Design

## Purpose

This document is the consolidated design for proxy-backed tracked state in
`weiv`.

It replaces the earlier split notes for:

- direction
- implementation model
- example matrix
- selection and diagnostics
- compiler/runtime contract
- current pipeline alignment

The goal is to keep one authoritative design document instead of a chain of
small proxy-state notes.

## Problem

The current compiler-first baseline is already strong:

- precise in many paths
- conservative but correct in blurry owned paths
- inspectable where precision stops

The hard remaining problem is not local mutation inside Weiv-owned boundaries
such as:

- template events
- child events
- compiler-wrapped callbacks

Those paths are already correct because Weiv owns the flush boundary.

The hard problem is mutation outside Weiv-owned boundaries, such as:

- shared mutable module state
- escaped object references
- later mutation through aliases
- external callback systems
- object-heavy state the compiler cannot fully follow

In those cases, the compiler may know which regions depend on a path, but not
when that path changed.

## Baseline And Goal

The proxy-state design does **not** replace the current baseline.

The intended split is:

### Local owned state

- keep simple local bindings
- keep compiler-first region planning
- keep owned-boundary conservative fallback

### Escaping / externalized state

- expose it through a canonical tracked surface
- use proxy-backed write detection
- map dirty paths into the existing compiler-planned region scheduler

So proxy-backed state is the stronger model for out-of-boundary mutable object
state, not the new default for every local binding.

## Why Proxy

Proxy is not the only possible tracking mechanism, but it is the best current
fit because:

- object mutation stays ergonomic
- nested mutable state is practical
- runtime can observe writes the compiler cannot directly see
- it fits the actual hard cases better than top-level-only cells or shallow
  descriptors

The costs are real:

- proxy is a wrapper around the target, not the target itself
- canonical access matters
- raw escape is still possible
- runtime overhead exists

That is why the design must stay:

- narrow
- canonical
- compiler-indexed

not a blanket proxy-everything model.

## Core Design

The proxy-state graph is path-oriented, not a generic reactive effect graph.

The compiler remains responsible for:

- tracked-root selection
- tracked-path extraction
- path-to-region mapping
- escape diagnostics

The runtime remains responsible for:

- canonical proxy creation
- write interception
- dirty-path accumulation
- handing dirty paths to the existing scheduler

Conceptually:

1. compiler identifies tracked roots and tracked paths
2. runtime exposes canonical proxy-backed roots
3. writes through those proxies mark dirty `pathId`s
4. existing region scheduling consumes those dirty ids
5. existing region patch functions update the DOM

## Tracked Roots

A tracked root is the top-level value that becomes the canonical tracked entry
point for state Weiv must observe outside simple owned-boundary mutation.

Examples:

- `workspace`
- `user`
- `session`
- `selectedItem`

### Promotion Categories

Relevant bindings classify into:

1. `local-baseline`
2. `owned-conservative`
3. `tracked-root`
4. `escape-warning`

These are not mutually exclusive over time. A binding may be a `tracked-root`
and also have an `escape-warning` use site.

### `local-baseline`

Use when all of these are true:

- binding is local
- binding is not imported/exported shared state
- template use is primitive or shallow enough
- known mutation stays inside owned Weiv boundaries
- binding does not escape into unknown external code

Typical cases:

- `let count = 0`
- `let open = false`

### `owned-conservative`

Use when:

- mutation shape is nested or alias-heavy
- but it still stays inside owned boundaries
- and the binding is not otherwise shared/externalized

Typical cases:

- local nested object mutation in a click handler
- local alias mutation inside a wrapped callback

Meaning:

- correctness still comes from owned-boundary flush
- no proxy root required yet

### `tracked-root`

Promote when any of these are true:

- nested template dependency on imported/shared object state
- nested template dependency on `props` object state
- nested template dependency on stable local object state that can keep one
  canonical tracked root
- object state crosses component boundaries
- imported mutable object state participates in template/runtime-visible logic
- exported or module-visible mutable object state is intended for reuse
- known out-of-boundary participation still goes through a canonical tracked
  surface

Bias:

- object-like values promote more easily
- primitive local bindings resist promotion unless clearly shared/externalized
- stable local object roots can promote even when the binding itself is
  `const`/immutable, as long as the root is not reassigned and does not become
  an alias target

### Non-Promotion Rule

Do **not** promote just because:

- a binding is mutable
- it appears in the template
- it has nested shape
- it is passed around only locally within owned execution

This protects Weiv from drifting into proxy-everything.

## Tracked Paths

A tracked path is a compiler-known property chain under a tracked root that a
template region depends on.

Examples:

- `workspace.sidebar.collapsed`
- `user.profile.name`
- `session.currentProject.id`

For each leaf path, the compiler also tracks replaceable ancestors.

If the template depends on:

- `user.profile.name`

then the relevant tracked paths are:

- `user`
- `user.profile`
- `user.profile.name`

because ancestor replacement must also invalidate the leaf.

Only paths that matter to template or runtime-visible derived helpers need
precise mapping. Unrelated sibling branches do not need their own graph nodes.

## Canonical Proxy Surface

Every tracked root must have one canonical proxied surface.

Rules:

- compiler/runtime code should use the proxied root
- nested objects should be proxied lazily from that root
- the raw target should not be the normal public surface
- proxy instances should be cached so the same raw target maps to the same
  proxy

The intended shape is:

- narrow root selection
- lazy nested proxying
- canonical use of the proxied surface

not eager deep proxying across the whole app.

## Dirty Marking

Tracked proxy writes should produce compiler-meaningful dirty paths.

### Direct leaf write

```ts
workspace.sidebar.collapsed = true;
```

marks:

- `workspace.sidebar.collapsed`

### Ancestor replacement

```ts
workspace.sidebar = nextSidebar;
```

marks:

- `workspace.sidebar`

and all tracked descendants under it are treated as affected.

### Root replacement

```ts
workspace = nextWorkspace;
```

marks:

- `workspace`

and the full tracked subtree is treated as affected.

Dirty work should accumulate into a stable set such as:

- `Set<PathId>`

or equivalent indexed representation.

## Compiler Runtime Contract

The compiler should be able to emit a small metadata block for each component.

Conceptually:

```ts
type StateGraphPlan = {
  roots: RootPlan[];
  paths: PathPlan[];
  regions: RegionDependencyPlan[];
};
```

### Root plan

```ts
type RootPlan = {
  rootId: number;
  bindingName: string;
  kind: "local-tracked" | "imported-tracked" | "prop-tracked";
  pathStart: number;
  pathCount: number;
};
```

### Path plan

```ts
type PathPlan = {
  pathId: number;
  rootId: number;
  segments: string[];
  parentPathId: number | null;
  subtreeEnd: number;
};
```

### Region dependency plan

```ts
type RegionDependencyPlan = {
  regionId: number;
  directPathIds: number[];
};
```

The runtime hook surface should stay small.

Conceptually:

```ts
type TrackedStateRuntime = {
  initRoot(rootId: number, value: unknown): unknown;
  markDirty(pathId: number): void;
  consumeDirtyPaths(): Uint32Array | number[];
};
```

This is not a generic public reactivity API. It is a compiler-targeted dirty
tracking layer.

## Existing Pipeline Alignment

The proxy-state design should land on structures Weiv already has.

The existing direct browser output already exposes the right seam:

- `instance.update()` for broad refresh
- `instance.updateDirty(dirtyBindings, scope)` for selective region execution

So the proxy graph should not invent a second scheduler. It should evolve that
seam from:

- dirty bindings

into:

- dirty bindings for the local baseline
- dirty path ids for tracked proxy roots

Conceptually:

```ts
instance.updateDirty(dirtyState, scope)
```

where `dirtyState` can eventually contain both:

- local binding dirtiness
- tracked path dirtiness

### Suggested compiler layering

1. script analysis / binding phase
   - classify bindings
2. invalidation-graph phase
   - assign tracked root ids
   - assign tracked path ids
   - attach path dependencies to existing region ids
3. browser-plan / codegen phase
   - emit metadata tables
   - emit selective path-aware update logic
   - emit inspect-visible metadata

### Region dependency shape

Existing regions should gain optional tracked-path metadata:

```ts
type RegionDependencyShape = {
  bindingDeps: string[];
  trackedPathIds: number[];
};
```

This lets the current baseline and proxy-backed tracking coexist.

## Escape Model

Proxy does not eliminate raw-reference escape.

The design assumes:

- the proxied surface is canonical
- raw escape weakens guarantees

### Safe tracked use

When code keeps using canonical proxied roots or descendants:

- dirty marking remains trustworthy

### Escape warning use

When tracked roots or tracked subpaths are:

- passed to unknown external calls
- returned as nested references
- stored on external objects
- exported as raw/nested references
- captured into alias flows that outlive local owned execution

Then:

- compiler emits `escape-warning`
- runtime may still work if mutation continues through the proxy
- Weiv no longer silently assumes strong guarantees

### Raw untracked escape

When later mutation may happen through raw unproxied references:

- proxy dirty marking may be bypassed
- correctness only survives if some owned flush point still exists
- otherwise freshness is no longer guaranteed

This must be treated as a strong diagnostic boundary, not hidden behavior.

## Diagnostics

Diagnostics should do three things:

1. say what escaped or blurred
2. say why that weakens guarantees
3. suggest the smallest deterministic rewrite

Typical rewrite guidance:

- pass snapshots or primitives instead of tracked mutable objects
- keep tracked state inside Weiv-owned APIs
- mutate through the tracked root directly instead of mutating through a local alias
- move tracked mutation into an owned boundary instead of leaving it in an
  unowned callback

Current practical scope on `main` is narrower than the full design space above:

- mainstream warnings currently focus on concrete Weiv tracking gaps that are
  easy to explain, especially alias escape and unowned callback mutation
- Weiv does not currently try to warn on every common JS detached-reference or
  reference-replacement pattern
- the tracked guarantee is about the visible captured binding/reference Weiv
  owns, not arbitrary unrelated references later created elsewhere in JS

Recommended severity split:

- `warning` when freshness guarantees meaningfully weaken
- `info` when the compiler is suspicious but not strongly certain

## Inspect Surface

The first proxy-state implementation should show up in
`weiv inspect invalidation-graph`, not only in generated JS.

Recommended new sections:

### `tracked-roots`

```text
tracked-roots
  root id=1 binding=workspace kind=imported-tracked
```

### `tracked-paths`

```text
tracked-paths
  path id=1 root=1 path=workspace
  path id=2 root=1 path=workspace.sidebar
  path id=3 root=1 path=workspace.sidebar.collapsed
```

### Region path dependencies

Extend region lines with something like:

- `tracked_paths=[3,5]`

The first implementation should prove:

- root selection
- path extraction
- region/path mapping

before it proves runtime proxy behavior.

## Concrete Examples

### Plain local counter

```ts
let count = 0;
function increment() {
  count += 1;
}
```

Template:

```html
<p>{{ count }}</p>
```

Classification:

- `count` -> `local-baseline`

### Local nested object in owned event

```ts
let user = { profile: { name: "Ada" } };
function rename() {
  user.profile.name = "Grace";
}
```

Template:

```html
{{ user.profile.name }}
```

Classification:

- `user` -> `owned-conservative`

### Imported shared nested object

```ts
import { workspace } from "./app-state.ts";
```

Template:

```html
{{ workspace.sidebar.collapsed }}
```

Classification:

- `workspace` -> `tracked-root`

Tracked paths:

- `workspace`
- `workspace.sidebar`
- `workspace.sidebar.collapsed`

### Tracked state passed to unknown helper

```ts
installPlugin(workspace.profile);
```

Classification:

- `workspace` -> `tracked-root`
- call site -> candidate future expansion, not a mainstream warning by default

### Returned tracked nested reference

```ts
function currentSidebar() {
  return workspace.sidebar;
}
```

Classification:

- `workspace` -> `tracked-root`
- return site -> candidate future expansion, not a mainstream warning by default

## Current Implemented Slice

The current shipped slice on `main` now includes:

1. tracked-root support for:
   - imported object roots
   - `props` object roots
   - a narrow stable local-object slice
2. `inspect invalidation-graph`
   - prints tracked roots
   - prints tracked paths
   - prints region-to-tracked-path mapping
   - prints current `escape-warning` diagnostics
3. direct browser codegen/runtime
   - emits tracked-state metadata tables
   - canonicalizes current tracked roots
   - accepts dirty path ids in the existing selective updater
   - produces dirty path ids through proxy-backed runtime tracking
4. `compile analyze component`
   - summarizes tracked roots by kind
   - summarizes current escape warnings
   - includes rewrite guidance for current warning reasons

This means the proxy-state graph is now an active implementation path, not only
an inspect-only or design-only concept.

## Non Goals

This design does **not** currently imply:

- proxying every local binding
- replacing the local authoring model with runtime-only reactivity
- inventing a second scheduler
- guaranteeing freshness after arbitrary raw escape
- exposing a generic public reactivity API as the immediate next step

## Recommendation

The current recommendation is:

- keep the compiler/conservative local baseline
- introduce a narrow proxy-backed tracked graph only for escaping or
  externalized object state
- treat it as a compiler-indexed dirty-path layer
- reuse existing invalidation regions and the existing selective update seam
- rely on build-time escape diagnostics to keep the boundary honest

That is the strongest current middle path between:

- compiler must infer arbitrary mutation timing statically
- and a full generic runtime reactivity model everywhere
