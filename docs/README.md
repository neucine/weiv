# Weiv Docs

This directory keeps only the current project map at the top level.

Active docs:

- [Framework Vision](./framework-vision.md): stable product goals, default
  authoring philosophy, and long-term constraints.
- [Architecture](./architecture.md): current compiler, runtime, state, and composition architecture.
- [Runtime Scheduling](./runtime-scheduling.md): current mutation, flush, microtask, subscription, and update timing model.
- [Terminology](./terminology.md): normalized vocabulary for Weiv's compiler-native UI model.
- [Status](./status.md): what works now, verification state, and known caveats.
  Includes the router feature summary.
- [Next Stage Priorities](./next-stage-priorities.md): current milestone priorities and sequencing.
- [NPM Single-Package Distribution](./npm-single-package-distribution.md): current packaging/publish model for `weivjs`.
- [VS Code Publish](./vscode-publish.md): packaging and publish flow for the VS Code extension.
- [UI Library Direction](./ui-library-direction.md): split architecture for headless core plus tokenized theme package.
- [Runtime README](../packages/weiv/src/runtime/README.md): observable and router API reference.
- [Testing Strategy](./testing-strategy.md): testing layers, current coverage gap, and the larger verification-app direction.
- [Testing Capability Matrix](./testing-capability-matrix.md): required Weiv feature coverage for the flagship verification app.

Historical design notes and superseded plans live in [archive](./archive/).

The active docs should describe what is true now. If a document is mainly
background, research, or an older implementation plan, keep it in the archive.
