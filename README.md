<p align="center">
  <img src="./docs/assets/weiv.svg" alt="weiv" width="120" />
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

## Status

Runnable today, still early.

## Quick Start

Try the included examples first:

```bash
weiv dev test/examples/todomvc/App.weiv
weiv dev test/examples/workspace-app/App.weiv
```

Then point it at your own root component:

```bash
weiv dev path/to/App.weiv
```

If you want a static bundle instead of the dev server:

```bash
weiv compile path/to/App.weiv ./dist
```

## Learn More

- [Docs Index](./docs/README.md)
- [Framework Vision](./docs/framework-vision.md)
- [Current Architecture](./docs/architecture.md)
- [Current Status](./docs/status.md)

## Contributor Commands

```bash
bun test test/component
bun test test/runtime
```
