# Weiv Docs

This directory keeps only the current project map at the top level.

Active docs:

- [Architecture](./architecture.md): current compiler, runtime, state, and composition architecture.
- [Runtime Scheduling](./runtime-scheduling.md): current mutation, flush, microtask, subscription, and update timing model.
- [Terminology](./terminology.md): normalized vocabulary for Weiv's compiler-native UI model.
- [Status](./status.md): what works now, verification state, and known caveats.
- [Plan](./plan.md): next implementation work from the current architecture.
- [Testing Strategy](./testing-strategy.md): testing layers, current coverage gap, and the larger verification-app direction.
- [Testing Implementation Plan](./testing-implementation-plan.md): concrete rollout plan for the larger flagship verification app.
- [Proxy State Graph Design](./proxy-state-graph-design.md): consolidated design and current implementation direction for proxy-backed tracked state, including root selection, path tracking, escape diagnostics, compiler/runtime contract, and pipeline alignment.

Historical design notes and superseded plans live in [archive](./archive/).

The active docs should describe what is true now. If a document is mainly
background, research, or an older implementation plan, keep it in the archive.
