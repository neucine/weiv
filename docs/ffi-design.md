# Weiv FFI Design

## Purpose

This document defines the intended FFI architecture for `weiv`.

The goal is to keep Zig as the owning compiler implementation while using a Rust helper layer for parser-heavy tasks where the best candidate libraries already exist in Rust.

## Decision Summary

`weiv` should use this split:

- Zig owns the compiler pipeline, IR, diagnostics assembly, and CLI
- Rust helper crates own parser-library integration where appropriate
- Zig and Rust communicate through a narrow FFI boundary
- Bun remains part of the surrounding toolchain, not the parser boundary

## Why This Split

The parser ecosystem is not evenly distributed.

Today the strongest candidates in scope are:

- `oxc` for TypeScript parsing and script analysis
- `lightningcss` for CSS parsing and selector-aware transforms
- possibly `html5ever` for template parsing if it survives evaluation

Those are Rust-native tools.
Trying to reproduce their capabilities directly in Zig would slow the project down and weaken the parser story.

## Ownership Model

### Zig owns

- `.weiv` SFC parsing
- compiler phase orchestration
- AST/IR ownership on the `weiv` side
- compiler diagnostics presentation
- JS/CSS emission coordination
- CLI commands
- project build integration

### Rust helper owns

- TypeScript parsing through `oxc`
- binding-oriented script extraction
- CSS parsing support when selector-aware logic is needed
- any parser-specific lowering that is too expensive or awkward to reimplement in Zig

## Package Layout

Recommended repo layout:

```text
libs/
  parser-backend/
    Cargo.toml
    src/
src/
  ffi/
  compiler/
  cli/
```

### Suggested names

- Zig side:
  - `src/ffi/parser_backend.zig`
- Rust side:
  - `libs/parser-backend`

The Rust crate should compile to a static library for Zig to link.

## ABI Strategy

The ABI should be:

- C ABI
- narrow
- phase-oriented
- explicit about memory ownership

Avoid:

- exporting large Rust-native AST structures directly
- depending on Rust layout details across the boundary
- broad “do everything” calls that hide compiler phases

Prefer:

- one function per bounded task
- explicit request/response contracts
- small stable records or serialized payloads

## Initial FFI Tasks

The first Rust helper tasks should be:

1. parse TypeScript script blocks with `oxc`
2. extract top-level bindings relevant to templates
3. report parse diagnostics with spans
4. optionally transpile or normalize TS when needed later
5. parse CSS selectors or stylesheets for scoped style rewriting

## Initial Function Shape

The first ABI does not need to be perfect.
It does need to be disciplined.

Recommended initial surface:

- `weiv_script_analyze`
- `weiv_css_scope`
- `weiv_backend_free`

Conceptual example:

```c
char* weiv_script_analyze(
  const char* source,
  const char* source_path
);

char* weiv_css_scope(
  const char* css_source,
  const char* component_scope_id,
  const char* source_path
);

void weiv_backend_free(char* ptr);
```

The returned payload may initially be JSON for speed of iteration.

## Payload Strategy

### Phase 1 recommendation

Use JSON payloads initially.

Reason:

- simplest to debug
- easiest to evolve while contracts are still moving
- already proven workable in `affon`

### Later optimization path

If JSON becomes too expensive or awkward:

- move hot paths to compact C structs
- or return length-delimited byte buffers with a stable schema

Do not optimize the transport format before the compiler contracts stabilize.

## Memory Ownership

The memory rules should be simple:

- Rust allocates returned payloads
- Zig copies the data it wants to keep
- Zig calls one Rust free function for the original payload

This mirrors the successful pattern already used in `affon`.

### Rules

- never let Zig free Rust-owned allocations directly
- never let Rust assume ownership of Zig-owned buffers unless explicitly documented
- duplicate into Zig-owned memory at the boundary when long-lived storage is needed

## Diagnostics Contract

The FFI boundary should return structured diagnostics, not plain text errors.

Minimum fields:

- severity
- message
- span start
- span end
- source path

Optional later fields:

- line and column
- error code
- hints

## Script Analysis Contract

For MVP, the Rust helper does not need to export a full `oxc` AST.

It should return only the data `weiv` needs:

- props declaration presence
- exported props type name
- top-level bindings visible to templates
- function declarations visible to templates
- imports relevant to component composition
- parse diagnostics

This keeps the ABI smaller and less coupled to `oxc` internals.

## CSS Contract

The CSS helper should return:

- scoped CSS output
- scope id or selector metadata
- diagnostics if parsing fails

It should not try to own high-level framework styling semantics.
It is a parser/transform helper, not a style system.

## Build Integration

The Zig build should treat the Rust helper as a first-class dependency.

Requirements:

- `zig build` should trigger the Rust helper build
- the output artifact path should be deterministic
- linking should not depend on manually prebuilt release artifacts

This is one place where `weiv` should improve on the current `affon` pattern.

## Relationship To Affon

`affon` already demonstrates:

- Zig calling Rust through FFI
- `oxc` as a Rust parser backend
- Rust-returned payloads copied into Zig-owned memory

`weiv` should reuse that pattern, but with a narrower, more compiler-oriented contract.

This also creates a path to align `affon` later on a cleaner shared architecture:

- Zig core
- Rust parser backend helpers
- narrow ABI

## Non-Goals

This FFI layer should not become:

- a general plugin system
- a giant cross-language object model
- a place to hide core compiler logic that belongs in Zig

The Rust helper exists to bridge parser ecosystems, not to replace the compiler.

## Immediate Next Step

Before implementation starts, add one more design artifact:

- a backend API contract doc that defines the JSON schema or struct schema for `weiv_script_analyze`

That will be enough to begin the script-analysis portion of Phase 1 cleanly.

Status:

- script-analysis backend API contract: created
