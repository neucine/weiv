# Compile evaluate() to Direct Property Access — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all runtime `evaluate()` calls in generated JS with compiled direct property access via scope destructuring.

**Architecture:** The compiler already knows all template-visible bindings from script analysis. Instead of emitting `evaluate("expr", scope)` which constructs a `new Function()` at runtime, emit a destructuring statement `const { binding1, binding2, ... } = scope;` at the top of each generated function, then inline the expression text verbatim. No IR or analysis changes needed — this is purely an emission-layer transformation.

**Tech Stack:** Zig compiler (node_codegen.zig, helpers.zig, direct_component_js.zig, common.zig), e2e tests in e2e_test.zig, Cypress browser tests.

**Spec:** `docs/superpowers/specs/2026-05-05-compile-evaluate-to-direct-access-design.md`

---

### Task 1: Add `emitScopeDestructure` helper to common.zig

**Files:**
- Modify: `src/compiler/emit/browser/direct_component_js/common.zig`

- [ ] **Step 1: Add the emitScopeDestructure function**

Add this function to `common.zig`. It emits a JS destructuring statement from the bindings list:

```zig
const script_analysis = @import("../../../analyze/ts/analysis.zig");
// (already imported)

pub fn emitScopeDestructure(
    bindings: []const script_analysis.BindingRecord,
    scope_expr: []const u8,
    indent: usize,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    var names = std.ArrayList([]const u8){};
    defer names.deinit(allocator);

    // Always include props and emit
    try names.append(allocator, "props");
    try names.append(allocator, "emit");

    for (bindings) |binding| {
        if (!binding.template_visible) continue;
        if (std.mem.eql(u8, binding.kind, "import")) continue;
        // Skip props/emit — already added above
        if (std.mem.eql(u8, binding.name, "props") or std.mem.eql(u8, binding.name, "emit")) continue;
        try names.append(allocator, binding.name);
    }

    try writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "const { ");
    for (names.items, 0..) |name, idx| {
        if (idx > 0) try out.appendSlice(allocator, ", ");
        try out.appendSlice(allocator, name);
    }
    try out.writer(allocator).print(" }} = {s};\n", .{scope_expr});
}
```

- [ ] **Step 2: Run zig build to verify it compiles**

Run: `zig build`
Expected: Compiles with no errors (function is unused at this point).

- [ ] **Step 3: Commit**

```bash
git add src/compiler/emit/browser/direct_component_js/common.zig
git commit -m "feat(codegen): add emitScopeDestructure helper for compiled direct access"
```

---

### Task 2: Replace evaluate() in updateDom — text interpolation and bound attributes

**Files:**
- Modify: `src/compiler/emit/browser/direct_component_js/node_codegen.zig`
- Modify: `src/compiler/emit/browser/direct_component_js.zig`

- [ ] **Step 1: Thread bindings into emitUpdateFunction and emitUpdateNode**

In `direct_component_js.zig`, change the call to `emitUpdateFunction`:

```zig
// In emitModule, change:
try node_codegen.emitUpdateFunction(plan, &out, allocator);
// To:
try node_codegen.emitUpdateFunction(plan, model.script.bindings, &out, allocator);
```

In `node_codegen.zig`, update the `emitUpdateFunction` signature and add a destructure:

```zig
pub fn emitUpdateFunction(
    plan: browser_plan.Document,
    bindings: []const script_analysis.BindingRecord,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator,
        \\function updateDom(instance) {
        \\  const refs = instance.refs;
        \\  const scope = instance.refresh();
        \\
    );
    try common.emitScopeDestructure(bindings, "scope", 1, out, allocator);
    for (plan.nodes) |node| {
        try emitUpdateNode(node, out, allocator, 1, "scope", "refs");
    }
    try out.appendSlice(allocator,
        \\}
        \\
    );
}
```

Add the import at the top of `node_codegen.zig`:

```zig
const script_analysis = @import("../../../analyze/ts/analysis.zig");
```

- [ ] **Step 2: Replace evaluate() in text interpolation (emitUpdateNode .interpolation)**

Change the interpolation branch in `emitUpdateNode` from:

```zig
try out.writer(allocator).print("const __next_text_{d} = String(evaluate(", .{interp.ref_id});
try common.emitString(interp.expression, out, allocator);
try out.writer(allocator).print(", {s}) ?? \"\");\n", .{scope_expr});
```

