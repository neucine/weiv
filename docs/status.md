# Weiv Status

## Current State

`weiv` is an early compiler-first frontend framework prototype with a working
direct-DOM browser path.

The current vocabulary for this architecture is documented in
[Terminology](./terminology.md).

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

The important caveat is that selective dirty-binding-to-region execution is not
fully implemented yet. The structure is present, but flushes still preserve
current behavior by routing through component update traversal.

## Invalidation Graph

`weiv dump-invalidation-graph <path>` reports:

- update regions
- visible dependencies
- mutation sites
- owned event boundaries
- hidden-state template call diagnostics
- expression-position mutation diagnostics
- unowned callback mutation diagnostics
- framework binding conflict diagnostics such as user-defined `emit`

This is the primary debugging surface for the compiler-native state model.

`weiv dump-state-plan <path>` remains available as a compatibility alias.

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

## Known Caveats

- `evaluate(...)` still exists in generated direct browser output.
- `emit` is reserved and injected, but event payload typing still depends on
  future IDE virtual declarations from `export interface Emits`.
- Region update functions exist, but dirty binding queues do not yet execute
  only the minimal affected region set.
- Local function dependency analysis is still shallow in `dump-invalidation-graph`.
- Alias analysis is intentionally limited.
- Arbitrary imported callback registration is not owned by the scheduler.
- `weiv dev` is still basic and needs watch/rebuild hardening.

## Current Health

The project is in a good checkpoint state:

- architecture direction is documented
- current implementation matches the direction
- direct render verification is green
- TodoMVC remains the main forcing-function example
- stale-risk state patterns are becoming inspectable instead of magical
