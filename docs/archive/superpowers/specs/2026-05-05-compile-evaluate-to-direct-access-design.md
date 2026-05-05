# Replace `evaluate()` with compiled direct property access

**Date:** 2026-05-05
**Status:** Approved

## Problem

weiv's codegen emits `evaluate(expression, scope)` for every dynamic template expression. At runtime, `evaluate()` uses `new Function(...names, 'return (${expression})')(...values)` — constructing and invoking a new function on every call. This happens on every update cycle for every interpolation, bound attribute, conditional check, loop iterable, and component prop.

This is the single largest runtime performance bottleneck in the generated code. It also prevents future per-binding dirty checking since expressions are opaque strings at runtime.

## Solution

Replace all `evaluate()` calls with direct inline expressions. The compiler destructures scope bindings at the top of each generated function, then emits the expression text verbatim as JS.

This should be done as a staged emitter change, not as a single "rip out evaluate everywhere" pass:

1. First, replace `evaluate()` in update-path expressions where the surrounding scope is already explicit and stable.
2. Then, once that is proven in the direct-browser harness, replace helper-path and event-handler usages.

The immediate goal is to remove the hot-path `new Function(...)` cost from direct DOM updates. Event handler resolution is still worth cleaning up, but it is a secondary win compared to update-path expression evaluation.

### Before

```js
function updateDom(instance) {
  const refs = instance.refs;
  const scope = instance.refresh();
  const __next_text_0 = String(evaluate("props.title", scope) ?? "");
  if (refs[0].data !== __next_text_0) {
    refs[0].data = __next_text_0;
  }
  const __value_6_disabled = evaluate("count >= limit", scope);
  // ...
}
```

### After

```js
function updateDom(instance) {
  const refs = instance.refs;
  const scope = instance.refresh();
  const { props, count, limit, doubled, increment } = scope;
  const __next_text_0 = String(props.title ?? "");
  if (refs[0].data !== __next_text_0) {
    refs[0].data = __next_text_0;
  }
  const __value_6_disabled = count >= limit;
  // ...
}
```

## Scope of changes

### Files modified

| File | Change |
|------|--------|
| `node_codegen.zig` | Replace update-path `evaluate()` emissions with inline expressions. Add `emitScopeDestructure` calls. Thread bindings through function signatures. |
| `helpers.zig` | Replace helper-path `evaluate()` emissions after update-path coverage is green. Remove `evaluate()` from prelude only after all direct-browser call sites are gone. |
| `direct_component_js.zig` | Pass `model.script.bindings` to codegen functions that need it. |

### Files NOT modified

- IR types (`ir.zig`), browser plan types (`types.zig`), lowerer — expressions stay as raw strings throughout the pipeline.
- `setup.zig` — `__weiv_refresh()` still builds the scope object the same way.
- `cloneScope` / `hasScopeChanged` in helpers prelude — still needed for event handler change detection.

## All `evaluate()` call sites

Eight categories, all receiving the same transformation:

### 1. Text interpolation update (`node_codegen.zig:emitUpdateNode`)

```js
// Before:
const __next_text_0 = String(evaluate("count", scope) ?? "");
// After:
const __next_text_0 = String(count ?? "");
```

### 2. Bound attribute update (`node_codegen.zig:emitBoundAttributeUpdate`)

```js
// Before:
const __value_6_disabled = evaluate("count >= limit", scope);
// After:
const __value_6_disabled = count >= limit;
```

### 3. Event handler resolution (`node_codegen.zig:emitCreateNode`)

```js
// Before:
const resolved = evaluate("increment", instance.refresh());
// After:  destructure from instance.refresh()
const { props, count, limit, doubled, increment } = instance.refresh();
const resolved = increment;
```

Note: event handlers call `instance.refresh()` inline. The destructure must capture the refresh result.

### 4. Conditional check (`helpers.zig:emitSingleConditionalHelper`)

```js
// Before:
const next = Boolean(evaluate("show", scope));
// After:
const next = Boolean(show);
```

### 5. For-loop iterable (`helpers.zig:emitKeyedComponentLoopHelper`, `emitKeyedGenericLoopHelper`)

```js
// Before:
const iterable = evaluate("items", scope) ?? [];
// After:
const iterable = items ?? [];
```

### 6. Component props object (`node_codegen.zig:emitPropsObject`)

```js
// Before:
{ "title": evaluate("props.title", scope) }
// After:
{ "title": props.title }
```

### 7. Child event handlers object (`node_codegen.zig:emitChildHandlersObject`)