To:

```zig
try out.writer(allocator).print("const __next_text_{d} = String(({s}) ?? \"\");\n", .{ interp.ref_id, interp.expression });
```

- [ ] **Step 3: Replace evaluate() in bound attribute updates (emitBoundAttributeUpdate)**

There are three `evaluate(` patterns in `emitBoundAttributeUpdate`. Replace each one.

For the boolean attributes (checked/disabled/selected) branch, change:

```zig
try out.writer(allocator).print("const __value_{d}_{s} = evaluate(", .{ ref_id, suffix });
try common.emitString(expression, out, allocator);
try out.writer(allocator).print(", {s});\n", .{scope_expr});
```

To:

```zig
try out.writer(allocator).print("const __value_{d}_{s} = ({s});\n", .{ ref_id, suffix, expression });
```

Apply the same pattern for the `value` attribute branch (line 640) and the generic attribute branch (line 679). All three follow the identical replacement: `evaluate(<quoted-expr>, <scope>)` becomes `(<expr>)`.

- [ ] **Step 4: Replace evaluate() in emitPropsObject**

Change:

```zig
try out.writer(allocator).print("\"{s}\": evaluate(", .{bind_dir.target_name});
try common.emitString(bind_dir.expression, out, allocator);
try out.writer(allocator).print(", {s})", .{scope_expr});
```

To:

```zig
try out.writer(allocator).print("\"{s}\": ({s})", .{ bind_dir.target_name, bind_dir.expression });
```

Remove the `scope_expr` parameter from `emitPropsObject` since it's no longer needed. Update all call sites (there are 4: in `emitCreateNode` component branch, `emitUpdateNode` component branch, and both keyed loop helpers in `helpers.zig`).

- [ ] **Step 5: Run tests to verify**

Run: `zig build test`
Expected: All 45 tests pass. The `__value_` and `__next_` variable names stay the same — only the evaluate() wrapper is removed.

- [ ] **Step 6: Commit**

```bash
git add src/compiler/emit/browser/direct_component_js/node_codegen.zig src/compiler/emit/browser/direct_component_js.zig
git commit -m "feat(codegen): replace evaluate() with direct expressions in updateDom and props"
```

---

### Task 3: Replace evaluate() in event handlers (createDom and emitChildHandlersObject)

**Files:**
- Modify: `src/compiler/emit/browser/direct_component_js/node_codegen.zig`
- Modify: `src/compiler/emit/browser/direct_component_js.zig`

- [ ] **Step 1: Thread bindings into emitCreateFunction and emitCreateNode**

In `direct_component_js.zig`, change:

```zig
try node_codegen.emitCreateFunction(plan, scope_id, &out, allocator);
```

To:

```zig
try node_codegen.emitCreateFunction(plan, scope_id, model.script.bindings, &out, allocator);
```

Update `emitCreateFunction` signature to accept bindings and pass them to `emitCreateNode`:

```zig
pub fn emitCreateFunction(
    plan: browser_plan.Document,
    scope_id: []const u8,
    bindings: []const script_analysis.BindingRecord,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    // ... existing preamble ...
    for (plan.nodes) |node| {
        try emitCreateNode(node, "fragment", scope_id, bindings, out, allocator, 1, "instance.refresh()", "refs");
    }
    // ... existing postamble ...
}
```

Add `bindings` parameter to `emitCreateNode` and propagate it in recursive calls (element children at line 138, slot outlet fallback).

- [ ] **Step 2: Replace evaluate() in event handler resolution**

In `emitCreateNode`, in the `.element` branch, the event handler code currently emits:

```zig
try out.appendSlice(allocator, "const resolved = evaluate(");
try common.emitString(event_dir.expression, out, allocator);
try out.writer(allocator).print(", {s});\n", .{scope_expr});
```

Replace with a destructure + direct access. The event handler needs its own destructure because it runs asynchronously:

```zig
try common.emitScopeDestructure(bindings, scope_expr, indent + 1, out, allocator);
try out.writer(allocator).print("const resolved = ({s});\n", .{event_dir.expression});
```

Note: the `beforeScope` clone line already uses `instance.refresh()` directly (no evaluate), so it doesn't change.

