# Remaining Work

## Purpose

This checklist tracks the highest-value work still needed to move `weiv` from promising prototype toward a stable compiler-first frontend framework.

Items here should stay concrete, testable, and aligned with the current scope guard.

## Immediate

- [x] tighten slot diagnostics and invalid-placement validation
- [x] expand composition verification for nested slots, loops, and conditionals together
- [x] reduce repeated direct browser slot/component codegen patterns

## Compiler And Runtime

- [ ] continue replacing generic browser update patterns with more compiler-emitted patch paths
- [x] harden component boundary updates and teardown behavior
- [x] define and document the stable compiler-native state/scheduling model
- [ ] implement compiler-native state/scheduling execution plan

## Diagnostics And Inspectability

- [x] grow the diagnostics catalog for common authoring mistakes
- [x] improve source-located compiler error coverage
- [ ] prefer behavioral verification where string-shape assertions are too brittle

## Tooling

- [ ] strengthen `weiv dev` watch/rebuild ergonomics
- [x] improve CLI-facing compiler diagnostics output
- [x] add more inspectable debug hooks for emitted output

## Verification

- [ ] keep TodoMVC as the main forcing-function verification app
- [ ] add more direct-browser interaction coverage for composition-heavy cases
- [ ] add more compiler-level tests for direct browser codegen contracts
