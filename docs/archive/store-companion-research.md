# Shared-State Companion Research

## Purpose

This document evaluates likely directions for the first officially supported
shared-state companion around `weiv`.

It exists before any final commitment to:

- a custom `@weiv/store`
- an officially supported third-party state library

The goal is not to chase the most fashionable state library. The goal is to
find the option that best fits Weiv's product stance:

- local component state first
- shared state only when genuinely required
- correctness before cleverness
- inspectability over hidden magic

## Evaluation Criteria

The main criteria are:

1. Production usability for object-heavy app state
- nested object updates should not become awkward immediately
- realistic shared app state should feel natural enough to use

2. Compatibility with Weiv's core identity
- Weiv core should stay plain-state-first
- the companion should remain optional
- the companion should not redefine normal `.weiv` authoring

3. Boundary honesty
- update ownership should remain explainable
- external subscriptions and async reactions should not be disguised as
  compiler-known behavior

4. Inspectability
- we should still be able to explain why updates happen
- the shared-state answer should not turn the framework into a black box

5. Implementation leverage
- the path should help the larger flagship verification app soon
- it should not require inventing a broad ecosystem before we validate the need

## Candidate 1: Custom Tiny `@weiv/store`

The first draft direction was:

- `store(initial)`
- `store(() => derivedValue)`
- `.value`
- `subscribe(listener)`

Strengths:

- tiny API
- explicit and easy to document
- easy AST recognition
- easy to keep clearly optional

Weaknesses:

- object-heavy state quickly becomes awkward if updates require repeated shallow
  replacement
- excluding deep object ergonomics makes it feel underpowered for realistic
  production shared state
- adding enough helpers to fix that may slowly reinvent a heavier reactive
  runtime anyway

Current conclusion:

- good as a minimal design exercise
- weak as the immediate official production shared-state answer unless we invest
  much more in ergonomics

## Candidate 2: Nano Stores

Nano Stores is a strong small-library baseline:

- tiny vanilla store core
- `atom(initial)`
- `computed(...)`
- `get()` / `set(...)`
- `subscribe(...)` and `listen(...)`

Relevant docs:

- https://github.com/nanostores/nanostores

Why it is attractive:

- small
- explicit
- framework-agnostic
- easy to understand

Why it is probably not the final official answer:

- still mostly a small-store world
- does not obviously solve the ergonomic objection for nested object-heavy
  production state
- the API shape is fine, but the capability ceiling still looks closer to
  "light shared state" than "official companion for serious shared app state"

Current conclusion:

- excellent baseline comparator
- good reference for "how small can the companion stay"
- probably not enough alone if production object-state ergonomics are a hard
  requirement

## Candidate 3: MobX

MobX is the strongest serious candidate so far.

Relevant docs:

- observable state: https://mobx.js.org/observable-state.html
- computed values: https://mobx.js.org/computeds.html
- actions: https://mobx.js.org/actions.html
- reactions: https://mobx.js.org/reactions.html
- configuration: https://mobx.js.org/configuration.html
- reactivity analysis: https://mobx.js.org/analyzing-reactivity.html

What MobX gives us:

- observable objects, arrays, maps, and sets
- derived values through `computed`
- explicit mutation boundaries through `action`
- reactions through `autorun`, `reaction`, and `when`
- runtime strictness options such as `enforceActions`
- built-in debugging / tracing facilities

Why it fits the current concern:

- object-heavy shared state is first-class
- nested mutation ergonomics are much better than a tiny shallow store
- it is proven as a production-capable shared-state model

Why it is not an automatic yes:

- it brings a substantial runtime reactivity model of its own
- Weiv would need to support it honestly as an optional companion rather than
  pretending those updates are compiler-native
- the mental model is larger than a tiny explicit store

Current conclusion:

- best candidate if production-grade shared object state is the priority
- likely better than rushing a weak custom `@weiv/store`

## Candidate 4: Proxy-First Deep Reactivity Libraries

Examples include Valtio and Vue's reactivity primitives.

Relevant docs:

- Valtio: https://valtio.dev/
- Vue reactivity core: https://vuejs.org/api/reactivity-core.html

Why they are interesting:

- deep object ergonomics are excellent
- nested mutation feels natural

Why they are a weaker fit for Weiv:

- they lean hard into runtime proxy magic
- they pull the mental model closer to ref/reactive ecosystems
- they are less aligned with Weiv's desire to keep update behavior explicit and
  inspectable

Current conclusion:

- useful comparison points
- not the leading direction for the official companion path

## Comparison Summary

### Tiny custom `@weiv/store`

Best at:

- simplicity
- explicitness
- staying obviously optional

Weakest at:

- production object-state ergonomics

### Nano Stores

Best at:

- small shared-state baseline
- simple vanilla API

Weakest at:

- being a convincing "official serious shared-state answer" by itself

### MobX

Best at:

- production-capable shared object state
- deep observability
- mature derivation and reaction model

Weakest at:

- bigger runtime mental model
- more integration care needed to keep Weiv's boundaries honest

### Proxy-first deep reactivity

Best at:

- deep mutation ergonomics

Weakest at:

- alignment with Weiv's explicit/inspectable product stance

## Weiv-Specific Integration Questions

Before Weiv blesses any shared-state companion, we need clear answers for:

1. What counts as owned enough?
- Weiv event handler mutates shared state
- shared-state reaction updates visible UI elsewhere
- how much of that should Weiv treat as normal owned behavior?

2. What remains external?
- raw subscription / reaction callbacks outside Weiv event boundaries
- async reactions triggered later by the shared-state runtime

3. What do we inspect?
- if a state library owns the dependency graph, Weiv should not fake compiler
  certainty
- inspect output should stay honest about where the compiler stopped and the
  runtime companion took over

4. What do we recommend to users?
- local state by default
- companion shared state only when truly needed
- explicit docs about the trade between compiler-native local state and
  runtime-managed shared state

## Current Recommendation

The strongest current recommendation is:

1. do not finalize the custom `@weiv/store` direction yet
2. research and prototype MobX as the first officially supported shared-state
   companion candidate
3. keep Nano Stores as the small baseline comparator
4. treat proxy-first libraries as reference points, not the first likely
   official path

This does not yet mean:

- "MobX is definitely the official answer"

It means:

- MobX is the most credible next candidate to prototype because it addresses the
  biggest practical objection to the tiny-store direction

## Suggested Next Step

The next concrete step should be a bounded prototype, not more abstract API
design.

Recommended prototype shape:

- keep Weiv local-state-first elsewhere
- add one bounded shared-state area in the future flagship app
- implement that area once with MobX-style shared object state
- verify:
  - correctness
  - async/callback behavior
  - owned vs unowned boundary clarity
  - how honest the inspect/diagnostic story remains

If that prototype feels strong, Weiv can then decide whether to:

- officially support MobX directly
- officially support a thin Weiv integration layer around MobX
- or revisit a custom `@weiv/store` later with better evidence
