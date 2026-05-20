# Reactivity

Weiv starts with ordinary local state inside the component.

You update variables directly, and the compiler/runtime path takes care of
patching the DOM where needed.

## Local State First

```html
<template>
  <section>
    <h2>{{ title }}</h2>
    <p>Count: {{ count }}</p>
    <button on:click="increment">Increment</button>
  </section>
</template>

<script lang="ts">
  let title = "Counter";
  let count = 0;

  function increment() {
    count += 1;
  }
</script>
```

This is the default model:

- keep state close to the component
- mutate normal variables directly
- let DOM updates follow from those changes

## Derived Values

Use ordinary functions when a value can be derived from local state.

```html
<template>
  <section>
    <p>Count: {{ count }}</p>
    <p>Doubled: {{ doubled() }}</p>
  </section>
</template>

<script lang="ts">
  let count = 2;

  function doubled() {
    return count * 2;
  }
</script>
```

## Event-Driven Updates

Local state usually changes in response to events.

```html
<template>
  <button on:click="toggleOpen">
    {{ open ? "Hide details" : "Show details" }}
  </button>

  <p if="open">Details are visible.</p>
</template>

<script lang="ts">
  let open = false;

  function toggleOpen() {
    open = !open;
  }
</script>
```

## When To Reach For Shared State

Stay with local state for most component logic.

Move to explicit shared state when:

- multiple components need the same mutable data
- state must outlive one component instance
- routing or external modules need to observe the same state

That is when `weiv:observable` becomes useful.

## Shared State Example

```ts
import { observable } from "weiv:observable";

export const counter = observable({
  value: 0
});
```

Use that model intentionally, not by default.

## Next Step

Use [Shared State](./shared-state.md) for the cross-component observable model,
or [Template Syntax](./template-syntax.md) for the template directives that
usually drive local reactivity.
