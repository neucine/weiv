# weivjs

Compiler-first `.weiv` tooling in one package:

- `weiv` CLI
- Vite plugin (`weivjs/vite`)
- Bun plugin (`weivjs/bun`)
- optional `weiv:*` typings (`weiv:observable`, `weiv:router`)

## Install

```bash
npm i -D weivjs
```

Then run:

```bash
npx weiv --help
```

## CLI Usage

```bash
# Dev server
npx weiv dev src/App.weiv

# Emit browser app bundle
npx weiv compile emit app src/App.weiv ./dist

# Emit JS for a component
npx weiv compile emit js src/App.weiv
```

## Writing `.weiv` SFCs

You can build normal components without any `weiv:*` imports.

```html
<template>
  <section>
    <h1>{{ title }}</h1>
    <p>Count: {{ count }}</p>
    <button @click="increment">Increment</button>
  </section>
</template>

<script>
  let title = "Hello Weiv";
  let count = 0;
  function increment() {
    count += 1;
  }
</script>
```

Use `weiv:*` imports only when you need shared state or routing.

Shared state example:

```ts
// state/counter.ts
import { observable } from "weiv:observable";

export const counter = observable({
  value: 0
});
```

```html
<template>
  <div>
    <p>Shared: {{ counter.value }}</p>
    <button @click="counter.value += 1">Add</button>
  </div>
</template>

<script>
  import { counter } from "./state/counter.ts";
</script>
```

Router example:

```ts
import { createRouter } from "weiv:router";

export const router = createRouter({
  routes: [
    { path: "/", component: () => import("./views/Home.mjs") },
    { path: "/about", component: () => import("./views/About.mjs") }
  ],
  target: document.getElementById("app")
});
```

## Vite Plugin

```ts
// vite.config.ts
import { defineConfig } from "vite";
import { weiv } from "weivjs/vite";

export default defineConfig({
  plugins: [weiv()]
});
```

You can then import `.weiv` files directly in your app.

## Bun Plugin

```ts
// bunfig.toml uses a JS/TS plugin file, for example build.ts
import { weiv } from "weivjs/bun";

export default {
  plugins: [weiv()]
};
```

## Optional `weiv:*` Typings

This package ships optional typing support for:

- `weiv:observable`
- `weiv:router`

Use these when needed in your app or generated code.
