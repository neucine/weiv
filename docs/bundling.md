# Bundling With Vite And Bun

The published `weivjs` package includes bundler adapters for both Vite and Bun.

Install the package first:

```bash
npm i -D weivjs
```

## Vite

Install Vite if your app does not already use it:

```bash
npm i -D vite
```

Then add the Weiv plugin:

```ts
// vite.config.ts
import { defineConfig } from "vite";
import { weiv } from "weivjs/vite";

export default defineConfig({
  plugins: [weiv()]
});
```

After that, you can import `.weiv` files directly from your app:

```ts
import App from "./App.weiv";

App.mount(document.getElementById("app")!, {});
```

## Bun

Use the Bun adapter when you want Bun to handle the plugin pipeline:

```ts
// build.ts
import { weiv } from "weivjs/bun";

export default {
  plugins: [weiv()]
};
```

This keeps `.weiv` compilation inside the Bun build flow instead of requiring a
separate compile step.

## Which One To Use

- Use Vite when you want a standard dev server and browser build pipeline.
- Use Bun when your project already leans on Bun for build orchestration.
- In both cases, the adapter comes from the same `weivjs` package.
