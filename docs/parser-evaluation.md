# Weiv Parser Evaluation

## Purpose

This document defines the candidate parser libraries to evaluate before Phase 1 implementation begins.

The intent is to prefer focused parser libraries first, and only hand-write the `weiv`-specific glue that those libraries do not cover well.

## Evaluation Rules

Each candidate should be judged against the same criteria:

- source span fidelity
- AST quality
- TypeScript or syntax coverage
- ease of integrating with a Zig-written compiler
- fit for incremental/watch workflows
- diagnostics friendliness
- maintenance risk
- how much `weiv`-specific syntax still needs custom handling

## Layer Strategy

`weiv` has four parsing layers:

1. SFC container parsing
2. template parsing
3. script parsing and TypeScript analysis
4. CSS parsing for scoping transforms

The right choice may differ by layer.
We should not assume one tool solves all four well.

## 1. SFC Container Parsing

### Scope

This layer only needs to parse:

- `<template>`
- `<script lang="ts">`
- `<style>`

plus preserve exact source spans and section contents.

### Recommendation

Write this layer directly in Zig.

### Reason

The `.weiv` container format is:

- small
- stable
- framework-specific
- simpler than HTML parsing as a whole

Pulling in a general parser here would add indirection without reducing meaningful risk.

### Decision

- no library evaluation required for SFC splitting
- implement as a small dedicated Zig parser with strong span tracking

## 2. Template Parsing

### Requirements

The template layer must support:

- HTML-like elements and attributes
- text nodes
- interpolation nodes like `{{ expr }}`
- structural directives:
  - `if`
  - `else`
  - `for`
- `on:`
- `bind:`
- accurate source spans

### Candidate: `html5ever`

Source:

