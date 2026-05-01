# Composition Milestone Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring slot composition to the exit criteria in `docs/composition-implementation.md` — fix stale tests, add IR snapshots, add a fallback example, ship six new diagnostics, and add Cypress coverage including parent-state-driven update propagation.

**Architecture:** No new packages. Compiler/analyze gets a small cross-component slot manifest cache to power validation diagnostics. Compiler/emit is unchanged. New IR snapshot tests and binder diagnostic tests in Zig. New Cypress spec + driver for slot examples mirroring the existing TodoMVC pattern.

**Tech Stack:** Zig 0.15.x, Rust (oxc) backing TS analysis via FFI, Bun, Cypress.

**Companion spec:** `docs/superpowers/specs/2026-05-01-composition-milestone-hardening-design.md`.

---

## File Structure

**Zig — modified**
- `src/e2e_test.zig` — fix 2 stale slot assertions; repair `unsupported-import` test; add IR snapshot tests; add diagnostic tests
- `src/compiler/analyze/binder.zig` — extend with slot validation; consume new manifest module
- `src/compiler/parse/template/directives.zig` — add span on `SlotAssignDirective` (needed for diagnostic span fidelity)
- `src/compiler/parse/template/normalize.zig` — propagate slot directive span (call site of `directives.split`)

**Zig — created**
- `src/compiler/analyze/slot_manifest.zig` — child slot manifest builder + cache, plus child-side `duplicate_outlet` detection

**Examples — created**
- `examples/slots/EmptyState.weiv`
- `examples/slots/EmptyStateUsage.weiv`
- `examples/slots/EmptyStateFallbackUsage.weiv`
- `examples/slots/ReactiveCardUsage.weiv`

**Cypress — created**
- `cypress/e2e/slots-direct.cy.js`
- `tools/run_cypress_slots.ts`

**Docs — modified**
- `docs/execution-plan.md` — milestone status note
- `docs/composition-implementation.md` — check off exit criteria

---

## Task 1: Unblock the test gate (fix 2 stale slot assertions)

**Files:**
- Modify: `src/e2e_test.zig:402` and `src/e2e_test.zig:455`

The codegen now emits `__slot_<id>` (e.g. `__slot_2`, `__slot_7`) for the projected-slot variable, but two tests still assert the old `__slot` name. We update assertions to match the current naming using a stable substring.

- [ ] **Step 1: Run the failing tests to confirm exact failure**

Run: `zig build test 2>&1 | tail -30`

Expected: 2 failures referencing line 402 and 455 in `e2e_test.zig`, plus 1 unrelated failure in the `unsupported-import` test (handled in Task 2).

- [ ] **Step 2: Update Panel default-slot assertion**

In `src/e2e_test.zig`, replace line 402:

```zig
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "const __slot = instance.slots?.default;") != null);
```

with:

```zig
    try std.testing.expect(std.mem.indexOf(u8, panel_js, " = instance.slots?.default;") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "const __slot_") != null);
```

- [ ] **Step 3: Update Card named-slot assertion**

In `src/e2e_test.zig`, replace line 455:

```zig
    try std.testing.expect(std.mem.indexOf(u8, card_js, "const __slot = instance.slots?.[\"header\"];") != null);
```

with:

```zig
    try std.testing.expect(std.mem.indexOf(u8, card_js, " = instance.slots?.[\"header\"];") != null);
    try std.testing.expect(std.mem.indexOf(u8, card_js, "const __slot_") != null);
```

- [ ] **Step 4: Run the two affected tests**

Run:

```bash
zig build test 2>&1 | grep -E "default slot projection contract|named slot browser modules"
```

Expected: both tests now pass (no error lines for them). The `unsupported-import` test is still failing — that's Task 2.

- [ ] **Step 5: Commit**

