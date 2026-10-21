# Compiler Structure

The compiler is organized as explicit stages. Each stage owns the representation
it produces, following the same broad shape as the sibling Cyna compiler:

```text
source .weiv
  -> parser: SFC document + template AST
  -> sema: SIR (ScriptFacts + TemplateBindings)
  -> lower: LIR
  -> ComponentUnit
  -> backend/browser: RenderTree + BrowserComponent
  -> browser emit: JavaScript, scoped CSS, app bundles
```

## Stage Ownership

- `parser/` reads `.weiv` single-file components into the parser document model.
  The document has template, script, and style sections. Template syntax is
  parsed into the template AST in `parser/ast.zig`; script and style remain raw
  section text at this layer so the parser owns structure, not TypeScript or CSS
  semantics.
- `sema/` turns raw script text into `ScriptFacts`, binds template references
  into `TemplateBindings`, and exposes those SIR model types from `sema/sir.zig`.
  Script parsing is delegated through the FFI script backend; semantic model
  names should use `ScriptFacts`, not the older "script analysis" wording.
- `lower/` converts semantic/template data into LIR types in `lower/lir.zig`.
- `component_unit.zig` owns `ComponentUnit` and `ComponentCompileReport`, the
  target-neutral bundle of phase outputs for one component. Target-neutral
  compilation stops here. `ComponentCompileReport.takeUnit` transfers a
  complete unit and clears the report's ownership of its phase outputs.
- `backend/browser/render_tree/` lowers a `ComponentUnit` into a browser
  `RenderTree`. This is the browser backend representation, not a complete
  JavaScript module by itself.
- `backend/browser/component.zig` owns `BrowserComponent`, the browser-specific
  lowering result. It holds the `ComponentUnit` reference and render tree;
  generated source and CSS belong to emitters.
- `backend/browser/emit/` owns browser output. `js_module/` emits component JS,
  `scoped_css.zig` emits scoped CSS, and `app/` builds whole app bundles.
  `app/graph.zig` owns `BundleGraph` collection and module copying;
  `app/bundle_outputs.zig` emits the app entry and preview files;
  `app/runtime_imports.zig` classifies and rewrites runtime module imports;
  `app/preview_props.zig`
  infers demo props from the declared interface.
- `backend/browser/emit/js_module/` separates script setup, static runtime
  prelude, expression and component binding emission, structural helper
  emission, DOM creation, DOM updates, DOM destruction, and slot emission.
  `tracked_metadata.zig` serializes graph metadata into the generated module.
- `backend/browser/tracked_roots.zig` classifies browser-trackable bindings;
  `tracked_paths.zig` owns path discovery and ID assignment. Browser emission
  and graph inspection use the same table. These browser-specific files do
  not belong to target-neutral `sema/`.
- `backend/browser/dependencies.zig` analyzes the static dependencies used by
  runtime update guards. `backend/browser/region_graph.zig` combines these
  dependencies with tracked paths and owns runtime region IDs. Build this graph
  once per browser module, then pass it to the metadata and DOM emitters.
- `compile.zig` is the compile-unit coordinator for one `.weiv` component. It
  orchestrates stages but does not own AST, SIR, LIR, render-tree, or emit
  rules.
- `inspect/` formats stage representations and derived debug views for CLI
  `emit` output. Its invalidation view uses the browser region graph, path
  table, and dependency analyzer. It adds explanatory nodes and warnings but
  does not assign a second set of path IDs. It is a formatter layer, not a
  compiler stage.
- `diagnostics.zig` contains shared diagnostic types and formatting helpers.

Keep new compiler code inside the phase that owns the data it creates. One-file
component orchestration belongs in `compile.zig`; target-specific output belongs
under `backend/<target>/`; representation formatters belong in `inspect/`. If
code does not clearly belong to a phase, target, compile-unit coordinator, or
formatter, keep it at the top level of `compiler/`.

## Reactivity Ownership

- `sema/` identifies script bindings, template references, mutations, and
  callback ownership. It reports cases that cannot be tracked precisely.
  External registrations are unowned unless their mutation is enclosed in
  the component-provided `weivUpdate` boundary.
- `lower/` preserves those decisions in target-neutral nodes and effects.
- `backend/browser/` decides which DOM regions depend on those values and
  emits their update operations. Browser-specific proxy and scheduler code
  belongs here, not in semantic analysis. The browser setup supplies
  `weivUpdate` as a component-scoped function for external callbacks.
- `packages/weiv/src/runtime/observable.ts` provides explicitly shared state.
  Its public `observable` and `subscribe` API is separate from compiler-owned
  local state tracking. Generated browser modules bridge imported observables
  into selective updates by their imported binding names. Aliases of the same
  observable share one listener and invalidate each matching binding name.
- `inspect/invalidation_graph.zig` explains the analyzed graph. Its
  `runtime-regions` section reads the same browser graph as code generation.
  Its existing `regions` section also displays nested explanatory nodes that
  are not independent runtime update regions. Keep that distinction explicit.

Imported observable notifications include changed property paths. Direct member
expressions such as `shared.count` use those paths to select individual regions.
Expressions involving calls or operators keep the imported-binding fallback.
Compiler-tracked local paths also select individual nested paths.

## CLI Stage Output

The CLI can emit major stage representations to stdout or to an optional file:

```bash
weiv emit ast <path> [out-file]
weiv emit sir <path> [out-file]
weiv emit lir <path> [out-file]
weiv emit render-tree <path> [out-file]
weiv emit invalidation-graph <path> [out-file]
weiv emit js <path> [out-file]
weiv emit css <path> [out-file]
```

Use `compile` for a whole app bundle:

```bash
weiv compile <root.weiv> [out-dir]
```

The default app output directory is `dist`.

## Naming Rules

- Use `parser`, `sema`, `lower`, and `backend` for compiler stage names.
- Use `SFC document`, `template AST`, `ScriptFacts`, `TemplateBindings`, `SIR`,
  `LIR`, `ComponentUnit`, `RenderTree`, and `BrowserComponent` for the major
  representations.
- Prefer `render-tree` over the older `browser-plan` wording.
- Prefer `lir` over the older generic `ir` wording.
- Prefer `script_backend` for the Zig FFI wrapper. The native Rust library is
  still named `weiv_parser_backend` until the Rust crate is renamed separately.
- Use `BundleGraph` for the app module graph. Its nodes are components; it
  also tracks runtime imports copied into the bundle. Use
  `region_graph.Graph` for DOM update regions. `tracked_metadata` names
  serialization; it does not build the graph.
- A `BrowserComponent` is a lowered browser component, not an emitted module.
  Keep source strings and CSS out of that struct.
- SIR is the semantic pair of `ScriptFacts` and `TemplateBindings`. There is no
  separate `SirDocument` allocation or ownership layer.
