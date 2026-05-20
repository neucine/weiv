# Runtime API

Weiv keeps the default runtime surface small.

Today the public runtime helpers are focused on two areas:

- observable shared state
- client-side routing

## Observable

File: `packages/weiv/src/runtime/observable.ts`

Public surface:

- `observable(value)` creates a tracked proxy object
- `subscribe(observableValue, listener)` listens for changes
- `snapshot(observableValue)` returns a frozen plain-object copy
- `isObservable(value)` checks whether a value is observable
- `observableBrandSymbol()` exposes the internal brand symbol

Semantics:

- nested objects are wrapped lazily on read
- repeated reads return stable nested proxy identities
- sync writes are batched into one microtask notification wave
- nested writes notify both the nested node and its parent chain
- replacing or deleting a nested object detaches the old child from the former
  parent chain
- `snapshot()` returns a frozen plain-object view detached from later writes

## Router

File: `packages/weiv/src/runtime/router.ts`

### Usage

```typescript
import { createRouter } from "weiv:router";

const router = createRouter({
  mode: "history",
  base: "",
  routes: [
    { path: "/", component: () => HomeModule },
    {
      path: "/users/:id",
      component: () => UserModule,
      props: (route) => ({ userId: route.params.id }),
    },
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
  scrollBehavior: ({ from, to }, savedPosition) =>
    savedPosition ?? { x: 0, y: 0 },
});

await router.ready;
```

### API

| Method / Property | Description |
| --- | --- |
| `router.route` | Observable route state with `path`, `params`, `query`, and `matched` |
| `router.ready` | Promise that resolves after the initial route mounts |
| `router.push(path)` | Navigate to a path and add a history entry |
| `router.replace(path)` | Navigate to a path and replace the current history entry |
| `router.back()` | Go back in history |
| `router.forward()` | Go forward in history |
| `router.beforeEach(guard)` | Add a global navigation guard |
| `router.afterEach(hook)` | Add a post-navigation hook |
| `router.destroy()` | Remove listeners and unmount components |

### Features

- static, dynamic, and wildcard route matching
- nested routes with merged params
- async global and per-route navigation guards
- internal link interception for normal in-app navigation
- lazy-loaded route components
- scroll restoration hooks
- observable route state
- history and hash routing modes

## Integration

Weiv's current component integration depends on the observable brand and
metadata contract directly rather than importing wrapper helpers from
`weiv:observable`.

The router works with component modules that export
`mountIntoBoundary(start, end, props)`.