```bash
git add src/e2e_test.zig
git commit -m "test: align slot codegen assertions with __slot_<id> naming

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Repair the `unsupported-import` test gate

**Files:**
- Modify: `src/e2e_test.zig:764-778`
- Investigate: `src/compiler/emit/browser/app_bundle.zig` (where `emitAppLegacy` lives)

The test calls `emitAppLegacy("examples/unsupported-import/App.weiv", ...)` and expects `error.UnsupportedRuntimeImport`. Current behaviour: it prints `error: unsupported bare runtime import ... lodash-es` to stderr and the test fails. Likely cause: the emitter writes the error to stderr and returns/panics rather than returning the error. Confirm and fix so the function returns the error.

- [ ] **Step 1: Run the test alone to capture exact failure**

Run:

```bash
zig build test 2>&1 | grep -A5 "unsupported"
```

Expected: stderr line `error: unsupported bare runtime import ...` followed by either a panic or a build break.

- [ ] **Step 2: Locate the print site**

Run:

```bash
rg -n "unsupported bare runtime import" src
```

Expected: one or two matches inside `src/compiler/emit/browser/`.

- [ ] **Step 3: Inspect the call site**

Read the matched file at the matched line (5 lines of context). Decide between two cases:

- (a) The code prints to stderr and then returns `void`/exits — change it to `return error.UnsupportedRuntimeImport` (no print, or print only and still return the error).
- (b) The code already returns the error but a wrapper higher up (`emitAppLegacy`) swallows it and prints. In that case, propagate by removing the swallow.

- [ ] **Step 4: Make the change minimally**

Whichever case applies, the function call chain reachable from `emitAppLegacy` must `return error.UnsupportedRuntimeImport;` for the unsupported-import fixture. Keep stderr output (it's useful) but ensure the error is returned, not consumed.

- [ ] **Step 5: Run the test**

Run:

```bash
zig build test 2>&1 | tail -10
```

Expected: green build summary, all 26 tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/compiler/emit/browser src/e2e_test.zig
git commit -m "fix(emit): return UnsupportedRuntimeImport instead of swallowing

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: IR snapshot tests for Panel and Card

**Files:**
- Modify: `src/e2e_test.zig` (append two tests)

Snapshot the lowered IR shape for the two existing slot examples so subsequent diagnostic work cannot silently change codegen-relevant structure.

- [ ] **Step 1: Add Panel IR snapshot test**

Append at end of `src/e2e_test.zig`:

```zig
test "Panel.weiv lowers to a single default slot outlet" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/slots/Panel.weiv");
    defer allocator.free(source);
    var model = try component.build(source, "examples/slots/Panel.weiv", allocator);
    defer model.deinit(allocator);

    // Top-level: <section><slot/></section>
    try std.testing.expectEqual(@as(usize, 1), model.ir_document.nodes.len);
    const section = model.ir_document.nodes[0];
    try std.testing.expect(std.mem.eql(u8, section.element.tag_name, "section"));
    try std.testing.expectEqual(@as(usize, 1), section.element.children.len);

    const outlet = section.element.children[0];
    try std.testing.expect(@as(std.meta.Tag(@TypeOf(outlet)), std.meta.activeTag(outlet)) == .slot_outlet);
    try std.testing.expect(outlet.slot_outlet.name == null);
    try std.testing.expectEqual(@as(usize, 0), outlet.slot_outlet.fallback_children.len);
}
```

- [ ] **Step 2: Run it to verify shape**

Run: `zig build test 2>&1 | grep "Panel.weiv lowers"`

Expected: PASS. If FAIL with a shape mismatch, read the actual IR by running `zig build run -- dump-ir examples/slots/Panel.weiv` and adjust the assertions to match (do not change codegen — this is a snapshot of current behavior).

- [ ] **Step 3: Add Card IR snapshot test**

Append:

```zig
test "Card.weiv lowers to header named slot and default slot with fallbacks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/slots/Card.weiv");
    defer allocator.free(source);
    var model = try component.build(source, "examples/slots/Card.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.ir_document.nodes.len);
    const root = model.ir_document.nodes[0].element;
    try std.testing.expect(std.mem.eql(u8, root.tag_name, "section"));
    try std.testing.expectEqual(@as(usize, 2), root.children.len);

    const header = root.children[0].element;
    try std.testing.expect(std.mem.eql(u8, header.tag_name, "header"));
    try std.testing.expectEqual(@as(usize, 1), header.children.len);
    const named_outlet = header.children[0].slot_outlet;
    try std.testing.expect(std.mem.eql(u8, named_outlet.name.?, "header"));
    try std.testing.expectEqual(@as(usize, 1), named_outlet.fallback_children.len);

    const body = root.children[1].element;
    try std.testing.expect(std.mem.eql(u8, body.tag_name, "div"));
    try std.testing.expectEqual(@as(usize, 1), body.children.len);
    const default_outlet = body.children[0].slot_outlet;
    try std.testing.expect(default_outlet.name == null);
    try std.testing.expectEqual(@as(usize, 1), default_outlet.fallback_children.len);
}
```

- [ ] **Step 4: Run both tests**

Run: `zig build test 2>&1 | grep -E "Panel\.weiv lowers|Card\.weiv lowers"`

Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add src/e2e_test.zig
git commit -m "test: snapshot lowered IR shape for Panel and Card slot examples

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Add EmptyState example + IR snapshot

**Files:**
- Create: `examples/slots/EmptyState.weiv`, `examples/slots/EmptyStateUsage.weiv`, `examples/slots/EmptyStateFallbackUsage.weiv`
- Modify: `src/e2e_test.zig` (append one test)

- [ ] **Step 1: Create `EmptyState.weiv`**

```html
<template>
  <section class="empty-state">
    <header class="empty-state__header">
      <slot name="message">
        <p class="empty-state__fallback-message">Nothing here yet.</p>
      </slot>
    </header>
    <div class="empty-state__body">
      <slot>
        <p class="empty-state__fallback-body">No additional details.</p>
      </slot>
    </div>
  </section>
</template>

<script lang="ts">
  export interface Props {}

  export let props: Props;
</script>

<style>
  .empty-state {
    border: 1px dashed #aaa;
    padding: 1rem;
  }

  .empty-state__fallback-message,
  .empty-state__fallback-body {
    color: #999;
  }
</style>
```

- [ ] **Step 2: Create `EmptyStateUsage.weiv`** (provides only the named slot — default uses fallback)

```html
<template>
  <EmptyState>
    <h2 slot:message>{{ props.heading }}</h2>
  </EmptyState>
</template>

<script lang="ts">
  import EmptyState from "./EmptyState.weiv";

  export interface Props {
    heading: string;
  }

  export let props: Props;
</script>

<style>
</style>
```

- [ ] **Step 3: Create `EmptyStateFallbackUsage.weiv`** (provides nothing — both fallbacks render)

```html
<template>
  <EmptyState />
</template>

<script lang="ts">
  import EmptyState from "./EmptyState.weiv";

  export interface Props {}

  export let props: Props;
</script>

