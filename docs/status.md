# Weiv Status

## Current State

`weiv` is an early compiler-first frontend framework prototype with a working
direct-DOM browser path.

The current vocabulary for this architecture is documented in
[Terminology](./terminology.md).

The current direction for the next script-side precision upgrade is documented
in [AST Script Analysis Plan](./ast-script-analysis-plan.md).
The current design direction for future explicit compiler-facing script helpers
is documented in [Authoring Helpers](./authoring-helpers.md), but that is
currently deferred behind AST-backed analysis work.
The current state-tracking direction for escaped / externalized state is
documented in [Proxy State Graph Design](./proxy-state-graph-design.md), and
the first tracked-root runtime slices are now live on `main`.

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

The repo also now has documented shared-state/runtime design exploration:

- a candidate `@weiv/store` draft API contract
- a candidate `@weiv/store` implementation sketch
- a broader research memo comparing that candidate with stronger runtime-backed
  options such as MobX-style observability
- an active proxy-based state-graph direction for escaping or externalized
  state, with initial imported / props / narrow-local tracked-root support
- `@weiv/router` intentionally deferred behind shared-state/runtime decisions

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
- tracked roots and tracked paths for promoted proxy-backed state roots
- `escape-warning` diagnostics when tracked roots weaken through alias or
  unowned callback flows
- framework binding conflict diagnostics such as user-defined `emit`

This is the primary debugging surface for the compiler-native state model.

`weiv inspect state-plan <path>` remains available as a compatibility alias.

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

## Verification

Current required verification:

```sh
zig build test
zig build render-test
```

Both pass at the latest checkpoint.

`zig build test` still prints the expected unsupported-import negative-fixture
stderr:

```text
error: unsupported bare runtime import in .../examples/unsupported-import/App.weiv: lodash-es
```

That stderr is expected and does not indicate test failure.

## Verification Shape

The current verification shape is still uneven:

- many narrow compiler/runtime fixtures
- TodoMVC as the main app-like verification example

What is still missing is a clearly larger flagship verification app that can
show the framework's strengths and conservative gaps at a broader scale than
TodoMVC.

The shared-state/runtime direction is also still at the design/planning stage.
There is no settled official companion/runtime package yet. The earlier
`@weiv/store` draft is retained as a candidate, not as a finalized commitment.
The proxy-backed state-graph direction is no longer design-only:

- tracked roots are now emitted for:
  - imported object roots
  - `props` object roots
  - a narrow local-object slice
- direct browser modules now emit tracked-state metadata and proxy-backed
  dirty-path runtime wiring
- `compile analyze component` now summarizes tracked roots, escape warnings,
  and rewrite guidance

What remains unsettled is the broader promotion policy and the long-term public
shared-state/runtime surface, not whether the proxy-state graph can work at
all.

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
- escaped state outside owned boundaries is still the main unresolved runtime
  precision problem; the current active direction is a narrow proxy-backed
  tracked state surface plus escape diagnostics and conservative fallback
- Binding-phase diagnostics now carry a formal `error` / `warning` / `info`
  severity model, and invalidation-graph diagnostics now surface `warning` /
  `info` levels in the inspect output while remaining inspect-only.
- `compile analyze component` now surfaces proxy-state tracked-root and
  escape-warning summaries, including rewrite guidance for current warning
  reasons.
- `weiv dev` now watches and rebuilds, defaults to an ephemeral preview
  port unless `PORT` is set, and debounces rebuilds after file changes, but
  the loop is still polling-based and needs polish around long-running process
  ergonomics.

## Current Health

The project is in a good checkpoint state:

- architecture direction is documented
- current implementation matches the direction
- proxy-state tracking is now real runtime/compiler behavior, not only a design note
- direct render verification is green
- TodoMVC remains a useful forcing-function example, but not a large flagship verification app
- stale-risk state patterns are becoming inspectable instead of magical
