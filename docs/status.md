# Weiv Status

## Current State

`weiv` is an early compiler-first frontend framework prototype with a working
direct-DOM browser path.

The current vocabulary for this architecture is documented in
[Terminology](./terminology.md).

The current direction for the next script-side precision upgrade is documented
in [AST Script Analysis Plan](./archive/ast-script-analysis-plan.md).
The current active next-direction for cross-component/shared state is
documented in [Shared Observable State Design](./archive/shared-observable-state-design.md).
The next diagnostics collection direction is documented in
[Compiler Diagnostics Architecture](./archive/compiler-diagnostics-architecture.md).
The current direct-browser timing flow is documented in
[Runtime Scheduling](./runtime-scheduling.md).

The repo currently has:

- `.weiv` parsing and validation
- TypeScript script analysis through the Rust parser backend
- template-to-script binding
- scoped CSS emission
- IR and browser-plan lowering
- direct browser component modules
- app bundle emission
- slot composition
- compiler-native invalidation-graph inspection
- owned-boundary scheduling for direct browser events and selected callbacks
- conventional `props` plus Weiv-provided `emit` component contracts

The repo also now has a standalone shared observable runtime plus the first
imported-observable integration path for shared cross-boundary state.

The runtime also includes a client-side router with route matching, nested
routes, navigation guards, link interception, scroll restoration, and
observable route state.

## Direct DOM Path

The direct browser emitter now has:

- retained DOM references
- create/update/destroy functions
- region update functions for text, attributes, conditionals, loops, children,
  and slots
- owned-boundary scheduling through `runOwnedBoundary`
- destroyed-instance guards for async settle flushes
- local callback wrappers for `setTimeout`, `setInterval`, `queueMicrotask`,
  and `requestAnimationFrame`

Selective dirty-binding-to-region execution is now implemented for the direct
browser path. The remaining caveat is that some region guards are still
conservative, so the runtime may update a broader safe subset of regions than
the theoretical minimum.

## Invalidation Graph

`weiv inspect invalidation-graph <path>` reports:

- update regions
- visible dependencies
- whether each region expression compiled to direct access or still falls back to
  runtime evaluation
- coarse fallback reasons for the remaining dynamic expressions
- mutation sites
- owned event boundaries
- hidden-state template call diagnostics
- hidden-state diagnostics for local helpers that still read external state or
  perform side effects
- source-located conservative diagnostics for alias mutation, unowned callback
  mutation, and expression-position mutation
- runtime-evaluate fallback diagnostics for expressions that still need
  `evaluate(...)`
- expression-position mutation diagnostics
- visible alias-mutation diagnostics for unsupported simple alias writes
- unowned callback mutation diagnostics
- framework binding conflict diagnostics such as user-defined `emit`

This is the primary debugging surface for the compiler-native state model.

## Composition

Slots are implemented and covered by compiler and render tests.

Current slot behavior includes:

- default and named slot mount
- fallback content
- grouped named slots
- projected content updates from parent-owned state
- nested slot trees
- fallback/projected switching after mount
- destroy behavior for projected slot handles

## Router

The runtime router (`packages/weiv/src/runtime/router.ts`) provides:

- route matching with static, `:param`, and `*` wildcard segments
- nested routes with parent preservation and child swapping
- navigation guards: global `beforeEach`, per-route `beforeEnter` and `beforeLeave`
- `afterEach` post-navigation hooks
- link interception for internal `<a>` clicks
- scroll restoration via `scrollBehavior` callback
- observable `route` state (`path`, `params`, `query`, `matched`)
- lazy component loading (async `component` functions)
- history and hash modes
- `push`, `replace`, `back`, `forward` navigation
- `ready` promise for initial mount
- full cleanup via `destroy()`

The router integrates directly with emitted component `mountIntoBoundary` /
`destroy` lifecycle — no adapter needed.

## Verification

Current required verification:

```sh
zig build test
zig build component-test
zig build runtime-test
```

All pass at the latest checkpoint.

Bare package imports (e.g. `lodash-es`) are now supported through import map
generation in the emitted `index.html`. The browser resolves bare specifiers
via the import map to `/node_modules/<package>` paths.

## Verification Shape

The current verification shape is still uneven:

- many narrow compiler/runtime fixtures
- TodoMVC as the main app-like verification example in practice

The first `test/examples/kanib` scaffold is now present, but it still
needs fuller component-test and inspect coverage before it replaces TodoMVC as the
broader app-scale anchor.

The broader shared-state/runtime direction is now much clearer:

- local component state remains compiler-first
- shared cross-boundary state should be created explicitly with
  `observable()` at the source
- components consume imported observables automatically through the compiler
  bridge

Archived proxy-state and companion/store notes are retained for historical
context, but they are no longer the active top-level story.

## Known Caveats

- `evaluate(...)` still exists in generated direct browser output for some dynamic
  expressions, but those fallback sites are now inspectable in
  `inspect invalidation-graph`.
- `emit` is reserved and injected, but event payload typing still depends on
  future IDE virtual declarations from `export interface Emits`.
- Region update functions are selective, but some dependency guards are still
  conservative rather than fully minimal.
- Local function dependency analysis now expands local helper calls, but alias
  analysis is still intentionally shallow.
- Alias analysis is intentionally limited beyond simple diagnosed cases.
- Arbitrary imported callback registration is not owned by the scheduler.
- shared observable integration is still conservative: imported observables wake
  the existing component update path rather than a more precise observable-to-
  region dependency map
- Binding-phase diagnostics now carry a formal `error` / `warning` / `info`
  severity model, and invalidation-graph diagnostics now surface `warning` /
  `info` levels in the inspect output while remaining inspect-only.
- CLI failure paths now support canonical machine-readable diagnostics through
  `--json-diagnostics` (`action`, `sourcePath`, `ok`, and structured
  diagnostics records).
- `weiv dev` now watches and rebuilds, defaults to an ephemeral preview
  port unless `PORT` is set, debounces rebuilds after file changes, and now
  emits normalized `weiv dev info <event>: ...` log lines; the loop is still
  polling-based but now supports tuning via `WEIV_DEV_WATCH_POLL_MS` and
  `WEIV_DEV_REBUILD_DEBOUNCE_MS`, limits scans to watch-relevant source files,
  and throttles repeated scan-failure diagnostics.
- diagnostics are still not fully unified across every code path: the main
  failure surface is now structured, but dev-loop informational output and some
  secondary internals still need normalization.

## Current Health

The project is in a good checkpoint state:

- architecture direction is documented
- current implementation matches the direction
- shared observable state is now a real runtime/compiler behavior, not only a
  design note
- direct render verification is green
- TodoMVC remains a useful forcing-function example, while kanib is the
  larger verification track now in active use
- stale-risk state patterns are becoming inspectable instead of magical