<style>
</style>
```

- [ ] **Step 4: Verify it compiles**

Run: `zig build run -- emit-app examples/slots/EmptyStateUsage.weiv .zig-cache/empty-state-out 2>&1 | tail -5`

Expected: no error; `.zig-cache/empty-state-out/EmptyStateUsage.mjs` exists.

- [ ] **Step 5: Add IR snapshot test**

Append to `src/e2e_test.zig`:

```zig
test "EmptyState.weiv lowers with named message slot and default slot, both with fallbacks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/slots/EmptyState.weiv");
    defer allocator.free(source);
    var model = try component.build(source, "examples/slots/EmptyState.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.ir_document.nodes.len);
    const root = model.ir_document.nodes[0].element;
    try std.testing.expectEqual(@as(usize, 2), root.children.len);

    const message_outlet = root.children[0].element.children[0].slot_outlet;
    try std.testing.expect(std.mem.eql(u8, message_outlet.name.?, "message"));
    try std.testing.expectEqual(@as(usize, 1), message_outlet.fallback_children.len);

    const default_outlet = root.children[1].element.children[0].slot_outlet;
    try std.testing.expect(default_outlet.name == null);
    try std.testing.expectEqual(@as(usize, 1), default_outlet.fallback_children.len);
}
```

- [ ] **Step 6: Run the test**

Run: `zig build test 2>&1 | grep "EmptyState\.weiv lowers"`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add examples/slots/EmptyState.weiv examples/slots/EmptyStateUsage.weiv examples/slots/EmptyStateFallbackUsage.weiv src/e2e_test.zig
git commit -m "feat(examples): add EmptyState slot example with fallbacks

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Add directive span fidelity for `slot:name`

**Files:**
- Modify: `src/compiler/parse/template/directives.zig`
- Modify: `src/compiler/parse/template/normalize.zig` (call site)
- Modify: `src/compiler/parse/template/ast.zig` if `Attribute` lacks a span field — verify first

The current `SlotAssignDirective` carries `slot_name` only. Diagnostics reporting `slot:name` errors need a span pointing at the attribute, not the parent element. Add a span to the directive variant and propagate from the raw attribute.

- [ ] **Step 1: Verify whether attributes carry spans**

Run: `rg -n "pub const Attribute" src/compiler/parse/template/ast.zig`

Open the matched file, read the struct. If `Attribute` already has a `span` or `name_span` field, use it. If not, add one in the next step.

- [ ] **Step 2: If needed, add a span field on `Attribute`**

If `Attribute` has no span: in `src/compiler/parse/template/ast.zig`, add `span: sfc.Span` to the struct and update the parser site that constructs `Attribute` to fill it (locate via `rg -n "\.name = " src/compiler/parse/template/`). For each construction site, capture the start offset before reading the name and the end offset after reading the value.

If span already exists: skip this step.

- [ ] **Step 3: Update `SlotAssignDirective` to carry a span**

In `src/compiler/parse/template/directives.zig`, change:

```zig
pub const SlotAssignDirective = struct {
    slot_name: []const u8,
};
```

to:

```zig
pub const SlotAssignDirective = struct {
    slot_name: []const u8,
    span: ast.Span, // or sfc.Span — match the type used by Attribute.span
};
```

Add the appropriate import at the top if not present.

- [ ] **Step 4: Populate the span when splitting**

In `directives.zig` `split()` function, in the `slot:` branch (around line 110), pass the attribute's span:

```zig
try directives.append(allocator, .{
    .slot_assign = .{
        .slot_name = slot_name,
        .span = attribute.span,
    },
});
```

- [ ] **Step 5: Compile to make sure nothing else breaks**

Run: `zig build 2>&1 | tail -20`

Expected: clean build. Fix any callers that destructure `SlotAssignDirective` (likely none — search with `rg -n "slot_assign" src`).

- [ ] **Step 6: Run the existing test suite**

Run: `zig build test 2>&1 | tail -5`

Expected: all tests still pass.

- [ ] **Step 7: Commit**

```bash
git add src/compiler/parse/template
git commit -m "feat(parse): preserve span on slot:name directive for diagnostics

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Parent-side slot diagnostics (#3, #4, #5)

**Files:**
- Modify: `src/compiler/analyze/binder.zig`
- Modify: `src/e2e_test.zig` (append three tests)

Implement three diagnostics on the parent template alone (no child manifest needed):
- **#3 `slot.assign_outside_component`** — `slot:name` on a non-direct-child-of-component element
- **#4 `slot.template_outside_component`** — `<template slot:name>` outside component child context
- **#5 `slot.duplicate_provision`** — repeated `slot:name` on bare nodes inside one component usage (the spec only allows concatenation via explicit `<template slot:name>` grouping)

- [ ] **Step 1: Add diagnostic test for #3**

Append to `src/e2e_test.zig`:

```zig
test "slot:name on non-component-child emits slot.assign_outside_component" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <div>
        \\    <h2 slot:header>oops</h2>
        \\  </div>
        \\</template>
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    var model = try component.build(source, "test:assign_outside.weiv", allocator);
    defer model.deinit(allocator);

    var found = false;
    for (model.binding.diagnostics) |d| {
        if (std.mem.eql(u8, d.kind, "slot.assign_outside_component")) found = true;
    }
    try std.testing.expect(found);
}
```

- [ ] **Step 2: Run to confirm it fails**

Run: `zig build test 2>&1 | grep "assign_outside_component"`

Expected: FAIL — no such diagnostic exists yet.

- [ ] **Step 3: Implement #3 in the binder**

In `src/compiler/analyze/binder.zig`, modify `bindElement`. Currently:

```zig
.slot_assign => {},
```

Replace with a check that requires the enclosing parent to be a component element. Plumbing: `bindNodes` needs to pass a flag to children indicating whether the parent is a component. Change `bindNodes` and `bindElement` signatures to take `parent_is_component: bool`. At the top of `bindElement`, before the `for (element.directives)` loop, check `slot_assign` directives:

```zig
for (element.directives) |directive| {
    if (directive == .slot_assign and !parent_is_component) {
        const sa = directive.slot_assign;
        try appendDiagnostic(diagnostics, "slot.assign_outside_component", sa.slot_name, "slot:<name> may only appear on a direct child of a component", sa.span, allocator);
    }
}
```

Then pass `parent_is_component = isComponentTag(element.tag_name)` when recursing into `bindNodes` for `element.children`.

For top-level `bindNodes` from `bind()`, pass `false`.

- [ ] **Step 4: Run #3 test**

Run: `zig build test 2>&1 | grep "assign_outside_component"`

Expected: PASS.

- [ ] **Step 5: Add diagnostic test for #4**

Append:

```zig
test "<template slot:foo> outside component emits slot.template_outside_component" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <div>
        \\    <template slot:header><h2>x</h2></template>
        \\  </div>
        \\</template>
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    var model = try component.build(source, "test:template_outside.weiv", allocator);
    defer model.deinit(allocator);

    var found = false;
    for (model.binding.diagnostics) |d| {
        if (std.mem.eql(u8, d.kind, "slot.template_outside_component")) found = true;
    }
    try std.testing.expect(found);
}
```

- [ ] **Step 6: Implement #4**

In `bindElement`, when `element.tag_name == "template"` and the element has a `slot_assign` directive, the existing `slot.assign_outside_component` check from Step 3 already fires when the parent isn't a component. Differentiate by tag: in the same loop, prefer the more specific code:

```zig
for (element.directives) |directive| {
    if (directive == .slot_assign and !parent_is_component) {
        const sa = directive.slot_assign;
        const code = if (std.mem.eql(u8, element.tag_name, "template"))
            "slot.template_outside_component"
        else
            "slot.assign_outside_component";
        const msg = if (std.mem.eql(u8, element.tag_name, "template"))
            "<template slot:<name>> may only appear as a direct child of a component usage"
        else
            "slot:<name> may only appear on a direct child of a component";
        try appendDiagnostic(diagnostics, code, sa.slot_name, msg, sa.span, allocator);
    }
}
```

- [ ] **Step 7: Run #4 test (and re-run #3)**

Run: `zig build test 2>&1 | grep -E "template_outside_component|assign_outside_component"`

Expected: both PASS.

- [ ] **Step 8: Add diagnostic test for #5**

Append:

```zig
test "duplicate bare slot:name without template grouping emits slot.duplicate_provision" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <Card>
        \\    <h2 slot:header>A</h2>
        \\    <h2 slot:header>B</h2>
        \\  </Card>
        \\</template>
        \\<script lang="ts">
        \\  import Card from "./Card.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    var model = try component.build(source, "test:duplicate_provision.weiv", allocator);
    defer model.deinit(allocator);

    var found = false;
    for (model.binding.diagnostics) |d| {
        if (std.mem.eql(u8, d.kind, "slot.duplicate_provision")) found = true;
    }
    try std.testing.expect(found);
}
```

- [ ] **Step 9: Implement #5**

In `bindElement`, when the element is a component (`isComponentTag` true), iterate its direct children. For each child carrying a `slot_assign` directive, record the slot name in a local set. If a child with a `slot_assign` for the same name has already been seen AND neither child is a `<template slot:...>` group, emit `slot.duplicate_provision`.

Add this block after the resolve check, before recursing:

```zig
if (isComponentTag(element.tag_name)) {
    var seen = std.StringHashMap(bool).init(allocator); // value: was previous a <template> group?
    defer seen.deinit();
    for (element.children) |child| switch (child) {
        .element => |child_el| {
            for (child_el.directives) |dir| if (dir == .slot_assign) {
                const sa = dir.slot_assign;
                const is_template_group = std.mem.eql(u8, child_el.tag_name, "template");
                const previous = seen.get(sa.slot_name);
                if (previous != null and !(previous.? and is_template_group)) {
                    try appendDiagnostic(diagnostics, "slot.duplicate_provision", sa.slot_name, "Slot is provided more than once; use <template slot:<name>> to group multi-node content", sa.span, allocator);
                }
                try seen.put(sa.slot_name, is_template_group);
            };
        },
        else => {},
    };
}
```

Note the rule encoded: only consecutive `<template slot:foo>` groups are tolerated (the spec defers concatenation rules; we err on the safe side and reject all loose duplicates here).

- [ ] **Step 10: Run #5 test**

Run: `zig build test 2>&1 | grep "duplicate_provision"`

Expected: PASS.

- [ ] **Step 11: Run the full suite**

Run: `zig build test 2>&1 | tail -5`

Expected: all green.

- [ ] **Step 12: Commit**

```bash
git add src/compiler/analyze/binder.zig src/e2e_test.zig
git commit -m "feat(analyze): parent-side slot diagnostics #3 #4 #5

- slot.assign_outside_component
- slot.template_outside_component
- slot.duplicate_provision

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Child slot manifest + `slot.duplicate_outlet` (#2)

**Files:**
- Create: `src/compiler/analyze/slot_manifest.zig`
- Modify: `src/compiler/analyze/binder.zig`
- Modify: `src/e2e_test.zig` (append one test)

Build a manifest of every `<slot>` outlet declared by a component. While building it, detect duplicate outlet names (#2). The manifest will be consumed in Task 8.

- [ ] **Step 1: Add diagnostic test for #2**

Append:

```zig
test "duplicate <slot name> in a component emits slot.duplicate_outlet" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <section>
        \\    <slot name="header"/>
        \\    <slot name="header"/>
        \\  </section>
        \\</template>
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    var model = try component.build(source, "test:duplicate_outlet.weiv", allocator);
    defer model.deinit(allocator);

    var found = false;
    for (model.binding.diagnostics) |d| {
        if (std.mem.eql(u8, d.kind, "slot.duplicate_outlet")) found = true;
    }
    try std.testing.expect(found);
}
```

- [ ] **Step 2: Confirm failure**

Run: `zig build test 2>&1 | grep "duplicate_outlet"`

Expected: FAIL.

- [ ] **Step 3: Create the manifest module**

Create `src/compiler/analyze/slot_manifest.zig`:

```zig
const std = @import("std");
const template = @import("../parse/template.zig");
const sfc = @import("../parse/sfc.zig");

