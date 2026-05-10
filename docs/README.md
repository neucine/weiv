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
- [Runtime README](../src/runtime/README.md): observable and router API reference.
- [Plan](./plan.md): next implementation work from the current architecture.
- [Shared Observable State Design](./shared-observable-state-design.md): active
  next-direction for cross-component/shared state using explicit
  `observable()` state at the source.
- [Shared Observable Weiv Integration Contract](./shared-observable-weiv-integration-contract.md):
  minimum bridge between the standalone observable runtime and future `.weiv`
  component integration.
- [Testing Strategy](./testing-strategy.md): testing layers, current coverage gap, and the larger verification-app direction.
- [Testing Implementation Plan](./testing-implementation-plan.md): concrete rollout plan for the larger flagship verification app.
- [Testing Capability Matrix](./testing-capability-matrix.md): required Weiv feature coverage for the flagship verification app.

Historical design notes and superseded plans live in [archive](./archive/).

The active docs should describe what is true now. If a document is mainly
background, research, or an older implementation plan, keep it in the archive.
