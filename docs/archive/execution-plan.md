# Weiv Execution Plan

## Purpose

This document turns the framework spec into a phased implementation plan.

It is intended to answer:

- what to build first
- what must be decided before code starts
- what artifacts each phase should produce
- what signals allow the project to move to the next phase

The plan stays aligned with the current project constraints:

- spec-first
- compiler-first
- TypeScript-first
- client-side rendering first
- CLI-first tooling integration
- Bun-friendly TypeScript workflow
- no router, SSR, forms stack, or ecosystem expansion in MVP

Scope guard:

- use [Framework Scope](./framework-scope.md) to decide whether a feature is required, later, or intentionally not planned

## Execution Rules

These rules apply across every phase:

1. Do not expand scope to cover SSR, routing, data frameworks, transitions, or platform features before the CSR foundation is proven.
2. Resolve syntax and architecture questions with small artifacts and prototypes, not long speculative redesign loops.
3. Keep the runtime minimal and move complexity into the compiler when that improves authoring ergonomics and debuggability.
4. Treat diagnostics and inspectability as core product work, not cleanup work for later.
5. Only advance a phase when its exit criteria are met.

## Phase 0: Decision Lock

### Goal

Turn the current spec into a sufficiently narrow implementation contract.

### Scope

- lock the `.weiv` single-file component shape
- choose the initial script model
- choose the initial template control-flow syntax
- choose the CSS scoping approach
- choose the compiler pipeline shape
- define the initial runtime API boundary

### Deliverables

- one syntax decision doc covering:
  - section grammar
  - interpolation syntax
  - conditionals
  - loops
  - event binding
  - attribute binding
- one architecture decision doc covering:
  - compiler phases
  - intermediate representation strategy
  - runtime responsibilities
  - update scheduling assumptions
- one typed component authoring example set:
  - basic props
  - local state mutation
  - conditional rendering
  - list rendering
  - component composition
- one MVP acceptance checklist

### Recommended decisions

- use `.weiv` as the initial extension unless a blocking tooling issue appears
- use a module-based script model first because it best matches the “ordinary TypeScript” goal
- keep template expressions intentionally smaller than arbitrary JavaScript
- use scoped CSS by default with compiler-driven selector rewriting
- compile through an explicit intermediate representation rather than lowering directly from template AST to DOM operations

### Exit criteria

- no unresolved decision remains that would force parser or compiler rework in the next phase
- two or three example components can be written without inventing ad hoc syntax
- the team can describe how a template symbol resolves into script scope and then into runtime update behavior

## Phase 1: Compiler Skeleton

### Goal

Build the end-to-end non-rendering pipeline so `.weiv` files can be parsed, validated, and compiled into inspectable artifacts.

### Scope

- file loader for `.weiv`
- section splitter and validator
- template parser
- script extraction
- style extraction
- template-to-script symbol binding
- CSS scoping transform
- initial intermediate representation
- code generation stubs
- sourcemap plumbing

### Deliverables

- parser package
- AST definitions
- IR definitions
- compiler package with explicit phases
- fixture-based tests for syntax and diagnostics
- compiled output snapshots for representative components

### Implementation order

1. SFC section parser and validation
2. template AST and expression parsing
3. script/style extraction and location tracking
4. symbol binding and diagnostics
5. CSS scoping transform
6. IR generation
7. codegen shell and sourcemap wiring

### Exit criteria

- a `.weiv` file compiles deterministically into typed intermediate artifacts
- invalid symbol references produce clear diagnostics with source locations
- style scoping output is predictable and test-covered
- generated artifacts are inspectable enough to debug before runtime work deepens

## Phase 2: Minimal Runtime and DOM Rendering

### Goal

Prove the authoring model works in the browser with a small runtime and compiled DOM updates.

### Scope

- component instance creation
- props initialization
- mount/unmount
- event binding
- text interpolation updates
- conditional rendering
- list rendering
- child component composition
- update scheduling

### Deliverables

- runtime package
- DOM instruction or IR executor
- component mount API
- lifecycle baseline:
  - create
  - mount
  - update
  - destroy
- browser integration example
- runtime tests covering update semantics

### Design constraints

- no public fine-grained reactive primitives in the default path
- no generalized graph engine unless the compiler/runtime contract genuinely requires it
- prefer generated update plans over opaque runtime magic

### Exit criteria

- the counter-style example works with ordinary local state mutation
- conditionals and lists update correctly without explicit reactive wrappers
- event handlers are correctly bound and cleaned up
- runtime internals are still small enough to explain in a short architecture note

## Phase 3: CLI Integration and Local DX

### Goal

Make the framework usable as a local development toolchain rather than a raw compiler demo.

### Scope

