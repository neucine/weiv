# Classic Todo App

This example exists to verify the current `weiv` compiler/runtime pipeline
against a realistic but still compact multi-component app shape.

Components:

- `App.weiv`
- `TodoList.weiv`
- `TodoItem.weiv`

Current verification scope:

- SFC parsing
- template parsing
- directive parsing
- control-flow normalization
- Rust-backed script analysis
- binding and component-reference resolution
- direct browser module emission
- app bundle emission
- scoped CSS aggregation

Compared with `test/examples/todomvc`, this fixture is smaller and easier to reason
about, so it still earns its place as a regression example even though TodoMVC
is the stronger end-to-end app check.
