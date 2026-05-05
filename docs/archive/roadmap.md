# Weiv Roadmap

## Purpose

This document describes how `weiv` should progress from framework idea to implementation project.

For the concrete phased delivery plan, see [Execution Plan](./execution-plan.md).

## Stage 0: Concept Lock

Complete:

- choose project name
- write framework spec
- define principles
- define MVP boundary
- define non-goals

## Stage 1: Design Narrowing

Next decisions:

- exact `.weiv` file syntax
- template expression grammar
- script model choice:
  - module-based
  - object-literal-based
  - hybrid
- CSS scoping strategy
- compiler pipeline structure

Artifacts to produce:

- syntax examples
- AST outline
- compiler phase outline
- runtime API sketch

## Stage 2: Prototype Implementation

Build only enough to prove the framework feels right:

- parser
- template compiler
- runtime mount/update path
- CLI tooling
- one toy example
- one realistic example

The goal is not completeness.
The goal is to validate ergonomics.

## Stage 3: Tooling Hardening

- diagnostics
- source maps
- TS support
- better error reporting
- example app documentation

## Stage 4: Public Preview

Only after the core authoring experience feels strong:

- publish packages
- document framework philosophy
- publish sample apps
- accept early external feedback

## Explicit Reminder

Do not build all of these at once:

- SSR
- router
- forms stack
- state library
- testing platform
- transitions engine
- server framework

Those are follow-on projects.
