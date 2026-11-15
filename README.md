<p align="center">
  <img src="https://weiv.dev/assets/weiv.png" alt="Weiv" width="120" />
</p>

# Weiv

[简体中文](README.zh-CN.md)

Weiv is a framework for building web pages with TypeScript. A `.weiv` file keeps
its markup, code, and styles together. Changing a value updates the page.

Weiv is available to try and is still before its first stable release. The
published compiler supports macOS arm64, Linux x64 GNU, and Windows x64 GNU.
For another platform, provide a compatible binary through `WEIV_BINARY_PATH`.

## Get started

Install Weiv in a Node.js project:

```sh
npm install --save-dev weivjs
```

Create `App.weiv`:

```html
<template>
  <button @click="increment">Count: {{ count }}</button>
</template>

<script lang="ts">
  let count = 0;

  function increment() {
    count += 1;
  }
</script>
```

Run the page locally:

```sh
npx weiv dev App.weiv
```

For a static bundle, run `npx weiv compile App.weiv`. Weiv writes the result to
`dist/`; use `bun dist/server.ts` to serve it.

## Learn more

- [Getting started](https://weiv.dev/getting-started)
- [Components](https://weiv.dev/simple-component)
- [API guide](https://weiv.dev/api-guide)
- [State and updates](https://weiv.dev/reactivity)
- [VS Code extension](packages/vscode-extension/README.md)

The package also provides adapters at `weivjs/vite` and `weivjs/bun`. See the
[package guide](packages/weiv/README.md) for those integrations.