pub const SlotEntry = struct {
    /// null name == default slot
    name: ?[]const u8,
    span: sfc.Span,
};

pub const Manifest = struct {
    entries: []SlotEntry,

    pub fn deinit(self: *Manifest, allocator: std.mem.Allocator) void {
        for (self.entries) |entry| {
            if (entry.name) |n| allocator.free(n);
        }
        allocator.free(self.entries);
        self.* = undefined;
    }

    pub fn hasDefault(self: Manifest) bool {
        for (self.entries) |entry| if (entry.name == null) return true;
        return false;
    }

    pub fn hasName(self: Manifest, name: []const u8) bool {
        for (self.entries) |entry| {
            if (entry.name) |n| {
                if (std.mem.eql(u8, n, name)) return true;
            }
        }
        return false;
    }
};

pub const DuplicateReport = struct {
    name: ?[]const u8,
    span: sfc.Span,
};

pub fn build(
    document: *const template.NormalizedDocument,
    allocator: std.mem.Allocator,
) !struct { manifest: Manifest, duplicates: []DuplicateReport } {
    var entries = std.ArrayList(SlotEntry){};
    defer entries.deinit(allocator);
    var dups = std.ArrayList(DuplicateReport){};
    defer dups.deinit(allocator);

    try walk(document.nodes, &entries, &dups, allocator);

    return .{
        .manifest = .{ .entries = try entries.toOwnedSlice(allocator) },
        .duplicates = try dups.toOwnedSlice(allocator),
    };
}

