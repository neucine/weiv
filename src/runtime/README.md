# Runtime Observable Contract

This folder holds the standalone shared observable runtime that Weiv plans to
integrate later for cross-component/shared state.

Current public package surface:

- `observable(value)`

Internal runtime helpers still exist in [observable.ts](/Users/chao.yang/Private/weiv/src/runtime/observable.ts):

- `subscribe(observableValue, listener)`
- `snapshot(observableValue)`
- `isObservable(value)`
- `observableBrandSymbol()`

Current semantics:

- `observable()` returns a proxy-backed tracked object
- nested objects are wrapped lazily on read
- repeated reads return stable nested proxy identities
- sync writes are batched into one microtask notification wave
- nested writes notify both the nested node and its parent chain
- replacing or deleting a nested object detaches the old child from the former
  parent chain
- `snapshot()` returns a frozen plain-object view detached from later writes

Weiv component integration currently relies on the observable brand and metadata
contract directly rather than importing these helper wrappers from
`@weiv/runtime`.

This runtime is intentionally being stabilized before Weiv component integration.
When in doubt about desirable semantics, use Valtio as a reference point for
ideas, but do not copy its implementation directly.
