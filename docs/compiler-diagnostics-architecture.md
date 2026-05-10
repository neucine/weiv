# Compiler Diagnostics Architecture

## Purpose

This document defines the next diagnostics architecture for `weiv`.

The goal is to move from the current mixed model:

- some phases emit structured diagnostics
- other phases throw the first compiler error and stop

to one compiler-owned diagnostic pipeline that can be reused by:

- CLI output
- `weiv dev` rebuild reporting
- future VS Code syntax highlighting and language server features
- future machine-readable analysis commands

This is an architecture document, not an implementation diff.

## Current Problem

Today the compiler has two different error models.

Structured diagnostics already exist for:

- Rust-backed script analysis
- binding analysis
- parts of invalidation-graph reporting

But several author-facing failures still escape as first-stop Zig errors:

- SFC parse failures
- template parse failures
- template normalization failures
- some emit/build failures such as unsupported import forms

In practice this means:

- one author mistake can stop compilation before later diagnostics are collected
- CLI formatting logic has to reconstruct user-facing location hints from thrown errors
- `weiv dev` rebuilds can preserve the last good output, but the error path is still exception-first
- future IDE tooling would need to duplicate compiler knowledge or scrape CLI output

That is the wrong long-term boundary.

Author mistakes should primarily become structured diagnostics.
Thrown Zig errors should be reserved for infrastructure failures or internal invariants.

## Goals

The new model should guarantee:

1. One canonical diagnostic structure across compiler phases.
2. Stable diagnostic codes and severities.
3. Source locations suitable for CLI and LSP reuse.
4. Multiple diagnostics can be collected in one compile when recovery is possible.
5. Fatal author errors stop dependent later phases, but do not erase earlier diagnostics.
6. CLI formatting is a presentation layer, not the source of truth.
7. Future IDE tooling can consume the same diagnostics directly.

## Non-Goals

This design does not require:

- full parser recovery in every phase immediately
- continuing all later phases after a malformed template or malformed SFC
- replacing every thrown error in one pass
- defining full LSP server behavior now

The first win is:

- collect diagnostics structurally
- stop only where the pipeline no longer has enough valid input
- keep the reporting contract reusable

## Design Principle

The compiler should separate:

- **author diagnostics**
- **infrastructure failures**

Author diagnostics are things like:

- missing `<template>`
- invalid section order
- unexpected `else`
- framework binding conflicts
- unowned callback mutation warnings
- unsupported import forms in author code

Infrastructure failures are things like:

- out of memory
- file read failure
- backend crash / malformed backend response
- impossible internal invariant

Rule:

- author diagnostics become data
- infrastructure failures remain thrown errors

## Canonical Diagnostic Model

The compiler should own one canonical diagnostic type in a shared module, likely
something like:

- `src/compiler/diagnostics.zig`

Suggested shape:

```zig
pub const Severity = enum {
    error,
    warning,
    info,
};

pub const Stage = enum {
    sfc_parse,
    template_parse,
    template_normalize,
    script_analysis,
    binding,
    lowering,
    browser_plan,
    emit,
    bundle,
};

pub const Span = struct {
    start: usize,
    end: usize,
};

pub const SourceLocation = struct {
    line: u32,
    column: u32,
    end_line: u32,
    end_column: u32,
};

pub const RelatedSpan = struct {
    source_path: []const u8,
    span: Span,
    message: []const u8,
};

pub const Diagnostic = struct {
    code: []const u8,
    severity: Severity,
    message: []const u8,
    stage: Stage,
    source_path: []const u8,
    span: ?Span,
    location: ?SourceLocation,
    fatal: bool,
    notes: [][]const u8,
    related: []RelatedSpan,
};
```

Not every field needs to be populated immediately.

The important part is that the canonical structure already has room for:

- stable codes
- phase identity
- source spans
- human message
- machine-readable severity
- future related-location diagnostics

## Severity And Fatality

Severity and fatality are related, but not identical.

Suggested rule:

- `error` usually means `fatal = true`
- `warning` means `fatal = false`
- `info` means `fatal = false`

But the model should keep them separate.

Reason:

- a future phase may want to emit an `error` diagnostic while still allowing
  some non-dependent reporting to continue
- IDE tooling cares about severity
- pipeline control cares about fatality

So the compiler should never infer pipeline flow only from severity.

## Diagnostic Bag

Every compile path should accumulate into a `DiagnosticBag`.

Suggested responsibilities:

