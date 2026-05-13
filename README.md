<p align="center">
  <img src="./docs/assets/weiv.png" alt="weiv" width="120" />
</p>

Frontend, with room to breathe.

`weiv` is a compiler-first frontend framework for single-file components,
direct DOM updates, and minimal runtime semantics.

- single-file components with clear template, script, and style boundaries
- TypeScript-friendly authoring without JSX
- plain local state by default
- explicit shared state only when it crosses component boundaries
- a minimal runtime with more work pushed into compiled output
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

Try the included examples first:

```bash
zig build run -- dev test/examples/todomvc/App.weiv
zig build run -- dev test/examples/kanib/App.weiv
```

Then point it at your own root component:

```bash
zig build run -- dev path/to/App.weiv
```

If you want a static bundle instead of the dev server:

```bash
zig build run -- compile emit app path/to/App.weiv ./dist
cd ./dist
bun server.ts
```

## NPM Package

`weivjs` is now published with:

- CLI command: `weiv`
- bundler adapters: `weivjs/vite`, `weivjs/bun`
- optional typings: `weiv:observable`, `weiv:router`

See packaging details in [NPM Single-Package Distribution](./docs/npm-single-package-distribution.md).

## Learn More

- [Docs Index](./docs/README.md)
- [Framework Vision](./docs/framework-vision.md)
- [Current Architecture](./docs/architecture.md)
- [Current Status](./docs/status.md)
- [Next Stage Priorities](./docs/next-stage-priorities.md)

## Contributor Commands

```bash
zig build test
zig build component-test
zig build runtime-test
zig build test-all
npm run test:package
```
