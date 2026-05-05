# Decisions To Make Later

These decisions are intentionally not locked yet.

## 1. Script Model

Open options:

- module-based component model
- object-literal-based component model
- hybrid with compile-time lowering

Selection criteria:

- readability
- TypeScript quality
- ease of binding to templates
- low ceremony
- no class-first bias by default

## 2. Template Syntax

Open options:

- mustache-style interpolation
- directive-style control flow
- block-style control flow

Selection criteria:

- readability
- parser simplicity
- IDE tooling potential
- avoiding template-language bloat

## 3. Reactivity Implementation Strategy

The authoring model should avoid explicit reactive wrappers by default, but the implementation may vary.

Possible internal techniques:

- compile-time dependency analysis
- property instrumentation
- generated dirty-check/update plans
- hidden fine-grained subscription graphs

Selection criteria:

- authoring ergonomics
- predictable performance
- debuggability
- implementation complexity

## 4. Styling Strategy

Open options:

- scoped CSS by default
- explicit scoped mode
- hashed selector rewriting
- shadow-dom-compatible future mode

## 5. Naming Conventions

Still open:

- file extension: `.weiv` or another format
- package namespace
- runtime/compiler package split

## 6. Long-Term Delivery Modes

To revisit only after CSR foundation is stable:

- SSR
- hydration
- static generation
- partial resume strategies