- append diagnostics
- expose `hasFatal()`
- expose `hasErrors()`
- own memory for diagnostics
- allow merge from subphases

Conceptually:

```zig
pub const DiagnosticBag = struct {
    diagnostics: std.ArrayList(Diagnostic),

    pub fn add(...) !void { ... }
    pub fn extend(...) !void { ... }
    pub fn hasFatal(self: *const DiagnosticBag) bool { ... }
    pub fn hasSeverity(self: *const DiagnosticBag, severity: Severity) bool { ... }
};
```

This becomes the compiler-owned collection surface used everywhere.

## Phase Results And Partial Progress

The current `ComponentModel` only represents a fully successful build.

That is too narrow for good diagnostics.

The new build pipeline should return a richer report object that can contain:

- diagnostics
- partial successful phase outputs
- knowledge of where the pipeline stopped

Suggested shape:

```zig
pub const ComponentBuildReport = struct {
    source_path: []const u8,
    diagnostics: []Diagnostic,

    sfc_document: ?sfc.Document,
    template_document: ?template.Document,
    normalized_template: ?template.NormalizedDocument,
    script: ?script_analysis.ScriptAnalysis,
    binding_result: ?binding.BindingResult,
    ir_document: ?ir.Document,

    halted_after: ?Stage,
};
```

This makes the recovery rule explicit:

- a phase runs only if its prerequisites exist
- diagnostics are preserved even if later phases do not run
- CLI and IDE tooling can inspect partial progress consistently

This report should eventually become the main output of component compilation.

The existing fully successful `ComponentModel` can remain as:

- a convenience success projection
- or a later thin wrapper around a completed `ComponentBuildReport`

## Recovery Model

The recovery model should be phase-bounded.

That means:

- a phase should try to collect more than one diagnostic when that is realistic
- but it should not pretend to recover beyond what the current parser/lowerer can support safely

Suggested phase behavior:

### SFC Parse

Collect where possible:

- duplicate sections
- invalid section order
- missing required sections
- invalid script attributes

If the SFC cannot be structurally understood enough to identify template/script
spans, stop after SFC parse with fatal diagnostics.

### Template Parse / Normalize

Collect where possible:

- unexpected close tag
- mismatched close tag
- invalid slot outlet
- invalid slot placement
- invalid grouped slot template placement
- unexpected `else`

If the template AST is too malformed to normalize safely, stop before later
template-dependent phases.

### Script Analysis

Continue using structured backend diagnostics.

If the backend fails operationally:

- treat that as an infrastructure failure
- not an author diagnostic

If the backend returns author diagnostics but still returns partial analysis:

- keep those diagnostics
- allow later phases only if the returned analysis is declared valid enough

### Binding / Lowering

Binding already has a good shape for structured diagnostics.

Lowering should eventually follow the same rule:

- expected author-visible unsupported patterns become diagnostics
- impossible IR invariants remain thrown internal errors

### Emission / Bundling

Several current emit-time failures are really author diagnostics, for example:

- unsupported runtime import forms

These should become structured diagnostics attached to the relevant source file
and import span rather than only thrown emit errors.

## CLI Contract

The CLI should stop owning diagnostic truth.

Instead, CLI should:

1. request a compiler report
2. inspect the canonical diagnostics
3. format them for the terminal
4. decide exit status from `hasFatal()`

This removes the need for ad hoc per-error formatting logic like:

- `friendlyErrorName(err)`
- special hint branches by thrown error name
- reconstructing spans after the fact whenever possible

Those can become presentation helpers over structured diagnostics instead.

## `weiv dev` Contract

`weiv dev` becomes much cleaner with this model.

Desired behavior:

- rebuild requests compile into a `BuildReport`
- if `hasFatal()` is false, emit new output
- if `hasFatal()` is true, preserve the last good output
- always print the full current diagnostic set

This also gives a future path for:

- browser overlay diagnostics
- editor-integrated watch diagnostics
- structured rebuild result streaming

## IDE / LSP Reuse

This architecture is specifically designed to be reusable in a future VS Code
extension and language server.

The compiler should be the authority on:

- diagnostic code
- severity
- primary span
- related spans
- message
- stage

The language server layer should only need to:

- request diagnostics for a file
- map them into LSP diagnostics
- map `Severity` to LSP severity
- optionally expose `code` and related info

That means the IDE should not have to:

- re-run custom regexes
- scrape CLI text
- re-derive template/binding state warnings on its own

The compiler remains the source of truth.

## Stable Codes

