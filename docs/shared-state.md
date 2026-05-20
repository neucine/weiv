# Shared State

Use local variables by default. Reach for `weiv:observable` when state needs to
cross component boundaries.

## Create Shared State

```ts
// state/counter.ts
import { observable } from "weiv:observable";

export const counter = observable({
  value: 0,
  label: "Shared counter"
});
```

## Read And Update It In A Component

```html
<template>
  <section>
    <p>{{ counter.label }}: {{ counter.value }}</p>
    <button on:click="increment">Add</button>
  </section>
</template>

<script lang="ts">
  import { counter } from "./state/counter.ts";

  function increment() {
    counter.value += 1;
  }
</script>
```

## When To Use It

- state shared by multiple components
- route-level or app-level state
- external modules that own their own mutable data

## What You Get

- observable updates across component boundaries
- typings for `weiv:observable` from the published `weivjs` package
- a small runtime surface instead of a larger framework-wide state layer
