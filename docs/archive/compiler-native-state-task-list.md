# Compiler-Native State Task List

This checklist tracks implementation of
[Compiler-Native State Execution Plan](./compiler-native-state-execution-plan.md).

## Phase 1: State Plan Introspection

- [x] add initial state-plan formatter
- [x] collect update regions from the browser plan
- [x] collect visible binding dependencies for region expressions
- [x] diagnose hidden-state template expressions with no visible dependency
- [x] expose `weiv dump-state-plan <path>`
- [x] add compiler tests for representative state-plan output

## Phase 2: Mutation Detection Without Runtime Scheduling

- [x] detect statement-position assignment mutations
- [x] detect property and index mutations rooted at observable bindings
- [x] detect known mutating `Array`, `Map`, and `Set` methods
- [x] diagnose expression-position mutations until value-preserving transforms
  exist
- [x] print mutation sites in `dump-state-plan`

## Phase 3: Boundary Ownership Analysis

- [x] classify template event handlers as owned
- [x] classify compiler-emitted child event handlers as owned
- [x] classify async functions invoked from owned event handlers as owned
- [x] diagnose visible observable mutations inside unowned callbacks

## Later Phases

- [x] add runtime dirty queue and boundary scheduler
- [x] emit text region update functions
- [x] emit attribute region update functions
- [x] emit conditional region update functions
- [x] emit loop region update functions
- [x] emit child region update functions
- [x] emit slot region update functions
- [x] add selected platform callback rewrites
- [x] polish stale UI diagnostics and debug output
