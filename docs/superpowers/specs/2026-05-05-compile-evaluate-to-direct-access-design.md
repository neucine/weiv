# Replace `evaluate()` with compiled direct property access

**Date:** 2026-05-05
**Status:** Approved

## Problem

weiv's codegen emits `evaluate(expression, scope)` for every dynamic template expression. At runtime, `evaluate()` uses `new Function(...names, 'return (${expression})')(...values)` — constructing and invoking a new function on every call. This happens on every update cycle for every interpolation, bound attribute, conditional check, loop iterable, and component prop.

This is the single largest runtime performance bottleneck in the generated code. It also prevents future per-binding dirty checking since expressions are opaque strings at runtime.

## Solution

Replace all `evaluate()` calls with direct inline expressions. The compiler destructures scope bindings at the top of each generated function, then emits the expression text verbatim as JS.

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
| `node_codegen.zig` | Replace all `evaluate()` emissions with inline expressions. Add `emitScopeDestructure` calls. Thread bindings through function signatures. |
| `helpers.zig` | Same replacement in conditional helpers, for-loop helpers, slot fallback helpers, projected slot helpers. Remove `evaluate()` function from prelude. Thread bindings through function signatures. |
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

The binding names come from `ComponentModel.script.bindings` filtered to `template_visible == true`, plus `props` and `emit` which are always present.

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

For-loops add the loop variable to scope via `{ ...scope, ["item"]: currentItem }`. The destructure of `loopScope` naturally includes this variable since it spreads all existing scope keys plus the loop variable.

## Threading bindings to codegen

Currently `node_codegen.zig` and `helpers.zig` functions receive `browser_plan.Document` / `browser_plan.Node` but not binding info. The bindings slice (`[]const BindingRecord`) needs to be passed through:

- `direct_component_js.zig:emitModule` → passes `model.script.bindings` to:
  - `node_codegen.emitCreateFunction`
  - `node_codegen.emitUpdateFunction`
  - `node_codegen.emitDestroyFunction`
  - `helpers.emitConditionalHelpers`
- These propagate to child functions as needed.

Additionally, for-loop nodes need access to their `item_name` for the destructure (already available on `ForLoopNode`).

## What stays in the prelude

After removing `evaluate()`, these helpers remain:

- `replaceBetween` — DOM manipulation for conditionals/slots
- `moveBoundaryBefore` — DOM reordering for for-loop reconciliation
- `cloneScope` — snapshot before event handlers
- `hasScopeChanged` — diff after event handlers

## Future work (not in this change)

**Step 2: Per-binding dirty guards.** With direct property access in place, the compiler can emit per-key comparisons:

```js
if (scope.count !== __prev.count) {
  const __next = String(count ?? "");
  if (refs[2].data !== __next) refs[2].data = __next;
}
```

This is a separate change that builds on the direct access foundation.