- [html5ever docs](https://docs.rs/html5ever/latest/html5ever/)

Strengths:

- mature HTML parser in Rust
- strong HTML parsing behavior
- tokenizer and parser components are available
- could be integrated via a Rust helper binary or library boundary

Risks:

- not designed around `weiv` directives or interpolation syntax
- may require a custom pre-tokenization or post-processing layer
- source-location handling and AST shape may not align naturally with compiler diagnostics needs
- Rust integration adds a second systems-language boundary next to Zig

Assessment:

- good candidate if we want standards-shaped HTML parsing first
- not yet the default recommendation for `weiv` because the framework syntax is only HTML-like, not plain HTML

### Candidate: `tree-sitter-html`

Strengths:

- incremental parsing ecosystem
- broad tooling familiarity
- can be embedded or called through bindings

Risks:

- parse tree shape is less natural as a compiler AST than a dedicated semantic AST
- `weiv` interpolation and directive syntax still need custom grammar work
- extra grammar maintenance may offset the benefit quickly

Assessment:

- worth keeping as a fallback candidate
- not the first choice unless editor tooling reuse becomes the main driver

### Candidate: custom `weiv` template parser in Zig

Strengths:

- exact control over spans and directive semantics
- no impedance mismatch between HTML parsing and `weiv` syntax
- direct control over interpolation and structural syntax

Risks:

- more implementation work
- must handle enough HTML-like correctness to avoid becoming brittle

Assessment:

- still likely the best long-term fit if existing HTML parsers force too much adaptation
- should only be chosen after the library-first evaluation is documented and rejected for concrete reasons

### Current recommendation

- evaluate `html5ever` first
- keep `tree-sitter-html` as a secondary fallback
- expect a custom Zig parser to remain likely if span quality or directive integration is poor

## 3. Script Parsing And TypeScript Analysis

### Requirements

This layer must support:

- TypeScript syntax coverage
- imports
- `export interface Props`
- `export let props: Props`
- top-level bindings
- source spans
- enough structure for template binding diagnostics

The compiler does not initially need full type-checking.
It does need reliable syntax parsing and binding-oriented analysis.

### Candidate: `oxc`

Sources:

- [Oxc parser architecture](https://oxc.rs/docs/learn/architecture/parser.html)
- [Oxc AST docs](https://oxc.rs/docs/contribute/parser/ast)

Observed from current docs:

- Oxc maintains its own JavaScript and TypeScript parser
- its AST nodes carry spans
- it is designed as a compiler-oriented parser with explicit AST types

Strengths:

- parser-first, compiler-oriented design
- strong AST story
- explicit span support
- less dependence on the TypeScript compiler stack
- likely better fit than transpile-only APIs for binding analysis

Risks:

- Rust integration boundary from Zig
- semantic/type-checking story is narrower than full TypeScript compiler APIs
- may require an adapter process or FFI layer

Assessment:

- strongest current candidate for parse-first TypeScript analysis
- should stay on the shortlist even if Bun remains the surrounding toolchain

### Candidate: `bun`

Source:

- [Bun Transpiler docs](https://bun.sh/docs/api/transpiler)

Observed from current docs:

- `Bun.Transpiler` exposes `transform`, `transformSync`, `scan`, and `scanImports`
- the API is clearly strong for transpilation and import scanning
- the docs do not position it as a stable general-purpose external AST API

Strengths:

- already aligned with the chosen Bun toolchain
- simple scripting integration
- fast transpilation path
- useful for import scanning and TS-to-JS output

Risks:

- weaker evidence of a supported external AST interface for compiler analysis
- likely better for transpile workflow than compiler-grade AST ownership
- may require more custom glue for template binding analysis than `oxc`

Assessment:

- strong transpile candidate
- weaker parse-analysis candidate than `oxc` unless AST access proves better than current docs suggest

### Candidate: TypeScript compiler API

Strengths:

- richest TypeScript syntax and semantic ecosystem
- well-understood binding and type-checking surface
- mature diagnostics model

Risks:

- heavier dependency stack
- likely slower and more operationally expensive than parser-focused options
- more JS/TS runtime coupling for a Zig compiler

Assessment:

- best fallback when semantic depth matters more than implementation simplicity
- probably not the first MVP choice unless `weiv` quickly needs true type-checker behavior

### Candidate: restricted custom analyzer

Strengths:

- simple MVP shortcut
- exact control over the narrow script model

Risks:

- fragile
- easy to outgrow immediately
- poor long-term TypeScript story

Assessment:

- acceptable only as a temporary bootstrap layer
- should not be the default plan

### Current recommendation

1. evaluate `oxc` first for parsing and AST extraction
2. evaluate `bun` for transpilation and possibly import-oriented support
3. keep TypeScript compiler API as the high-capability fallback
4. treat a restricted custom analyzer only as a temporary bootstrap option

## 4. CSS Parsing

### Requirements

This layer must support:

- selector-aware parsing
- safe scoped-selector rewriting
- source spans where practical
- future compatibility with modern CSS

### Candidate: `lightningcss`

Source:

- [Lightning CSS](https://lightningcss.dev/)

Observed from current docs:

- it is a CSS parser and transformer
- it is designed for performance
- it already models selectors and modern CSS features

Strengths:

- purpose-built CSS parser/transformer
- strong fit for selector rewriting
- better foundation than ad hoc CSS string rewriting

Risks:

- Rust integration boundary from Zig
- may be more featureful than MVP strictly needs

Assessment:

- strongest current CSS candidate
- should be the default evaluation target for scoped CSS support

### Candidate: custom CSS rewrite pass

Strengths:

- minimal initial implementation

Risks:

- brittle quickly
- unsafe once selector complexity grows
- poor foundation for future CSS support

Assessment:

- avoid unless MVP scoping is intentionally restricted to trivial selectors only

### Current recommendation

- evaluate `lightningcss` first
- avoid string-based CSS rewriting if a real selector parser is viable

## Initial Shortlist

By layer, the current shortlist is:

- SFC container: custom Zig parser
- template: `html5ever` first, custom Zig parser likely fallback, `tree-sitter-html` as backup candidate
- script/TypeScript: `oxc` first, `bun` second, TypeScript compiler API fallback
- CSS: `lightningcss` first

## Evaluation Outcome To Produce

Before implementation starts, the repo should produce one short decision record that answers:

1. Which template parser is chosen?
2. Which script parser/transpile path is chosen?
3. Which CSS parser is chosen?
4. What interop boundary is used from Zig

Current answer:

- FFI

Implication:

- parser-library integration should assume a narrow ABI boundary from the start
- candidate choices should be judged partly on how practical they are to wrap behind FFI

## Current Lean Recommendation

If a decision had to be made today, the leanest serious path looks like:

- SFC: custom Zig
- template: attempt library-first evaluation, but expect custom Zig if directive/span fit is poor
- script parsing: `oxc`
- transpilation: `bun`
- CSS parsing: `lightningcss`
- interop: FFI

That split keeps Bun in the toolchain without forcing it to be the parser for every layer.

Recommended implementation shape:

- Zig compiler core
- Rust helper crate for parser-library integration
- narrow FFI boundary between them
