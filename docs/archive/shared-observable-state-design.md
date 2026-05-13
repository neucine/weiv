# Shared Observable State Design

This document defines the active next-direction for shared state in Weiv.

It replaces the earlier "late proxying of imported/shared objects inside the
component" direction as the preferred path forward.

## Core Split

Weiv should keep two different state stories:

- **component-owned local state**
  - plain JS/TS authoring
  - compiler-owned analysis, instrumentation, and scheduling
  - no shared-state ceremony by default
- **shared state beyond the component boundary**
  - explicit runtime-owned observable state
  - created at the shared-state source
  - consumed naturally inside `.weiv` components

## Why The Previous Proxy Direction Is Not Enough

The earlier proxy-state-graph work proved something useful, but it also exposed
a hard limitation:

- a proxy only intercepts writes that go through the proxy reference
- writes through a raw/original reference bypass the proxy trap

That makes this pattern too weak:

1. a component imports a plain shared object
2. Weiv wraps it later inside the component
3. some imported helper still mutates the raw shared object

So the new rule is:

- if state is shared beyond the component boundary, it should be created as
  observable state at the source
- Weiv should not rely on "proxy this plain object later in the consumer" as the
  main shared-state contract

## Target Authoring Model

Shared state should be created through one Weiv helper:

```ts
import { observable } from "weiv:observable";

export const workspace = observable({
  notifications: 3,
  selectedItemId: "activity-2",
});
```

Templates and component code should read it naturally:

```html
<p>{{ workspace.notifications }}</p>
```

```ts
function clearAlerts() {
  workspace.notifications = 0;
}
```

The preferred helper name is:

- `observable`

## Foundation Contract

The public shared observable runtime contract should be:

1. `observable(value)` returns the tracked shared object
2. nested writes are observable
3. writes eventually notify subscribers
4. Weiv components can subscribe/unsubscribe automatically

The compiler should stay mostly agnostic to how the runtime implements that
contract internally. It mainly needs to know:

- this imported value is shared observable state
- component reads from it participate in UI updates
- component instances must subscribe/unsubscribe correctly

The compiler/runtime bridge should rely on:

- a stable observable brand identity
- stable internal metadata fields the compiler is allowed to use

not on a large public helper surface.

## Local State Remains Compiler-First

This shared-state direction does **not** replace the current local state model.

Local component state should still be:

- plain variables
- plain local objects
- compiler-owned mutation analysis
- owned-boundary scheduling
- direct DOM patch planning

So Weiv keeps:

- **local state**: compiler-native
- **shared state**: runtime observable

## Implementation Order

Implementation should happen in this order:

1. build the shared observable runtime semantics first
2. verify the runtime independently
3. then integrate it into Weiv component codegen/scheduling

## Current Status

What is already true on `main`:

- Weiv has a working compiler-first local-state baseline
- Weiv has owned-boundary scheduling and selective region updates
- Weiv has an experimental proxy-tracked-root implementation for some shared
  paths

What this document changes:

- the experimental late-proxy tracked-root path is no longer the preferred
  forward architecture for shared state
- the preferred path is explicit `observable()` shared state created at the
  source, with Weiv-integrated component consumption
