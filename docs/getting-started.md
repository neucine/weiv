# Getting Started

## Status

`weiv` is runnable today, but still pre-v1.

The current checkpoint includes a working direct-DOM browser path,
compiler-driven invalidation, slot composition, shared observable runtime
integration, runtime routing, and growing runtime/component verification.

## Install

```bash
npm i -D weivjs
```

The published `weivjs` package includes:

- the `weiv` CLI
- bundler adapters at `weivjs/vite` and `weivjs/bun`
- optional typings for `weiv:observable` and `weiv:router`

## Install The VS Code Extension

For the best `.weiv` authoring experience in VS Code, install the Weiv
extension too.

See [VS Code Extension](./vscode-extension.md).

## Check The CLI

```bash
npx weiv --help
```

## Run Your Own Root Component

```bash
npx weiv dev path/to/App.weiv
```

## Emit A Static App Bundle

```bash
npx weiv compile emit app path/to/App.weiv ./dist
cd ./dist
bun server.ts
```

## Diagnostics JSON

```bash
npx weiv --json-diagnostics compile emit js path/to/App.weiv
```

This emits structured diagnostics with:

- `action`
- `sourcePath`
- `ok`
- `diagnostics`

## Optional Runtime Imports

Use `weiv:*` imports only when you need them.

- `weiv:observable` for shared observable state
- `weiv:router` for client-side routing

The package already includes typings for both virtual modules.

For concrete examples, see [Shared State](./shared-state.md) and
[Router Example](./router-example.md).