- [ ] **Step 3: Replace evaluate() in emitChildHandlersObject**

Change:

```zig
try out.writer(allocator).print("\"{s}\": (payload) => {{ const resolved = evaluate(", .{event_dir.event_name});
try common.emitString(event_dir.expression, out, allocator);
try out.writer(allocator).print(", {s}); const beforeScope = cloneScope(instance.refresh()); ...", .{scope_expr});
```

Build the destructure + expression inline in a single print. The arrow function body needs to destructure, resolve the expression, clone scope, call the handler, check for changes, and return:

```zig
try out.writer(allocator).print("\"{s}\": (payload) => {{ ", .{event_dir.event_name});
try common.emitScopeDestructureInline(bindings, scope_expr, out, allocator);
try out.writer(allocator).print(" const resolved = ({s}); const beforeScope = cloneScope(instance.refresh()); let result = undefined; if (typeof resolved === \"function\") {{ result = resolved(payload); }} if (hasScopeChanged(beforeScope, instance.refresh())) {{ instance.update(); }} return result; }}", .{event_dir.expression});
```

Add `emitScopeDestructureInline` to `common.zig` — same as `emitScopeDestructure` but without indent/newline, for use in single-line contexts:

```zig
pub fn emitScopeDestructureInline(
    bindings: []const script_analysis.BindingRecord,
    scope_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    // Same name-collection logic as emitScopeDestructure, but emits:
    // const { name1, name2 } = <scope_expr>;
    // without leading indent or trailing newline
}
```

Thread `bindings` parameter through `emitChildHandlersObject`. Remove `scope_expr` parameter. Update all call sites.

- [ ] **Step 4: Run tests to verify**