```js
// Before:
const resolved = evaluate("handler", scope);
// After:
const resolved = handler;
```

### 8. Nested scope contexts (slot fallbacks, for-loop entries)

Same transformation as above, but destructure from the appropriate scope variable (`loopScope` for for-loop body, `scope` for slot fallbacks).

## Scope destructuring

A new helper `emitScopeDestructure` emits one line at the top of each scope-using function:

```js
const { props, emit, count, limit, doubled, increment } = scope;
```

The destructured names come from two sources:

1. `ComponentModel.script.bindings` filtered to `template_visible == true`, plus `props` and `emit` which are always present.
2. Context-local names introduced by the emitter itself, such as a `for` loop item variable.

That means destructuring cannot be driven by the script bindings slice alone.

### Where destructuring is emitted

| Generated function | Destructure from |
|---|---|
| `createDom` | `instance.refresh()` (for event handlers only — emitted per event handler) |
| `updateDom` | `scope` (already `instance.refresh()`) |
| `createConditionalFragment_N` | `scope` parameter |
| `updateConditional_N` | `scope` parameter |
| `createForEntry_N` / `createForComponentEntry_N` | `loopScope` (includes loop variable) |
| `updateForLoop_N` | `scope` parameter (top-level), `loopScope` (inside loop body) |
| `createSlotFallbackFragment_N` | `scope` parameter |
| `mountProjectedSlot_N_M` | `instance.refresh()` |

### For-loop variable injection

For-loops add the loop variable to scope via `{ ...scope, ["item"]: currentItem }`, but that alone is not enough. The emitter must also explicitly destructure the loop variable name.

For example:

```js
const loopScope = { ...scope, ["item"]: currentItem };
const { props, emit, count, item } = loopScope;
```

The destructure helper therefore needs an `extra_names` or equivalent mechanism for loop-local names.

## Name collision policy

Direct destructuring introduces a correctness risk if user-visible bindings collide with generated locals.

Examples of generated locals already used in direct browser output include:

- `refs`
- `scope`
- `instance`
- `payload`
- `record`
- `start`
- `end`
- `fragment`
- generated `__...` temporaries

The compiler must not emit destructures that redeclare those names in the same JS scope.

For this change, the preferred policy is:

1. Treat `__weiv_*` and `__*` as reserved internal names.
2. Maintain a generated-local denylist for common non-prefixed locals such as `refs`, `scope`, `instance`, `payload`, `record`, `start`, `end`, and `fragment`.
3. If a template-visible binding collides with a reserved/generated local, fail compilation with a clear diagnostic rather than emitting ambiguous JS.

Alias-based destructuring is also viable, but it is a larger follow-up because it requires rewriting raw expression text to match aliases.

## Threading bindings to codegen

Currently `node_codegen.zig` and `helpers.zig` functions receive `browser_plan.Document` / `browser_plan.Node` but not binding info. The bindings slice (`[]const BindingRecord`) needs to be passed through:

- `direct_component_js.zig:emitModule` → passes `model.script.bindings` to:
  - `node_codegen.emitCreateFunction`
  - `node_codegen.emitUpdateFunction`
  - `helpers.emitConditionalHelpers`
- These propagate to child functions as needed.

Additionally, helper call sites that execute within loop-local scopes need access to contextual extra names like `for_loop.item_name`.

## What stays in the prelude

After removing `evaluate()`, these helpers remain:

- `replaceBetween` — DOM manipulation for conditionals/slots
- `moveBoundaryBefore` — DOM reordering for for-loop reconciliation
- `cloneScope` — snapshot before event handlers
- `hasScopeChanged` — diff after event handlers

## Future work (not in this change)

### Verification expectations

This change must be validated primarily through the current direct-browser runtime harness:

- `zig build test`
- `zig build render-test`

Compiler-output assertions are useful, but they are not sufficient on their own for a change this sensitive to runtime JS scope semantics.

### Event handler cleanup as a follow-up phase

Replacing `evaluate()` in event handlers is still desirable, but it is not required for the first milestone if update-path direct access lands cleanly first.

The most important first win is:

- interpolation updates
- bound property/attribute updates
- conditional checks
- loop iterable evaluation
- child prop/slot projection expressions

**Step 2: Per-binding dirty guards.** With direct property access in place, the compiler can emit per-key comparisons:

```js
if (scope.count !== __prev.count) {
  const __next = String(count ?? "");
  if (refs[2].data !== __next) refs[2].data = __next;
}
```

This is a separate change that builds on the direct access foundation.
