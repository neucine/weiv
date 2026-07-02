# Compiler Structure

The compiler is organized by phase. Each core phase owns the representation it
produces, following the same broad shape as the sibling Cyna compiler:

- `parser/` reads `.weiv` single-file components and template syntax into AST
  types in `parser/ast.zig`.
- `sema/` turns raw script text into `ScriptFacts`, binds template references
  into `TemplateBindings`, and exposes all SIR model types from `sema/sir.zig`.
- `lower/` converts SIR/template data into LIR types in `lower/lir.zig`.
- `backend/` turns a `ComponentUnit` into target-specific representations and
  output. Today this is the browser backend: `backend/browser/render_tree/`
  lowers LIR to a browser render tree, `backend/browser/component.zig`
  aggregates browser-specific component facts, and `backend/browser/emit/`
  emits JavaScript, scoped CSS, and app bundles from browser representations.
- `compile.zig` is the compile-unit coordinator for one `.weiv` component. It
  orchestrates phases but does not own AST/SIR/LIR/backend rules.
- `component_unit.zig` owns `ComponentUnit` and `ComponentCompileReport`, the
  retained bundle of phase outputs for one component.
- `inspect/` formats derived compiler views used by CLI inspection commands.
- `diagnostics.zig` contains shared diagnostic types and formatting helpers.

Keep new compiler code inside the phase that owns the data it creates. One-file
component orchestration belongs in `compile.zig`; target-specific output belongs
under `backend/<target>/`; CLI-only derived views belong in `inspect/`. If code
does not clearly belong to a phase, target, compile-unit coordinator, or
inspection view, keep it at the top level of `compiler/`.

Target-neutral compilation stops at `ComponentUnit`. Backend-specific
representations, such as the browser `RenderTree` and `BrowserComponent`, stay
under `backend/<target>/` so future targets can build their own representations
from the same LIR.

The CLI can emit the major stage representations to files for debugging:

- `weiv compile emit ast <path> <out-file>`
- `weiv compile emit sir <path> <out-file>`
- `weiv compile emit lir <path> <out-file>`
- `weiv compile emit render-tree <path> <out-file>`