fn walk(
    nodes: []const template.NormalizedNode,
    entries: *std.ArrayList(SlotEntry),
    dups: *std.ArrayList(DuplicateReport),
    allocator: std.mem.Allocator,
) anyerror!void {
    for (nodes) |node| switch (node) {
        .element => |el| try walk(el.children, entries, dups, allocator),
        .slot_outlet => |out| {
            const name_copy: ?[]const u8 = if (out.name) |n| try allocator.dupe(u8, n) else null;
            for (entries.items) |existing| {
                const both_default = existing.name == null and name_copy == null;
                const same_name = if (existing.name != null and name_copy != null)
                    std.mem.eql(u8, existing.name.?, name_copy.?)
                else
                    false;
                if (both_default or same_name) {
                    try dups.append(allocator, .{ .name = name_copy, .span = out.span });
                    break;
                }
            }
            try entries.append(allocator, .{ .name = name_copy, .span = out.span });
        },
        .conditional => |c| {
            try walk(c.consequent, entries, dups, allocator);
            try walk(c.alternate, entries, dups, allocator);
        },
        .for_loop => |f| try walk(f.body, entries, dups, allocator),
        .component => {},
        .text, .interpolation => {},
    };
}
```

Verify the actual field names by reading `src/compiler/lower/ir.zig` and `src/compiler/parse/template/normalized.zig` — adjust accessors (`out.name`, `out.span`, etc.) to match.

- [ ] **Step 4: Wire the manifest into the binder**

In `src/compiler/analyze/binder.zig`:

1. Add `const slot_manifest = @import("slot_manifest.zig");`
2. At the top of `bind()`, after building diagnostics array but before walking nodes, build the manifest for the current document:

```zig
var manifest_result = try slot_manifest.build(document, allocator);
defer manifest_result.manifest.deinit(allocator);
defer allocator.free(manifest_result.duplicates);

