<p align="center">
  <img src="./docs/assets/weiv.png" alt="weiv" width="120" />
</p>

Frontend, with room to breathe.

`weiv` is a compiler-first frontend framework for single-file components,
direct DOM updates, and zero runtime by default.

- single-file components with clear template, script, and style boundaries
- TypeScript-friendly authoring without JSX
- plain local state by default
- explicit shared state only when it crosses component boundaries
- zero runtime by default; optional tiny runtime surface when needed
- direct DOM updates instead of a framework-wide VDOM layer
- runtime-level routing integrated with emitted component lifecycle

## Status

Runnable today, still pre-v1.

The current checkpoint includes a working direct-DOM browser path,
compiler-driven invalidation, slot composition, shared observable runtime
integration, runtime routing, and growing runtime/component verification.

The project is now beyond the initial experimental phase, but still needs:

- more precise dependency analysis
- broader app-scale verification
- diagnostics unification
- IDE/tooling polish
- additional runtime precision work

before it should be treated as production-ready.

## Quick Start

Install the published package:

```bash
npm i -D weivjs
```

Then run the included CLI:

```bash
npx weiv --help
npx weiv dev path/to/App.weiv
```

If you want a static bundle instead of the dev server:

```bash
npx weiv compile emit app path/to/App.weiv ./dist
cd ./dist
bun server.ts
```

## NPM Package

`weivjs` is now published with:

- CLI command: `weiv`
- bundler adapters: `weivjs/vite`, `weivjs/bun`
- optional typings: `weiv:observable`, `weiv:router`

See packaging details in [NPM Single-Package Distribution](./docs/npm-single-package-distribution.md).

## Diagnostics JSON

For tooling and machine-readable failure handling:

```bash
npx weiv --json-diagnostics compile emit js path/to/App.weiv
```

This emits canonical diagnostics JSON with:

- `action`
- `sourcePath`
- `ok`
- `diagnostics` (`code`, `severity`, `stage`, `message`, `location`, `span`, `fatal`)

## Learn More

- [Docs Index](./docs/README.md)
- [Framework Vision](./docs/framework-vision.md)
- [Current Architecture](./docs/architecture.md)
- [Current Status](./docs/status.md)
- [NPM Single-Package Distribution](./docs/npm-single-package-distribution.md)

## Contributor Commands

```bash
zig build test
zig build component-test
zig build runtime-test
zig build test-all
npm run test:package
```