- `weiv` CLI
- Bun-oriented TypeScript workflow
- watch mode, even if initially simple
- browser-facing sourcemap validation
- example app bootstrapping without bundler plugin lock-in
- compiled output inspection hooks

### Deliverables

- CLI package
- `weiv build` command
- `weiv dev` or `weiv watch` command
- example app template
- local development guide
- developer debugging guide for compiled output
- integration tests proving `.weiv` files compile and run through the CLI workflow

### Exit criteria

- a small example app runs through the CLI workflow with an edit-refresh loop
- source locations in errors map back to `.weiv` files with acceptable accuracy
- the compiler/runtime boundary is stable enough that example app work is not blocked by tooling gaps

## Phase 4: Diagnostics and TypeScript Tooling

### Goal

Harden the authoring experience so framework errors feel product-quality.

### Scope

- template symbol diagnostics
- prop typing ergonomics
- event typing strategy
- editor-facing metadata or TS integration hooks
- clearer compiler error messages
- example-driven validation of authoring rules

### Deliverables

- diagnostics catalog
- template-to-script validation rules
- TypeScript integration notes or tooling prototype
- type tests for props and component usage
- error message regression suite

### Implementation priorities

1. unresolved symbol diagnostics
2. invalid prop usage diagnostics
3. source spans that map template nodes cleanly
4. event handler typing
5. editor/tooling integration polish

### Exit criteria

- common authoring mistakes fail with actionable messages
- prop types remain first-class through compilation
- template errors can be traced without inspecting generated code

## Phase 5: Realistic Example Validation

### Goal

Validate ergonomics against something more representative than a counter.

### Scope

- one toy example retained for clarity
- one realistic example added for pressure-testing
- documented gaps found during example implementation

### Suggested example shape

Build a small app that requires:

- nested components
- props flowing through multiple levels
- list rendering
- conditional UI branches
- form input events
- derived display values
- scoped component styling

Avoid choosing an example that forces routing or SSR into scope.

### Deliverables

- realistic example app
- ergonomics review notes
- list of spec or implementation adjustments discovered through actual use

### Exit criteria

- the realistic example can be built without introducing framework escape hatches
- pain points are concrete and prioritized
- any required syntax or architecture changes are still small enough to absorb before preview

## Phase 6: MVP Preview Readiness

### Goal

Package the framework as an intentional early preview once the core experience is coherent.

### Scope

- package naming and split finalization
- publishable package structure
- installation path
- basic docs
- sample apps
- contribution guidance

### Deliverables

- publishable compiler/runtime/Vite packages
- getting-started documentation
- framework philosophy overview
- sample apps and known limitations list

### Exit criteria

- a new user can install, run, and understand the framework without reading internal design notes first
- known limitations are explicit
- the preview invites feedback on ergonomics, not confusion about missing core behavior

## Cross-Phase Workstreams

These workstreams should continue through multiple phases instead of being left to the end.

### Testing

- fixture tests for parsing and diagnostics
- runtime behavior tests
- example app smoke tests
- regression cases whenever syntax or binding behavior changes

### Observability

- inspectable compiler output
- architecture notes for IR and runtime instructions
- minimal debug hooks for mounted component state and updates

### Documentation

- update the framework spec only when product-level intent changes
- keep implementation decisions in focused docs rather than mutating the spec into a design dump
- record rejected alternatives when they materially affect later contributors

## Immediate Next Actions

The current repo should do these next:

1. Create a syntax decisions document that narrows the `.weiv` grammar enough for parser work to start.
2. Create a compiler architecture document that names phases, AST/IR boundaries, and runtime/codegen contracts.
3. Create an MVP checklist derived from the framework spec.
4. Add three canonical example components that exercise props, branching, lists, and child composition.
5. Start Phase 1 only after those documents remove ambiguity from parser and runtime boundaries.

Status as of 2026-05-01:

- syntax decisions doc: created
- compiler architecture doc: created
- MVP checklist: created
- canonical example expansion: created
- Zig interop direction: FFI selected
- composition milestone (slots): completed

## Risks To Manage

- unresolved script-model debate causing churn across parser, binding, and codegen
- too-permissive template expressions making analysis and diagnostics weak
- runtime growth caused by postponing compiler decisions
- hidden bundler assumptions leaking into compiler output despite the CLI-first goal
- TypeScript support treated as post-MVP polish instead of core architecture input
- example apps chosen too early from problem spaces that pull in router or SSR requirements

## Definition Of Success

This plan is working if each new phase reduces ambiguity and increases proof:

- Phase 0 proves the design is narrow enough to build
- Phase 1 proves the compiler model is coherent
- Phase 2 proves the authoring model feels right
- Phase 3 and Phase 4 prove the developer experience is credible
- Phase 5 proves the framework holds up outside toy demos
- Phase 6 proves the project is ready for external evaluation