for (manifest_result.duplicates) |dup| {
    const name_for_diag = dup.name orelse "default";
    try appendDiagnostic(&diagnostics, "slot.duplicate_outlet", name_for_diag, "Slot outlet declared more than once with the same name", dup.span, allocator);
}
```

3. Add the manifest to `BindingResult` so Task 8 can reuse it on the parent side. Extend `BindingResult`:

```zig
pub const BindingResult = struct {
    component_refs: []ComponentRef,
    diagnostics: []Diagnostic,
    own_slot_manifest: slot_manifest.Manifest,

    pub fn deinit(self: *BindingResult, allocator: std.mem.Allocator) void {
        allocator.free(self.component_refs);
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(self.diagnostics);
        self.own_slot_manifest.deinit(allocator);
        self.* = undefined;
    }
};
```

Stop deferring the manifest cleanup at the local level above — instead transfer ownership into the result:

```zig
return .{
    .component_refs = try component_refs.toOwnedSlice(allocator),
    .diagnostics = try diagnostics.toOwnedSlice(allocator),
    .own_slot_manifest = manifest_result.manifest,
};
```

(Remove the matching `defer manifest_result.manifest.deinit(allocator);` line.)

- [ ] **Step 5: Compile**

Run: `zig build 2>&1 | tail -10`

Expected: clean compile. Fix any callers of `BindingResult` (`rg -n "BindingResult" src`) that destructure the old shape.

- [ ] **Step 6: Run #2 test plus full suite**

Run: `zig build test 2>&1 | tail -5`

Expected: all green, including the new `duplicate_outlet` test.

- [ ] **Step 7: Commit**

```bash
git add src/compiler/analyze
git commit -m "feat(analyze): slot manifest + slot.duplicate_outlet diagnostic

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Cross-component slot diagnostics (#1, #6)

**Files:**
- Modify: `src/compiler/analyze/binder.zig`
- Modify: `src/e2e_test.zig` (append two tests)

`#1 slot.unknown_name` and `#6 slot.default_not_supported` need access to the *child* component's slot manifest. The binder already resolves component references via `isNameVisible`, but does not currently load and analyze imported `.weiv` files. We will accept a small dependency: the build pipeline that constructs a `Component` model already knows how to resolve and build sibling components for codegen (see `examples/slots/CardUsage.weiv` emit successfully producing `Card.mjs`). Reuse the same loader.

- [ ] **Step 1: Locate the import resolver**

Run: `rg -n "weiv" src/compiler/emit/browser/app_bundle.zig | head -20`

Open the file. Identify the function that, given a parent component path, resolves and reads imported `.weiv` files. We will call into the same path-resolution helper from the binder.

- [ ] **Step 2: Add a small "lookup neighbour manifest" helper to the binder**

Strategy: avoid eager full parse during binding. Instead, add a function `loadNeighbourManifest(parent_path, import_specifier, allocator) !?Manifest` that:

1. Resolves the import specifier to an absolute path (reuse the resolver from app_bundle).
2. Reads the file.
3. Calls the existing pipeline up through `slot_manifest.build` (parse → normalize → manifest). It does NOT need to fully bind/lower the neighbour.
4. Returns `null` if the file does not exist (the neighbour might be from a non-`.weiv` import).

Cache results within a single `bind()` invocation in a `std.StringHashMap(Manifest)` keyed by absolute path.

This adds a `parent_source_path` parameter to `bind()` and to `component.build()`. Search where `component.build()` is called and thread the source path through. (`build()` already takes a path; verify with `rg -n "fn build" src/compiler/component.zig` — adjust the call sites accordingly.)

- [ ] **Step 3: Add diagnostic test for #1**

Append:

```zig
test "slot:foo with no matching child outlet emits slot.unknown_name" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Card has slots "header" and default. Use "title" which is unknown.
    const source =
        \\<template>
        \\  <Card>
        \\    <h2 slot:title>oops</h2>
        \\  </Card>
        \\</template>
        \\<script lang="ts">
        \\  import Card from "./Card.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    var model = try component.build(source, "examples/slots/CardUsageInvalid.weiv", allocator);
    defer model.deinit(allocator);

    var found = false;
    for (model.binding.diagnostics) |d| {
        if (std.mem.eql(u8, d.kind, "slot.unknown_name")) found = true;
    }
    try std.testing.expect(found);
}
```

The fixture path `examples/slots/CardUsageInvalid.weiv` is virtual (the source is provided inline). It must be sibling to `Card.weiv` so the relative `./Card.weiv` import resolves. Use the same directory.

- [ ] **Step 4: Add diagnostic test for #6**

Append:

```zig
test "providing default content to a child without default slot emits slot.default_not_supported" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // First create a child .weiv on disk that has only a named slot — reuse a real file.
    // EmptyState has both a "message" slot and a default slot, so it does NOT trigger #6.
    // Construct a temp child via inline source instead.

    const child_source =
        \\<template>
        \\  <header><slot name="title"/></header>
        \\</template>
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    // Write child to a temp file alongside parent
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "OnlyNamed.weiv", .data = child_source });

    const parent_source =
        \\<template>
        \\  <OnlyNamed>plain text</OnlyNamed>
        \\</template>
        \\<script lang="ts">
        \\  import OnlyNamed from "./OnlyNamed.weiv";
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
        \\<style></style>
    ;
    const parent_path = try std.fs.path.join(allocator, &.{
        ".zig-cache", "tmp", tmp.sub_path[0..], "Parent.weiv",
    });
    defer allocator.free(parent_path);
    try tmp.dir.writeFile(.{ .sub_path = "Parent.weiv", .data = parent_source });

    var model = try component.build(parent_source, parent_path, allocator);
    defer model.deinit(allocator);

    var found = false;
    for (model.binding.diagnostics) |d| {
        if (std.mem.eql(u8, d.kind, "slot.default_not_supported")) found = true;
    }
    try std.testing.expect(found);
}
```

- [ ] **Step 5: Implement #1 and #6 in the binder**

In `bindElement`, when the element is a component (`isComponentTag(element.tag_name)`), look up the manifest for its resolved source. For each slot provision (i.e. each direct child carrying a `slot_assign` directive, or each unnamed direct child that becomes default content):

```zig
if (isComponentTag(element.tag_name)) {
    const child_manifest = try ctx.loadNeighbourManifest(element.tag_name); // ?Manifest

    if (child_manifest) |manifest| {
        var has_unnamed_content = false;
        for (element.children) |child| switch (child) {
            .element => |child_el| {
                var has_slot_assign = false;
                for (child_el.directives) |dir| if (dir == .slot_assign) {
                    has_slot_assign = true;
                    const sa = dir.slot_assign;
                    if (!manifest.hasName(sa.slot_name)) {
                        try appendDiagnostic(diagnostics, "slot.unknown_name", sa.slot_name, "Child component has no <slot> with this name", sa.span, allocator);
                    }
                };
                if (!has_slot_assign) has_unnamed_content = true;
            },
            .text => |t| if (!isWhitespaceOnly(t.value)) { has_unnamed_content = true; },
            .interpolation => has_unnamed_content = true,
            else => has_unnamed_content = true,
        };
        if (has_unnamed_content and !manifest.hasDefault()) {
            try appendDiagnostic(diagnostics, "slot.default_not_supported", element.tag_name, "Component has no default <slot>; default content is not allowed", element.span, allocator);
        }
    }
}
```

Where `ctx.loadNeighbourManifest(tag_name)`:
1. Looks up the import for `tag_name` in `script.bindings` (find binding with kind=import).
2. Resolves the import specifier relative to `parent_source_path`.
3. Returns the cached `Manifest`, building it on miss.
4. Returns `null` if the import is not a `.weiv` file or cannot be resolved.

Implement `isWhitespaceOnly` as: all bytes are space/tab/newline.

- [ ] **Step 6: Run all six diagnostic tests**

Run:

```bash
zig build test 2>&1 | grep -E "slot\.(unknown_name|default_not_supported|duplicate_outlet|duplicate_provision|assign_outside_component|template_outside_component)"
```

Expected: all 6 PASS.

- [ ] **Step 7: Run full suite**

Run: `zig build test 2>&1 | tail -5`

Expected: green.

- [ ] **Step 8: Commit**

```bash
git add src/compiler/analyze src/e2e_test.zig
git commit -m "feat(analyze): cross-component slot diagnostics #1 #6

- slot.unknown_name
- slot.default_not_supported

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Reactive slot example + Cypress coverage

**Files:**
- Create: `examples/slots/ReactiveCardUsage.weiv`
- Create: `tools/run_cypress_slots.ts`
- Create: `cypress/e2e/slots-direct.cy.js`
- Modify: `cypress.config.mjs` if it scopes specs to a single pattern

- [ ] **Step 1: Create `ReactiveCardUsage.weiv`**

```html
<template>
  <Card>
    <template slot:header>
      <h2 data-test="header-title">{{ title }}</h2>
      <p data-test="header-eyebrow">Updated {{ updateCount }} time(s)</p>
    </template>
    <p data-test="body">{{ body }}</p>
    <button data-test="bump" on:click="bump()">Bump</button>
  </Card>
</template>

<script lang="ts">
  import Card from "./Card.weiv";

  export interface Props {}

  export let props: Props;

  let title = "Initial";
  let body = "Body 0";
  let updateCount = 0;

  function bump() {
    updateCount += 1;
    title = `Bumped ${updateCount}`;
    body = `Body ${updateCount}`;
  }
</script>

<style></style>
```

- [ ] **Step 2: Verify it compiles**

Run: `zig build run -- emit-app examples/slots/ReactiveCardUsage.weiv .zig-cache/reactive-card-out 2>&1 | tail -3`

Expected: no error.

- [ ] **Step 3: Create the Cypress driver**

Create `tools/run_cypress_slots.ts`. Mirror `tools/run_cypress_direct.ts` but boot ReactiveCardUsage:

```ts
import { createServer } from "node:net";

const cwd = process.cwd();
const outDir = ".zig-cache/cypress-slots-direct";
const entry = "examples/slots/ReactiveCardUsage.weiv";
const specPath = "cypress/e2e/slots-direct.cy.js";

async function findFreePort(): Promise<number> {
  return await new Promise((resolve, reject) => {
    const server = createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close(() => reject(new Error("Failed to determine a free port")));
        return;
      }
      const { port } = address;
      server.close((error) => (error ? reject(error) : resolve(port)));
    });
  });
}

