# Classic Todo App

This example exists to verify the current `weiv` compiler pipeline against a realistic multi-component app shape.

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
