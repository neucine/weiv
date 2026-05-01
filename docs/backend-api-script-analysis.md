# Weiv Backend API: Script Analysis

## Purpose

This document defines the initial backend contract for script analysis performed by the Rust helper layer.

It covers the first high-value FFI entrypoint:

- `weiv_script_analyze`

The purpose of this API is to give the Zig compiler the binding-oriented information it needs from a `<script lang="ts">` block without exposing a full Rust-native `oxc` AST across the FFI boundary.

## Scope

This API is responsible for:

- parsing TypeScript script content
- reporting parse diagnostics
- extracting props-related declarations
- extracting top-level bindings relevant to templates
- extracting imports relevant to component composition

This API is not responsible for:

- full TypeScript type-checking
- template parsing
- template-to-script binding
- JS code generation
- runtime behavior

## FFI Function Shape

Initial C ABI:

```c
char* weiv_script_analyze(
  const char* source,
  const char* source_path
);

void weiv_backend_free(char* ptr);
```

### Arguments

- `source`: UTF-8 script source from `<script lang="ts">`
- `source_path`: logical file path used for diagnostics and sourcemap identity

### Return

- success or failure payload encoded as JSON
- `null` only for unrecoverable backend-level failure such as invalid FFI input or allocation failure

## Transport Format

The transport format for Phase 1 is JSON.

Reason:

- easy to inspect
- easy to evolve while the compiler contract is still moving
- already consistent with the `affon` interop precedent

## Top-Level JSON Shape

The Rust helper should always try to return a valid JSON object when parsing was attempted.

Initial schema:

```json
{
  "ok": true,
  "source_path": "src/components/Counter.weiv::<script>",
  "props": {
    "has_props_export": true,
    "props_binding_name": "props",
    "props_type_name": "Props"
  },
  "imports": [],
  "bindings": [],
  "diagnostics": []
}
```

If parsing fails in a normal compiler sense:

```json
{
  "ok": false,
  "source_path": "src/components/Counter.weiv::<script>",
  "props": null,
  "imports": [],
  "bindings": [],
  "diagnostics": [
    {
      "severity": "error",
      "message": "Unexpected token",
      "span_start": 18,
      "span_end": 19,
      "line": 2,
      "column": 7
    }
  ]
}
```

## Response Fields

### `ok`

Type:

- `boolean`

Meaning:

- `true` when the script parsed successfully enough to produce binding data
- `false` when parse diagnostics prevent trusted script-model extraction

### `source_path`

Type:

- `string`

Meaning:

- the logical path identity for diagnostics

### `props`

Type:

- object or `null`

Shape:

```json
{
  "has_props_export": true,
  "props_binding_name": "props",
  "props_type_name": "Props"
}
```

Rules:

- `has_props_export` indicates whether `export let props: Props` was found
- `props_binding_name` should normally be `"props"` in MVP
- `props_type_name` should be the identifier name of the annotation when present
- if props export is missing or malformed, this object may still be returned with partial data plus diagnostics

### `imports`

Type:

- array of import records

Shape:

```json
{
  "source": "./MetricBadge.weiv",
  "kind": "default",
  "imported_name": null,
  "local_name": "MetricBadge",
  "span_start": 0,
  "span_end": 38
}
```

Fields:

- `source`: module specifier
- `kind`: one of:
  - `default`
  - `named`
  - `namespace`
  - `side_effect`
- `imported_name`: original imported symbol for named imports, otherwise `null`
- `local_name`: local binding name, or empty string for side-effect imports
- `span_start`
- `span_end`

Purpose:

- enables component-resolution preparation
- enables diagnostics for missing imported component bindings later in the pipeline

### `bindings`

Type:

- array of binding records

This is the core script-model payload.

Shape:

```json
{
  "name": "count",
  "kind": "mutable",
  "exported": false,
  "template_visible": true,
  "callable": false,
  "type_annotation": null,
  "span_start": 74,
  "span_end": 106
}
```

Fields:

- `name`: binding identifier
- `kind`: one of:
  - `mutable`
  - `immutable`
  - `function`
  - `import`
  - `type_only`
- `exported`: whether this binding is exported
- `template_visible`: whether the binding should be considered available to the template
- `callable`: whether the binding may be called from template expressions
- `type_annotation`: textual type annotation if cheaply available, otherwise `null`
- `span_start`
- `span_end`

### `diagnostics`

Type:

- array of diagnostic records

Shape:

```json
{
  "severity": "error",
  "message": "Expected identifier",
  "span_start": 45,
  "span_end": 46,
  "line": 3,
  "column": 12,
  "code": null
}
```