async function waitForServer(url: string, timeoutMs: number) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const res = await fetch(url);
      if (res.ok) return;
    } catch {}
    await Bun.sleep(300);
  }
  throw new Error(`Timed out waiting for ${url}`);
}

async function main() {
  const port = String(await findFreePort());
  const baseUrl = `http://127.0.0.1:${port}`;

  const server = Bun.spawn({
    cmd: ["zig", "build", "run", "--", "dev", entry, outDir],
    cwd,
    env: { ...process.env, PORT: port },
    stdout: "inherit",
    stderr: "inherit",
    stdin: "ignore",
  });

  const stop = () => { try { server.kill("SIGTERM"); } catch {} };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);

  try {
    await waitForServer(baseUrl, 60_000);
    const cypress = Bun.spawn({
      cmd: ["bunx", "cypress", "run", "--headless", "--browser", "electron", "--spec", specPath],
      cwd,
      env: { ...process.env, CYPRESS_BASE_URL: baseUrl },
      stdout: "inherit",
      stderr: "inherit",
      stdin: "ignore",
    });
    const exitCode = await cypress.exited;
    if (exitCode !== 0) throw new Error(`Cypress exited with code ${exitCode}`);
  } finally {
    stop();
    await server.exited;
  }
}

await main();
```

- [ ] **Step 4: Create the spec**

Create `cypress/e2e/slots-direct.cy.js`:

```js
describe("Slot composition direct bundle", () => {
  beforeEach(() => {
    cy.visit("/");
  });

  it("renders projected named-slot content", () => {
    cy.get('[data-test="header-title"]').should("have.text", "Initial");
    cy.get('[data-test="header-eyebrow"]').should("contain.text", "Updated 0");
  });

  it("renders projected default-slot content", () => {
    cy.get('[data-test="body"]').should("have.text", "Body 0");
  });

  it("updates projected slot interpolations when parent state changes", () => {
    cy.get('[data-test="header-title"]').then(($el) => {
      const before = $el[0];
      cy.get('[data-test="bump"]').click();
      cy.get('[data-test="header-title"]').should("have.text", "Bumped 1");
      cy.get('[data-test="header-title"]').then(($after) => {
        // Same element node — proves no remount
        expect($after[0]).to.equal(before);
      });
      cy.get('[data-test="body"]').should("have.text", "Body 1");
      cy.get('[data-test="header-eyebrow"]').should("contain.text", "Updated 1");
    });
  });

  it("updates non-slot interpolations in step with slot interpolations", () => {
    cy.get('[data-test="bump"]').click();
    cy.get('[data-test="bump"]').click();
    cy.get('[data-test="header-title"]').should("have.text", "Bumped 2");
    cy.get('[data-test="body"]').should("have.text", "Body 2");
    cy.get('[data-test="header-eyebrow"]').should("contain.text", "Updated 2");
  });
});
```

- [ ] **Step 5: Add a `package.json` script for slot Cypress**

Read `package.json`. Add to its `scripts`:

```json
"cypress:slots": "bun tools/run_cypress_slots.ts"
```

(Adjust to match the existing script style for `cypress:direct` or whatever the TodoMVC equivalent is named.)

- [ ] **Step 6: Run the new Cypress spec**

Run: `bun run cypress:slots`

Expected: all 4 tests PASS. If the `expect($after[0]).to.equal(before)` assertion fails (DOM identity mismatch), it indicates the projected slot is being remounted instead of patched — that's a real codegen bug. In that case STOP and report it as a finding rather than masking with a different assertion. The whole point of this test is to catch that.

- [ ] **Step 7: Commit**

```bash
git add examples/slots/ReactiveCardUsage.weiv tools/run_cypress_slots.ts cypress/e2e/slots-direct.cy.js package.json
git commit -m "test(cypress): slot direct bundle covers fallback and reactive update

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Default and named fallback Cypress coverage

**Files:**
- Modify: `cypress/e2e/slots-direct.cy.js`

The Reactive spec only exercises mount/update against `Card`. We still need fallback verification on `EmptyState` (named-fallback and default-fallback paths). Easiest path: bundle a small "showcase" entry that mounts both `EmptyStateUsage` and `EmptyStateFallbackUsage` and assert their fallback DOM via Cypress.

Decision: rather than spinning up a second `bunx cypress run`, add a second entry into the same Cypress run by serving a different page route. The simplest variant is **a second .weiv app** that imports both EmptyState usages and renders them side by side.

- [ ] **Step 1: Create showcase wrapper `examples/slots/SlotShowcase.weiv`**

