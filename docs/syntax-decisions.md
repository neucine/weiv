# Weiv Syntax Decisions

## Purpose

This document locks the initial `.weiv` authoring syntax tightly enough for parser and compiler work to begin.

It is intentionally narrow.
If a syntax feature is not described here, it is not part of the Phase 1 contract.

## Decision Summary

The initial syntax direction is:

- file extension: `.weiv`
- component format: single-file component with explicit top-level sections
- required sections:
  - `<template>`
  - `<script lang="ts">`
- optional sections:
  - `<style>`
- script model: module-based
- interpolation: `{{ expr }}`
- event binding: `on:event="handler"`
- control flow: directive-style attributes first
- list rendering: directive-style attributes first
- child components: capitalized tags
- style scoping: scoped by default through compiler selector rewriting

## 1. File Shape

Each component is a single `.weiv` file with explicit top-level sections.

Initial allowed shape:

```html
<template>
  ...
</template>

<script lang="ts">
  ...
</script>

<style>
  ...
</style>
```

### Rules

- exactly one `<template>` section is required
- exactly one `<script lang="ts">` section is required
- zero or one `<style>` section is allowed initially
- section order is fixed in Phase 1:
  - `<template>`
  - `<script lang="ts">`
  - `<style>`
- duplicate sections are a compile error
- unknown top-level sections are a compile error

### Rationale

Fixed section order reduces parser ambiguity in the first implementation and keeps diagnostics simple.

## 2. Script Model

The initial script model is module-based.

Authors write ordinary TypeScript declarations in component scope:

- `export interface Props`
- `export let props: Props`
- local `let` state
- local `const` helpers
- named functions

Example:

```ts
export interface Props {
  title: string;
  initialCount?: number;
}

export let props: Props;

let count = props.initialCount ?? 0;

function increment() {
  count += 1;
}

function doubled() {
  return count * 2;
}
```

### Rules

- `lang="ts"` is required on `<script>`
- `export let props: Props` is the initial props declaration form
- no class-based component model in MVP
- no object-literal wrapper model in MVP
- no framework-specific state wrappers in the default path

### Deferred

- alternate prop declaration forms
- instance lifecycle syntax
- context/injection APIs
- async setup semantics
- composition model details:
  - see [Composition Model](./composition-model.md)

## 3. Template Syntax

The template syntax is HTML-like with a constrained expression layer.

Templates support:

- text interpolation
- attribute binding
- event binding
- conditionals
- list rendering
- child component composition

### 3.1 Interpolation

Text interpolation uses mustache syntax:

```html
<p>{{ count }}</p>
```

Interpolation expressions may reference:

- props
- local variables
- function calls with simple argument expressions
- member access
- arithmetic and boolean expressions

Not allowed in Phase 1:

- statements
- assignments inside template expressions
- `await`
- inline function literals
- arbitrary new expressions

### 3.2 Attribute Binding

Static attributes use normal HTML syntax.

Dynamic attributes use `bind:`:

```html
<button bind:disabled="count === 0">
  Save
</button>
```

Rules:

- `bind:name="expr"` assigns the evaluated expression to the DOM attribute or DOM property chosen by compiler rules
- the compiler should initially support a narrow, explicit mapping for common HTML cases rather than guessing broadly
- unsupported bindings should fail clearly

### 3.3 Event Binding

Event handlers use `on:`:

```html
<button on:click="increment">
  Increment
</button>
```

Rules:

- handler values must resolve to script-scope callables
- direct function reference is the preferred form
- expression handlers may be supported later, but are not required in Phase 1

### 3.4 Conditionals

Initial conditional rendering uses `if` and `else` directive attributes:

```html
<p if="count > 0">Active</p>
<p else>Empty</p>
```

Rules:

- `if="expr"` marks a conditional branch
- `else` must immediately follow a sibling `if` branch
- `else if` is deferred in Phase 1
- directive placement outside valid sibling structure is a compile error

### 3.5 Lists

Initial list rendering uses `for`:

```html
<li for="item in items">
  {{ item.label }}
</li>
```

Rules:

- initial form is `for="item in items"`
- keyed list syntax is deferred
- index binding is deferred
- nested list semantics are supported only through repeated valid `for` usage, not special syntax

### 3.6 Child Components

Child components use capitalized tags:

```html
<CounterCard bind:title="title" />
```

Rules:

- capitalized tag names resolve as components
- lowercase tag names resolve as native elements
- explicit import requirements and resolution rules belong in the compiler architecture doc

## 4. Style Syntax

The initial style block contains ordinary CSS:

```html
<style>
  .counter-card {
    padding: 1rem;
  }
</style>
```

Rules:

- styles are scoped by default
- scoping is implemented by compiler selector rewriting
- no CSS-in-JS
- no custom CSS DSL
- CSS modules support is deferred
- multiple style blocks are deferred

## 5. Canonical Example

```html
<template>
  <section class="counter-card">
    <h2>{{ props.title }}</h2>

    <p if="count > 0">Current count: {{ count }}</p>
    <p else>Empty</p>

    <ul>
      <li for="item in items">{{ item.label }}</li>
    </ul>

    <button on:click="increment" bind:disabled="count >= limit">
      Increment
    </button>
  </section>
</template>

<script lang="ts">
  export interface Props {
    title: string;
    initialCount?: number;
  }

  export let props: Props;

  let count = props.initialCount ?? 0;
  let limit = 10;
  let items = [{ label: "One" }, { label: "Two" }];

  function increment() {
    count += 1;
  }
</script>

<style>
  .counter-card {
    padding: 1rem;
    border-radius: 16px;
  }
</style>
```

## 6. Compiler Expectations From Syntax

This syntax contract implies:

- the SFC parser must preserve section boundaries and source spans
- the template parser must understand directive attributes as structural syntax, not plain HTML attributes
- the compiler must bind template expressions against script scope
- the style transformer must rewrite selectors using component scope identifiers
- the emitter must produce JS and CSS modules consumable by Bun-driven app workflows

## 7. Explicit Deferrals

These features are intentionally not part of the first syntax contract:

- slots
- fragments as first-class syntax
- `else if`
- keyed `for`
- two-way bindings
- transitions
- inline async template expressions
- custom directive authoring
- alternate script languages
- multiple `<style>` blocks

## 8. Exit Condition For This Document

Phase 1 may start once parser and compiler implementation can treat this document as the working syntax contract without reopening routine authoring questions.
