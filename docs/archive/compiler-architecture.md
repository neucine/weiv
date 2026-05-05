# Weiv Compiler Architecture

## Purpose

This document defines the initial architecture for the `weiv` compiler, runtime boundary, and CLI emission contract.

It is the implementation-facing companion to the framework spec and syntax decisions.

For the long-term browser execution model, see [Browser Codegen Direction](./browser-codegen.md).

## Decision Summary

The initial implementation should use this shape:

- input: `.weiv` single-file components
- output: JavaScript module plus CSS asset/module metadata
- integration model: `weiv` compiler emits artifacts, Bun handles serving and bundling
- systems interop model: Zig compiler core with Rust parser libraries accessed through FFI where needed
- compiler structure:
  - SFC parse
  - template parse
  - script analysis
  - binding
  - style scoping
  - IR generation
  - JS/CSS emission
- runtime model:
  - small DOM runtime
  - generated update plans
  - no public fine-grained reactivity primitives in the default path

## 1. Architectural Boundary

`weiv` is not the bundler.

The responsibilities are split like this:

### `weiv` owns

- `.weiv` parsing
- syntax validation
- template-to-script binding
- scoped CSS transforms
- framework diagnostics
- sourcemap generation
- JS module emission
- CSS emission
- runtime import wiring

### Bun owns

- TypeScript execution environment around the app
- dev server behavior
- watch orchestration if delegated there
- module graph loading
- bundling and output packaging
- browser asset serving

This keeps framework semantics independent from any one bundler.

## 2. Package Shape

Initial package split should be:

- `@weiv/compiler`
- `@weiv/runtime`
- `@weiv/cli`
- `libs/parser-backend` for Rust parser interop support

Optional later packages:

- `@weiv/ts`
- `@weiv/test`
- `@weiv/router`

## 2.1 Interop Boundary

The initial interop choice is FFI.

That means:

- Zig remains the owning compiler implementation
- parser libraries in Rust may be exposed through a narrow C ABI layer
- `weiv` should avoid subprocess-based parser orchestration for core compilation paths

Reason:

- lower process overhead
- direct data exchange for spans, AST fragments, and diagnostics
- clearer long-term architecture than shelling out during compilation

Constraint:

- keep the FFI surface narrow and phase-oriented
- do not expose large parser-internal ASTs blindly across the boundary
- prefer compact result structs or serialized intermediate records where ownership is explicit

Direction:

- use a Rust helper layer for parser-heavy tasks where ecosystem fit is materially better than Zig-native alternatives
- keep Zig as the owner of compiler orchestration and IR

## 3. Compiler Pipeline

The compiler should be explicit and phase-based.

### Phase A: SFC Parse

Input:

- raw `.weiv` source

Output:

- `SfcDocument`

Responsibilities:

- locate top-level sections
- validate required and duplicate sections
- preserve exact source spans

### Phase B: Template Parse

Input:

- template section source

Output:

- `TemplateAst`

Responsibilities:

- parse HTML-like nodes
- parse structural directives:
  - `if`
  - `else`
  - `for`
- parse interpolation nodes
- preserve spans for diagnostics and sourcemaps

### Phase C: Script Analysis

Input:

- TypeScript script section

Output:

- `ScriptModel`

Responsibilities:

- identify exported props declaration
- identify local bindings visible to the template
- classify functions, locals, and imports
- collect type information hooks for later diagnostics

The first version may use a limited AST walk rather than a full language-service implementation.

### Phase D: Binding

Input:

- `TemplateAst`
- `ScriptModel`

Output:

- `BoundTemplate`

Responsibilities:

- resolve template identifiers into script bindings
- validate event handlers
- validate supported directive forms
- emit source-located diagnostics for unresolved or invalid references

### Phase E: Style Scoping

Input:

- style section source
- component scope id

Output:

- `ScopedCssResult`

Responsibilities:

- rewrite selectors to component-scoped selectors
- preserve readable and deterministic output
- return mapping data for JS emission and debugging

### Phase F: IR Generation

Input:

- `BoundTemplate`

Output:

- `ComponentIr`

Responsibilities:

- lower template structure into an explicit render/update representation
- separate static DOM shape from dynamic bindings
- represent event attachment points
- represent conditional and list blocks

### Phase G: JS/CSS Emission

Input:

- `ComponentIr`
- `ScriptModel`
- `ScopedCssResult`

Output:

- compiled JS module
- CSS asset text or CSS module record
- sourcemaps

Responsibilities:

- emit component factory/module code
- connect compiled instructions to `@weiv/runtime`
- emit CSS in a Bun-consumable form
- preserve inspectability of generated output

## 4. Why Use An IR

The compiler should not lower directly from template AST to final JS strings.

An explicit IR is recommended because it:

- reduces churn when codegen changes
- makes DOM update planning inspectable
- keeps runtime assumptions visible
- supports better debugging and tests

The IR does not need to be overly abstract.
It only needs to be stable enough to separate template parsing from JS emission.

## 5. Output Module Contract

The first compiler target should be JS/CSS modules that Bun can consume directly.

### JS contract

Each compiled component module should export:

- a component definition object or factory
- metadata needed by the runtime
- an optional CSS reference or scope id

Conceptual example:

```ts
import { createComponent } from "@weiv/runtime";
import { css } from "./CounterCard.weiv.css";

export default createComponent({
  id: "CounterCard",
  css,
  setup(props) {
    let count = props.initialCount ?? 0;

    function increment() {
      count += 1;
    }

    return {
      state: { count },
      handlers: { increment },
      render: ...
    };
  }
});
```

This is illustrative, not locked syntax.
The real contract should optimize for generated clarity and runtime simplicity.

### CSS contract

The compiler may emit:

- a sibling CSS file, or
- CSS text attached through module metadata

Recommendation:

- emit sibling CSS artifacts plus scope metadata

Reason:

- simpler browser asset behavior
- easier inspection
- cleaner separation from JS runtime behavior

## 6. Runtime Contract

`@weiv/runtime` should remain intentionally small.

It should provide:

- component mounting
- DOM creation helpers or instruction executor
- event listener attachment/removal
- update scheduling
- component teardown

It should not provide:

- public state containers as the default authoring path
- a large reactive graph API
- framework-owned application state management

## 7. Reactivity Strategy

The preferred initial strategy is:

- compile mutable script bindings into tracked component-local update points
- generate update plans for template dependencies
- use runtime scheduling only to batch or coordinate DOM work

The runtime should not discover all dependencies dynamically by default.
The compiler should do as much dependency planning as practical.

## 8. CLI Contract

`@weiv/cli` should remain thin.

Initial commands:

- `weiv build`
- `weiv watch`

Optional later command:

- `weiv check`

### `weiv build`

Responsibilities:

- compile `.weiv` inputs into JS/CSS outputs
- print diagnostics
- write sourcemaps

### `weiv watch`

Responsibilities:

- watch `.weiv` inputs
- rebuild incrementally when possible
- print diagnostics on change

The CLI should not grow into a full dev server unless a clear need appears.

## 9. Sourcemap Expectations

Sourcemaps are required early, not as a late polish item.

The compiler should preserve source mapping for:

- template expressions
- event handler references
- script-originated generated code
- CSS selector rewrites where practical

## 10. Testing Strategy

The compiler architecture should support:

- fixture tests for SFC parsing
- AST snapshot tests
- binding diagnostics tests
- CSS scoping tests
- IR snapshot tests
- emission snapshot tests
- runtime integration tests using compiled fixtures

## 11. Implementation Order

Recommended implementation order:

1. define core data structures:
   - `SfcDocument`
   - `TemplateAst`
   - `ScriptModel`
   - `BoundTemplate`
   - `ComponentIr`
2. implement SFC parsing
3. implement template parsing
4. implement script analysis
5. implement binding diagnostics
6. implement CSS scoping
7. implement IR generation
8. emit JS/CSS modules
9. connect emitted output to the runtime
10. wrap the compiler in the CLI

## 12. Open But Non-Blocking Details

These details can remain open without blocking Phase 1:

- exact shape of generated component factory APIs
- whether CSS is emitted per file or aggregated later
- how much type metadata is preserved into emitted artifacts
- whether watch mode lives entirely in `weiv` or partly in Bun scripts

## 13. Decisions Locked By This Document

This document locks these choices for MVP:

- `weiv` emits modules, not bundles
- Bun is the surrounding toolchain, not the owner of framework semantics
- compiler phases are explicit
- an IR exists between parsing and codegen
- runtime remains small and DOM-focused
- CLI stays dependency-light and narrow