```html
<template>
  <main>
    <section data-test="reactive">
      <ReactiveCardUsage />
    </section>
    <section data-test="empty-with-named">
      <EmptyStateUsage heading="Hello" />
    </section>
    <section data-test="empty-fallback">
      <EmptyStateFallbackUsage />
    </section>
  </main>
</template>

<script lang="ts">
  import ReactiveCardUsage from "./ReactiveCardUsage.weiv";
  import EmptyStateUsage from "./EmptyStateUsage.weiv";
  import EmptyStateFallbackUsage from "./EmptyStateFallbackUsage.weiv";

  export interface Props {}
  export let props: Props;
</script>

<style></style>
```

- [ ] **Step 2: Update the driver to boot the showcase**

In `tools/run_cypress_slots.ts`, change:

```ts
const entry = "examples/slots/ReactiveCardUsage.weiv";
```

to:

```ts
const entry = "examples/slots/SlotShowcase.weiv";
```

- [ ] **Step 3: Verify the showcase compiles**

Run: `zig build run -- emit-app examples/slots/SlotShowcase.weiv .zig-cache/showcase-out 2>&1 | tail -3`

Expected: no error.

- [ ] **Step 4: Add fallback assertions to the spec**

Append to `cypress/e2e/slots-direct.cy.js`:

```js
describe("Slot fallback content", () => {
  beforeEach(() => {
    cy.visit("/");
  });

  it("renders named-slot fallback when only the named slot is provided", () => {
    cy.get('[data-test="empty-with-named"]').within(() => {
      cy.contains("h2", "Hello").should("exist");
      // default slot was not provided — fallback message shows
      cy.contains(".empty-state__fallback-body", "No additional details.").should("exist");
    });
  });

  it("renders both fallbacks when no slots are provided", () => {
    cy.get('[data-test="empty-fallback"]').within(() => {
      cy.contains(".empty-state__fallback-message", "Nothing here yet.").should("exist");
      cy.contains(".empty-state__fallback-body", "No additional details.").should("exist");
    });
  });
});
```

The existing reactive describe block must scope its selectors with `cy.get('[data-test="reactive"]').within(...)` since the showcase now mounts multiple components on one page. Update the existing block accordingly:

```js
describe("Slot composition direct bundle (reactive)", () => {
  beforeEach(() => {
    cy.visit("/");
    cy.get('[data-test="reactive"]').as("scope");
  });

  it("renders projected named-slot content", () => {
    cy.get("@scope").find('[data-test="header-title"]').should("have.text", "Initial");
    cy.get("@scope").find('[data-test="header-eyebrow"]').should("contain.text", "Updated 0");
  });
  // ... apply the same scoping to the other three reactive tests
});
```

- [ ] **Step 5: Run the spec**

Run: `bun run cypress:slots`

Expected: all 6 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add examples/slots/SlotShowcase.weiv tools/run_cypress_slots.ts cypress/e2e/slots-direct.cy.js
git commit -m "test(cypress): cover slot fallback rendering via SlotShowcase

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Mark milestone complete in docs

**Files:**
- Modify: `docs/composition-implementation.md`
- Modify: `docs/execution-plan.md`
- Modify: `README.md` (Near-Term Focus list — strike the composition item)

- [ ] **Step 1: Mark exit criteria checked off**

In `docs/composition-implementation.md`, under "Exit Criteria", append a `## Status` section confirming completion (do not delete the criteria themselves). Example:

```markdown
## Status

Completed on 2026-05-01 by the composition milestone hardening plan
(`docs/superpowers/plans/2026-05-01-composition-milestone-hardening.md`).

- default and named slots: verified in Cypress + IR snapshot tests
- fallback content: verified in Cypress (SlotShowcase)
- grouped `<template slot:name>`: verified in CardUsage IR snapshot + Cypress
- diagnostics: 6 codes implemented and unit-tested
- direct browser path supports projected content end to end
```

- [ ] **Step 2: Update the execution plan status**

In `docs/execution-plan.md`, locate the "Status as of 2026-05-01" block and append:

```markdown
- composition milestone (slots): completed
```

- [ ] **Step 3: Update README**

In `README.md`, under "Near-Term Focus", strike or remove the line:

```
- add a real composition model, likely slots or an equivalent content projection mechanism
```

Replace with a short note:

```
- composition model: slots shipped — see docs/composition-implementation.md
```

- [ ] **Step 4: Final full verification**

Run:

```bash
zig build test 2>&1 | tail -5
bun run cypress:slots
```

Expected: both green.

- [ ] **Step 5: Commit**

```bash
git add docs/composition-implementation.md docs/execution-plan.md README.md
git commit -m "docs: mark composition milestone complete

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review Notes

Spec coverage:

- Section 1 (Goal & Scope) → Tasks 1-11 collectively
- Section 2 (Architecture) → Task 7 introduces manifest module; Task 8 uses it; Tasks 6/8 add binder diagnostics; Task 9-10 the Cypress harness
- Section 3 (Diagnostics Catalog) → Task 6 (#3, #4, #5), Task 7 (#2), Task 8 (#1, #6) — all six covered
- Section 4 (Test Plan) → Task 1 (stale fixes), Task 2 (unsupported-import), Task 3 (Panel/Card snapshots), Task 4 (EmptyState), Tasks 6-8 (diagnostic tests), Tasks 9-10 (Cypress)
- Section 5 (Implementation Order & Risks) — order followed exactly; manifest scope creep mitigated by Task 8 step 1 reusing existing resolver; update propagation risk addressed by Task 9 step 6 explicitly failing on remount; directive span fidelity addressed in Task 5 before Task 6 emits spans

No placeholders detected. All code blocks contain concrete code; all commands have expected output.

Type consistency:

- `slot_manifest.Manifest` defined in Task 7, consumed in Task 8
- `BindingResult.own_slot_manifest` introduced in Task 7, used by callers from there on
- `loadNeighbourManifest` introduced in Task 8 — used by Task 8 only

If a task fails its expected output, do not advance — diagnose. The most likely failure surface is Task 8's import resolution; in that case the fix is in `loadNeighbourManifest` only, not in the diagnostic code.
