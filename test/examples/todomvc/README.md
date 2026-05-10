# TodoMVC Verification Example

This example is the primary end-to-end verification fixture for `weiv`.

It is adapted from the trimmed TodoMVC benchmark app at:

- https://github.com/chaoyangnz/weiv-todomvc

The port keeps the important framework exercise points:

- multi-component composition
- root-owned mutable state
- child event emission
- create, toggle, edit, delete, filter, toggle-all, and clear-completed flows
- scoped styles across a larger component tree
- direct browser mounting and selective patching
- app bundle generation and preview bootstrapping

Unlike the benchmark source, this version is shaped around the current `weiv`
runtime model rather than older render-runtime assumptions, store decorators,
or class-component semantics.