Fields:

- `severity`: `error` or `warning`
- `message`
- `span_start`
- `span_end`
- `line`
- `column`
- `code`: optional backend-specific code

## Binding Extraction Rules

The initial extraction rules should be intentionally narrow and predictable.

### Include in `bindings`

- top-level `let`
- top-level `const`
- top-level `function`
- imported value bindings
- `export let props`

### Exclude from `bindings`

- nested function-local variables
- interface members
- type aliases unless explicitly needed later
- enum members unless explicitly needed later

### `template_visible`

Set `template_visible` to `true` for:

- top-level value bindings
- imported component/value bindings
- top-level functions
- `props`

Set `template_visible` to `false` for:

- type-only declarations
- internal-only constructs not accessible in template expression context

### `callable`

Set `callable` to `true` for:

- function declarations
- imported bindings only if confidently known callable is not required in MVP

Recommendation:

- in MVP, mark only explicit function declarations as callable
- do not try to infer callable imported values yet

## Props Extraction Rules

The helper should look specifically for the MVP props shape:

```ts
export let props: Props;
```

It should return:

- whether it exists
- the binding name
- the annotation identifier name if present

Diagnostics should be emitted if:

- there is no exported `props` binding
- `props` exists but has no type annotation
- the props export shape is unsupported

The helper should not reject the entire script solely because props are malformed.
That is a compiler diagnostic, not necessarily a parser failure.

## Error Handling Rules

### Return `null` only when

- input pointers are invalid
- UTF-8 decoding fails before parsing can begin
- allocation fails
- a backend panic boundary is converted into a hard failure

### Return JSON with `ok: false` when

- the script contains parse errors
- parsing ran but reliable binding extraction could not complete

This distinction is important:

- `null` means backend invocation failure
- `ok: false` means normal compiler-facing parse failure

## Example Success Payload

For this script:

```ts
import MetricBadge from "./MetricBadge.weiv";

export interface Props {
  title: string;
}

export let props: Props;

let count = 0;
const limit = 10;

function increment() {
  count += 1;
}
```

Expected conceptual result:

```json
{
  "ok": true,
  "source_path": "examples/basic-counter.weiv::<script>",
  "props": {
    "has_props_export": true,
    "props_binding_name": "props",
    "props_type_name": "Props"
  },
  "imports": [
    {
      "source": "./MetricBadge.weiv",
      "kind": "default",
      "imported_name": null,
      "local_name": "MetricBadge",
      "span_start": 0,
      "span_end": 39
    }
  ],
  "bindings": [
    {
      "name": "MetricBadge",
      "kind": "import",
      "exported": false,
      "template_visible": true,
      "callable": false,
      "type_annotation": null,
      "span_start": 0,
      "span_end": 39
    },
    {
      "name": "props",
      "kind": "mutable",
      "exported": true,
      "template_visible": true,
      "callable": false,
      "type_annotation": "Props",
      "span_start": 74,
      "span_end": 98
    },
    {
      "name": "count",
      "kind": "mutable",
      "exported": false,
      "template_visible": true,
      "callable": false,
      "type_annotation": null,
      "span_start": 100,
      "span_end": 114
    },
    {
      "name": "limit",
      "kind": "immutable",
      "exported": false,
      "template_visible": true,
      "callable": false,
      "type_annotation": null,
      "span_start": 116,
      "span_end": 133
    },
    {
      "name": "increment",
      "kind": "function",
      "exported": false,
      "template_visible": true,
      "callable": true,
      "type_annotation": null,
      "span_start": 135,
      "span_end": 177
    }
  ],
  "diagnostics": []
}
```

## Zig-Side Expectations

The Zig wrapper should:

- call `weiv_script_analyze`
- treat `null` as backend failure
- parse returned JSON into Zig-owned structs
- copy any long-lived slices into Zig-owned memory
- call `weiv_backend_free` on the original payload

The Zig compiler should not depend on field order in the JSON.

## Evolution Rules

This contract may expand, but should stay stable in spirit:

- do not expose raw `oxc` AST internals
- only add fields that clearly help downstream compiler phases
- preserve backward compatibility where possible while Phase 1 is active

## Immediate Implementation Target

Once this contract is accepted, the next implementation work can start with:

1. `libs/parser-backend` Rust crate scaffold
2. `weiv_script_analyze` Rust implementation using `oxc`
3. `src/ffi/parser_backend.zig` wrapper
4. fixture tests using the canonical example scripts