Run: `zig build test`
Expected: All 45 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/compiler/emit/browser/direct_component_js/node_codegen.zig src/compiler/emit/browser/direct_component_js.zig
git commit -m "feat(codegen): replace evaluate() with direct expressions in event handlers"
```

---

### Task 4: Replace evaluate() in helpers.zig (conditionals, loops, slots)

**Files:**
- Modify: `src/compiler/emit/browser/direct_component_js/helpers.zig`
- Modify: `src/compiler/emit/browser/direct_component_js.zig`

- [ ] **Step 1: Thread bindings into emitConditionalHelpers**

In `direct_component_js.zig`, change:

```zig
try helpers.emitConditionalHelpers(plan.nodes, scope_id, &out, allocator);
```

To:

```zig
try helpers.emitConditionalHelpers(plan.nodes, scope_id, model.script.bindings, &out, allocator);
```

Update `emitConditionalHelpers` signature to accept and propagate `bindings`:

```zig
pub fn emitConditionalHelpers(
    nodes: []const browser_plan.Node,
    scope_id: []const u8,
    bindings: []const script_analysis.BindingRecord,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
```

Propagate `bindings` to all recursive calls within this function and to `emitSingleConditionalHelper`, `emitSingleForLoopHelper`, `emitSingleSlotFallbackHelper`, `emitProjectedSlotHelpers`.

Add the import at the top of `helpers.zig`:

```zig
const script_analysis = @import("../../../analyze/ts/analysis.zig");
```

- [ ] **Step 2: Replace evaluate() in emitSingleConditionalHelper**

In `updateConditional_N`, the condition check currently emits:

```zig
"function updateConditional_{d}(instance, scope) {{\n  const refs = instance.refs;\n  const next = Boolean(evaluate(",
```

Change to emit a destructure then inline the expression:

```zig
"function updateConditional_{d}(instance, scope) {{\n  const refs = instance.refs;\n",
```

Then after the opening line, emit:

```zig
try common.emitScopeDestructure(bindings, "scope", 1, out, allocator);
```

Then emit the condition inline:

```zig
try out.appendSlice(allocator, "  const next = Boolean(");
try out.appendSlice(allocator, conditional.condition);
try out.appendSlice(allocator, ");\n");
```

Remove the old `emitString` + evaluate pattern for the condition.

Also add `emitScopeDestructure` calls at the top of `createConditionalFragment_N` (destructure from `scope` parameter).

- [ ] **Step 3: Replace evaluate() in for-loop helpers**

In `emitKeyedComponentLoopHelper`, the iterable check emits:

```zig
"function updateForLoop_{d}(instance, scope) {{\n  const refs = instance.refs;\n  const iterable = evaluate(",
```

Replace with destructure + direct access:

```zig
"function updateForLoop_{d}(instance, scope) {{\n  const refs = instance.refs;\n",
```

Then:

```zig
try common.emitScopeDestructure(bindings, "scope", 1, out, allocator);
try out.appendSlice(allocator, "  const iterable = (");
try out.appendSlice(allocator, for_loop.iterable_expr);
try out.appendSlice(allocator, ") ?? [];\n");
```

Apply the same pattern to `emitKeyedGenericLoopHelper`.

For `createForComponentEntry_N` and `createForEntry_N`, add destructure from `loopScope` (which already includes the loop variable via spread).

- [ ] **Step 4: Add destructure to slot fallback and projected slot helpers**

In `emitSingleSlotFallbackHelper`, add destructure from `scope` at the top of the generated function body.

In `emitProjectedSlotHelpers`, add destructure from `instance.refresh()` at the top of `mountProjectedSlot_N_M`, and from `scope` in the `update()` inner function.

- [ ] **Step 5: Run tests to verify**

Run: `zig build test`
Expected: All 45 tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/compiler/emit/browser/direct_component_js/helpers.zig src/compiler/emit/browser/direct_component_js.zig
git commit -m "feat(codegen): replace evaluate() in conditional, loop, and slot helpers"
```

---

### Task 5: Remove evaluate() from prelude and run full verification

**Files:**
- Modify: `src/compiler/emit/browser/direct_component_js/helpers.zig`

- [ ] **Step 1: Remove evaluate() function from emitPrelude**

In `helpers.zig`, `emitPrelude` currently emits the `evaluate()` function definition (lines 8-13 of the multiline string). Remove those lines:

```zig
pub fn emitPrelude(out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try out.appendSlice(allocator,
        \\function replaceBetween(start, end, content) {
```

Keep `replaceBetween`, `moveBoundaryBefore`, `cloneScope`, and `hasScopeChanged` — they're still used.

- [ ] **Step 2: Run zig build test**

Run: `zig build test`
Expected: All 45 tests pass. No test references `evaluate(` in assertions, so removing it from the prelude should not break any tests.

- [ ] **Step 3: Run cypress tests**

Run: `npx cypress run` (or however cypress is invoked in this repo)
Expected: All cypress tests pass. This validates that the generated JS actually works in a browser — the ultimate proof that direct access produces correct runtime behavior.

- [ ] **Step 4: Verify generated output for basic-counter**

Run: `./zig-out/bin/weiv emit-browser-direct-js examples/basic-counter.weiv`

Verify:
- No `evaluate(` calls anywhere in the output
- `updateDom` has `const { props, count, limit, doubled, increment } = scope;` near the top
- Text interpolations use direct expressions: `String(props.title ?? "")`
- Bound attributes use direct expressions: `(count >= limit)`
- Event handler has destructure + `const resolved = (increment);`
- `cloneScope` and `hasScopeChanged` are still present in the prelude

- [ ] **Step 5: Commit**

```bash
git add src/compiler/emit/browser/direct_component_js/helpers.zig
git commit -m "feat(codegen): remove evaluate() from prelude — all expressions now compiled"
```

---

### Task 6: Update e2e test assertions for tighter codegen contract

**Files:**
- Modify: `src/e2e_test.zig`

- [ ] **Step 1: Add assertion for scope destructuring in counter test**

In the test `"basic counter direct browser module emits create/update DOM contract"` (line 209), add:

```zig
try std.testing.expect(std.mem.indexOf(u8, js, "const { props,") != null);
try std.testing.expect(std.mem.indexOf(u8, js, "} = scope;") != null);
```

This asserts that `updateDom` emits the destructuring statement.

- [ ] **Step 2: Add assertion that evaluate() is NOT present**

In the same test, add a negative assertion:

```zig
try std.testing.expect(std.mem.indexOf(u8, js, "function evaluate(") == null);
try std.testing.expect(std.mem.indexOf(u8, js, "evaluate(") == null);
```

- [ ] **Step 3: Run tests**

Run: `zig build test`
Expected: All tests pass including the new assertions.

- [ ] **Step 4: Commit**

```bash
git add src/e2e_test.zig
git commit -m "test: assert compiled direct access contract in e2e tests"
```
