# Weiv Framework Spec

## 1. Purpose

`weiv` is a frontend framework project intended to combine the strongest parts of several existing frontend approaches while avoiding the parts that feel ergonomically expensive.

The design motivation is:

- keep template, script, and style clearly separated
- avoid JSX as the primary UI authoring model
- avoid making explicit reactive wrappers the default way to write app code
- use compilation aggressively where it improves ergonomics and runtime cost
- preserve strong TypeScript support
- keep the runtime small and understandable

`weiv` is not trying to be novel for novelty's sake.
It is trying to be a practical, high-ergonomics frontend framework for application developers.

## 2. Problem Statement

Current frontend tradeoffs often look like this:

- `React` offers broad ecosystem adoption and explicit control, but pushes UI authoring into JSX and often mixes template concerns into JavaScript.
- `Vue` offers single-file components and clear template separation, but leans heavily on explicit reactive concepts such as `ref()` and `computed()`.
- `Svelte` offers compiler-driven ergonomics and strong single-file authoring, but modern usage still introduces explicit reactive primitives such as `$state()` and `$derived()`.
- `Angular` offers a more conventional template/state ergonomics and avoids per-value reactive wrappers by default, but usually splits component concerns across multiple files and carries a heavier framework model.

`weiv` exists because there is room for a framework with this combination:

- Vue/SFC-like component authoring
- Angular-like default state ergonomics without inheriting Angular's class-first component shape
- Svelte-like willingness to compile aggressively
- a smaller, clearer runtime surface than heavyweight enterprise frameworks

## 3. Framework Vision

`weiv` should feel like:

- writing components, not writing framework ceremony
- describing UI in templates, not embedding templates in JavaScript
- updating ordinary state, not wrapping everything in reactive containers
- using compile-time help where possible, not paying unnecessary runtime abstraction tax

The framework should feel boring in the good sense:

- predictable
- readable
- easy to onboard into
- easy to debug
- easy to statically analyze

## 4. Core Principles

### 4.1 Template, Script, Style Separation

Single-file components are a core part of the design.
Each component should allow a shape similar to:

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

This separation is a first-class product choice, not an optional addon.

### 4.2 Ordinary State First

The default component state model should feel like ordinary TypeScript variables, object fields, and functions.

The framework should avoid requiring patterns like:

- `ref(...)`
- `computed(...)`
- `$state(...)`
- `$derived(...)`

for routine component authoring.

If advanced reactivity primitives exist at all, they should be:

- intentionally scoped
- opt-in
- not the everyday happy path

### 4.3 Compiler First, Runtime Second

Whenever a concern can be solved at compile time without making the mental model confusing, that should be preferred.

Examples:

- template compilation
- scoped style transforms
- event binding lowering
- static tree detection
- template-to-DOM update planning

The runtime should exist to support:

- component lifecycle
- mounting/unmounting
- event dispatch/binding
- change propagation
- scheduling

but it should not become a dumping ground for every abstraction.

### 4.4 TypeScript Native

TypeScript should be a first-class design input, not retrofitted later.

This includes:

- strong component prop typing
- strong event payload typing
- strong template-to-script symbol validation
- editor tooling and diagnostics
- source maps that preserve debuggability

### 4.5 Explicit Boundaries Over Magic

`weiv` may use compilation and inference aggressively, but it should not become mysterious.

Rules should be:

- learnable
- explainable
- inspectable

The compiler should not depend on hidden framework folklore to be productive.

## 5. What Weiv Will Be

`weiv` will be:

- a component model
- a single-file component format
- a compiler
- a small runtime
- a build-tool integration layer
- a TypeScript/editor integration story

Over time, the ecosystem may also include:

- a router
- a forms package
- a resource/data-loading package
- testing helpers
- SSR adapters

But these are secondary to the core framework.

## 6. What Weiv Will Not Be

At least initially, `weiv` will not be:

- a full backend framework
- a large enterprise platform
- an everything-in-one batteries-included mega-system
- a clone of React, Vue, Svelte, or Angular
- a signal-wrapper framework where every meaningful value lives inside a framework-specific container
- a JSX-first or render-function-first UI system
- a CSS-in-JS opinion

It will also not aim to solve every frontend problem in v1:

- SSR can be deferred
- routing can be deferred
- animation systems can be deferred
- server mutations/data cache layers can be deferred

## 7. Component Authoring Model

## 7.1 File Shape

The primary component format should be a single file with explicit sections:

```html
<template>
  <button on:click="increment">
    {{ count }}
  </button>
</template>

<script lang="ts">
  export interface Props {
    initialCount?: number;
  }

  export let props: Props;

  let count = props.initialCount ?? 0;

  function increment() {
    count += 1;
  }
</script>

<style>
  button {
    font: inherit;
  }
</style>
```

The exact syntax may evolve, but the intent is stable:

- template remains declarative
- script remains TypeScript-first
- style remains ordinary CSS-first

## 7.2 Script Model

The default script model should favor a plainly-structured component module API.

The framework should begin from the assumption that developers want to write:

- local variables
- named methods
- functions
- props
- derived values through ordinary code when possible

instead of wrapping every state value in a special framework primitive.

## 7.3 Template Expression Model

Templates should support:

- interpolation
- conditionals
- lists
- event binding
- attribute binding
- component composition

But the template language should remain intentionally smaller than arbitrary JavaScript.

This is important for:

- compiler reasoning
- template readability
- static analysis
- better editor diagnostics

## 7.4 Styling Model

