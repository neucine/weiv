# Weiv Runtime

This folder holds the standalone shared runtime modules for Weiv.

## Observable (`observable.ts`)

Proxy-based reactive state with parent-chain propagation and microtask batching.

Public surface:

- `observable(value)` — create a tracked proxy object
- `subscribe(observableValue, listener)` — listen for changes
- `snapshot(observableValue)` — frozen plain-object copy
- `isObservable(value)` — type check
- `observableBrandSymbol()` — internal brand symbol

Semantics:

- nested objects are wrapped lazily on read
- repeated reads return stable nested proxy identities
- sync writes are batched into one microtask notification wave
- nested writes notify both the nested node and its parent chain
- replacing or deleting a nested object detaches the old child from the former
  parent chain
- `snapshot()` returns a frozen plain-object view detached from later writes

## Router (`router.ts`)

Client-side router that integrates with Weiv's `mountIntoBoundary`/`destroy`
component lifecycle.

### Usage

```typescript
import { createRouter } from "weiv:router";

const router = createRouter({
  mode: "history",       // "history" (pushState) or "hash" (#-based)
  base: "",              // optional URL base path
  routes: [
    { path: "/", component: () => HomeModule },
    { path: "/users/:id", component: () => UserModule, props: (route) => ({ userId: route.params.id }) },
    {
      path: "/dashboard",
      component: () => DashLayoutModule,
      children: [
        { path: "/overview", component: () => OverviewModule },
        { path: "/stats", component: () => StatsModule },
      ],
    },
    { path: "/lazy", component: () => import("./LazyModule.mjs") },
    { path: "/files/*", component: () => FileBrowserModule },
  ],
  target: document.getElementById("app")!,
  scrollBehavior: ({ from, to }, savedPosition) => savedPosition ?? { x: 0, y: 0 },
});

await router.ready;
```

### API

| Method / Property | Description |
|---|---|
| `router.route` | Observable `{ path, params, query, matched }` — subscribe to react to route changes |
| `router.ready` | Promise that resolves after initial route mounts |
| `router.push(path)` | Navigate to path (adds history entry) |
| `router.replace(path)` | Navigate to path (replaces current history entry) |
| `router.back()` | Go back in history |
| `router.forward()` | Go forward in history |
| `router.beforeEach(guard)` | Add global navigation guard; returns unsubscribe function |
| `router.afterEach(hook)` | Add post-navigation hook; returns unsubscribe function |
| `router.destroy()` | Remove all listeners, unmount components |

### Features

- **Route matching**: static segments, `:param` dynamic segments, `*` wildcard catch-all
- **Nested routes**: parent stays mounted while children swap; params merged across levels
- **Navigation guards**: `beforeEach` (global), `beforeEnter` (per-route), `beforeLeave` (per-route). Return `false` to block, a string to redirect, or void to allow. Async guards supported.
- **Link interception**: internal `<a>` clicks are caught and routed through `push()`. Skips external links, `target="_blank"`, modifier keys, `download`, `mailto:`/`tel:`.
- **Lazy loading**: `component` can return a Promise for code-split routes
- **Scroll restoration**: `scrollBehavior` callback receives navigation context and saved position. Supports `{ x, y }` coordinates or `{ el: "#selector" }`.
- **Observable route state**: `router.route` is an observable — any component can `subscribe()` to it
- **History and hash modes**: `mode: "history"` (pushState) or `mode: "hash"` (#-based with hashchange listener)

### Guard Types

```typescript
// Global guard — runs before every navigation
router.beforeEach(async ({ from, to }) => {
  if (to.path === "/admin" && !isAuthenticated()) return "/login";
});

// Per-route enter guard
{ path: "/admin", component: () => AdminModule, beforeEnter: ({ to }) => isAdmin() }

// Per-route leave guard (unsaved form protection)
{ path: "/editor", component: () => EditorModule, beforeLeave: () => !hasUnsavedChanges || confirm("Discard?") }
```

## Integration

Weiv component integration currently relies on the observable brand and metadata
contract directly rather than importing these helper wrappers from
`weiv:observable`. The router works with any module that exports
`mountIntoBoundary(start, end, props)`.