Every user-facing diagnostic should have a stable code string.

Examples:

- `sfc.missing_template`
- `sfc.duplicate_script`
- `template.unexpected_else`
- `template.invalid_slot_placement`
- `framework.reserved_binding`
- `callback.unowned_mutation`
- `alias.mutation`
- `import.unsupported_runtime_import`

Messages may be refined over time.
Codes should be stable enough that:

- tests can assert them
- IDE tooling can key off them
- future docs can reference them

This also makes diagnostic localization or richer help possible later.

## Notes And Related Locations

The model should support secondary notes early, even if only lightly used at first.

Examples where this helps:

- duplicate section diagnostics
- duplicate slot outlet diagnostics
- future cross-component composition diagnostics
- future “imported here, used here” messages

So the architecture should plan for:

- one primary span
- zero or more secondary related spans
- optional human notes

This keeps the model future-friendly without forcing full adoption immediately.

## JSON Shape For Tooling

Even if the first implementation stays in-process, the diagnostics model should
be serializable cleanly.

Suggested eventual JSON shape:

```json
{
  "diagnostics": [
    {
      "code": "template.unexpected_else",
      "severity": "error",
      "stage": "template_normalize",
      "message": "`else` must immediately follow a sibling element with `if`",
      "sourcePath": "src/App.weiv",
      "span": { "start": 118, "end": 122 },
      "location": { "line": 12, "column": 3, "endLine": 12, "endColumn": 7 },
      "fatal": true,
      "notes": [],
      "related": []
    }
  ]
}
```

This gives a clean future path for:

- `weiv compile analyze component --json`
- language-server bridges
- editor integration tests

## Migration Strategy

The rollout should be phased.

### Phase 1: Shared Diagnostic Core

Create:

- canonical `Diagnostic`
- `Severity`
- `Stage`
- `DiagnosticBag`

Do not change every phase at once.

### Phase 2: Adapt Existing Structured Diagnostics

Move existing structured producers onto the shared type:

- script analysis diagnostics
- binding diagnostics
- invalidation-graph diagnostics where appropriate

This reduces type duplication first.

### Phase 3: Parse And Normalize Diagnostics

Convert current thrown author errors in:

- SFC parse
- template parse
- template normalize

into structured diagnostics where practical.

Recovery can still be phase-bounded.

### Phase 4: Build Report

Replace `build(...) !ComponentModel` with a richer report path.

Keep a success-only convenience path if needed for callers that truly require a
completed model.

### Phase 5: CLI Rewire

Make CLI consume build reports and diagnostic formatting helpers rather than
hard-coded thrown-error special cases.

### Phase 6: Emit / Bundle Diagnostics

Move author-visible emit/bundle stops such as unsupported import forms into the
same diagnostic system.

### Phase 7: IDE / JSON Surface

Once the compiler contract is stable:

- add JSON diagnostic output
- add LSP mapping in future tooling

## Expected First Slice

The first implementation slice should be intentionally narrow.

Recommended first slice:

1. Add shared diagnostic types and bag.
2. Unify script diagnostics and binding diagnostics onto the shared type.
3. Add a `ComponentBuildReport`.
4. Convert SFC and template structural author errors into report diagnostics.
5. Make `compile analyze component` print from the report, not from mixed
   exception formatting.

That gives immediate value without forcing full emitter conversion.

## Open Questions

These do not block the architecture, but should be answered during implementation:

1. Should `location` be eagerly computed for every diagnostic, or lazily derived
   from `source_path + span` during formatting?

Recommendation:

- keep `span` canonical
- compute line/column lazily where practical

2. Should one report type serve both successful and partial builds, or should
   there also be a smaller `AnalysisReport`?

Recommendation:

- start with one component build report
- avoid parallel report types too early

3. Should invalidation-graph warnings be stored in the same report or only
   derived later?

Recommendation:

- move toward the same diagnostic type
- but it is acceptable if some inspect-only diagnostics remain derived in an
  intermediate step

4. Should CLI exit code be based only on `fatal`, or also on any `error`
   severity?

Recommendation:

- base it on `fatal`
- preserve the distinction intentionally

## Recommended Direction

The compiler should become diagnostics-first, not exception-first.

That means:

- author problems are collected as structured diagnostics
- later dependent phases stop only when inputs are no longer valid enough
- CLI is only a renderer
- IDE tooling reuses the same diagnostics directly

This is the right foundation for:

- better compile output
- better `weiv dev`
- future VS Code extension work
- future language server work