Scoped component styles should be supported by default.

The style system should prefer:

- ordinary CSS
- predictable scoping
- low abstraction

The framework should avoid forcing:

- CSS-in-JS
- runtime styling primitives
- nonstandard styling DSLs

## 8. Reactivity Model

This is the most important design constraint in the project.

### 8.1 Desired Outcome

Developers should be able to write ordinary-looking component state without explicitly wrapping each state value in framework-specific reactive containers.

The preferred mental model is:

- component instance holds state
- template depends on state
- framework/compiler tracks enough structure to update efficiently

### 8.2 Non-Goals

The default model should not require:

- explicit per-field wrappers
- explicit computed wrappers for simple derivations
- framework-wide dependence on proxy semantics in application code

### 8.3 Acceptable Hidden Mechanisms

Implementation-wise, `weiv` may use:

- compiler transforms
- property instrumentation
- generated update plans
- runtime subscriptions internal to the framework

The important rule is:

the implementation mechanism is allowed to be sophisticated, but the authoring model should remain simple.

### 8.4 Derived State

Simple derived values should be expressible as:

- local computed constants or functions
- ordinary helper functions
- compile-time analyzable template expressions

If the framework later introduces special primitives for expensive or async derivation, they should remain advanced tools, not the default expectation.

## 9. Compiler Responsibilities

The `weiv` compiler should own:

- parsing `.weiv` single-file components
- validating component sections
- binding template symbols to script scope
- transforming scoped CSS
- compiling templates to optimized runtime instructions
- producing sourcemaps
- emitting TypeScript-friendly artifacts for tooling

The compiler is a core product, not just an implementation detail.

## 10. Runtime Responsibilities

The runtime should be intentionally small.

Expected responsibilities:

- mount component trees
- create/destroy component instances
- connect compiled template instructions to DOM operations
- schedule updates
- coordinate event handlers
- support lifecycle hooks

The runtime should avoid becoming:

- a large general-purpose reactive graph engine
- a kitchen-sink state library
- an unbounded plugin host

## 11. Tooling Integration

The likely initial tooling direction should include:

- a dependency-light `weiv` CLI
- Bun-friendly TypeScript workflow support
- TypeScript language tooling hooks
- source map support
- test runner compatibility

The first-class developer experience should include:

- good diagnostics for template symbol errors
- easy local dev startup
- stable stack traces
- clear compiled output inspection

## 12. Rendering Strategy

The first implementation should prioritize client-side rendering.

Reason:

- it reduces initial complexity
- it lets the component model and compiler stabilize first
- it avoids mixing core framework design with SSR architecture too early

Later possible stages:

- SSR rendering API
- hydration/resume story
- static-site or partial-prerender adapters

These should be future phases, not day-one obligations.

## 13. Routing and Data

Routing and data-fetching should not be required to prove the core framework.

The first `weiv` milestone should succeed without:

- a built-in router
- a built-in cache layer
- a framework-owned GraphQL client

These can evolve later as packages or companion projects.

## 14. MVP Scope

The v1 MVP should include only the minimum viable framework foundation:

- `.weiv` single-file component parser
- `<template>`, `<script lang="ts">`, `<style>` sections
- component props
- conditionals
- loops
- event binding
- scoped CSS
- small browser runtime
- Vite integration
- source maps
- one or two realistic example apps

The MVP should not include:

- SSR
- router
- transitions system
- complex forms package
- resource cache system
- custom animation DSL

## 15. Evolution Path

The intended maturity path should be:

### Phase 1: Spec and Syntax Stability

- lock the conceptual model
- lock SFC shape
- lock the default state philosophy
- lock compiler/runtime responsibilities

### Phase 2: Parser, Compiler, Minimal Runtime

- parse components
- mount simple components
- support props, events, conditional rendering, loops
- prove that the authoring model feels right

### Phase 3: Tooling and Developer Experience

- Vite integration
- diagnostics
- source maps
- editor support
- examples

### Phase 4: Ecosystem Foundations

- router
- testing utilities
- async resource primitives if actually needed
- form helpers

### Phase 5: Advanced Delivery Modes

- SSR
- hydration
- static generation
- adapters

## 16. Deliberately Deferred Questions

These questions are important, but should not block the first spec baseline:

- should the default script model be purely module-based or allow an optional object wrapper pattern?
- what exact syntax should templates use for interpolation and control flow?
- how much JavaScript should template expressions allow?
- should styles default to scoped or opt-in scoped?
- what should component-to-component event typing feel like?
- should the compiler target DOM instructions directly or an intermediate representation first?
- what should the package split be across compiler/runtime/tooling?

These are design decisions for the next stage, not reasons to delay the specification.

## 17. Design Constraints

Every design decision in `weiv` should be tested against these questions:

1. Does this make ordinary component code more readable?
2. Does this avoid forcing framework-specific wrappers into everyday state?
3. Does this preserve clear template/script/style separation?
4. Does this keep the runtime smaller when a compiler can do the work?
5. Does this improve TypeScript and tooling quality rather than fight it?
6. Is this something a product team would still enjoy using after six months?

If a proposed feature fails those tests, it should be rejected or deferred.

## 18. Success Criteria

`weiv` succeeds if developers can say:

- “I can write components naturally.”
- “I do not have to adopt a strange state wrapper model just to render UI.”
- “My templates stay readable.”
- “My logic stays in TypeScript instead of leaking into markup.”
- “The framework helps me more than it asks from me.”

That is the real product target.
