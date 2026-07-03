# Compiler Structure

The compiler is organized as explicit stages. Each stage owns the representation
it produces, following the same broad shape as the sibling Cyna compiler:

```text
source .weiv
  -> parser: SFC document + template AST
  -> sema: ScriptFacts + TemplateBindings + SIR
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
  into `TemplateBindings`, and exposes all SIR model types from `sema/sir.zig`.
  Script parsing is delegated through the FFI script backend; semantic model
  names should use `ScriptFacts`, not the older "script analysis" wording.
- `lower/` converts semantic/template data into LIR types in `lower/lir.zig`.
- `component_unit.zig` owns `ComponentUnit` and `ComponentCompileReport`, the
  target-neutral bundle of phase outputs for one component. Target-neutral
  compilation stops here.
- `backend/browser/render_tree/` lowers a `ComponentUnit` into a browser
  `RenderTree`. This is the browser backend representation, not a complete
  JavaScript module by itself.
- `backend/browser/component.zig` owns `BrowserComponent`, the browser-specific
  container that combines the render tree with the other facts required by
  browser emitters.
- `backend/browser/emit/` owns browser output. `js_module/` emits component JS,
  `css_scoped/` emits scoped CSS, and `app/` builds whole app bundles. App
  bundles additionally use an app graph to collect component and runtime
  dependencies.
- `compile.zig` is the compile-unit coordinator for one `.weiv` component. It
  orchestrates stages but does not own AST, SIR, LIR, render-tree, or emit
  rules.
- `inspect/` formats stage representations and derived debug views for CLI
  `emit` output. It is a formatter layer, not a compiler stage.
- `diagnostics.zig` contains shared diagnostic types and formatting helpers.

Keep new compiler code inside the phase that owns the data it creates. One-file
component orchestration belongs in `compile.zig`; target-specific output belongs
under `backend/<target>/`; representation formatters belong in `inspect/`. If
code does not clearly belong to a phase, target, compile-unit coordinator, or
formatter, keep it at the top level of `compiler/`.

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
