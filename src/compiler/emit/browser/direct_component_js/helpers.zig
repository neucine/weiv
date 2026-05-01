const std = @import("std");
const browser_plan = @import("../../../lower/browser_plan.zig");
const common = @import("common.zig");
const node_codegen = @import("node_codegen.zig");

pub fn emitPrelude(out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try out.appendSlice(allocator,
        \\function evaluate(expression, scope) {
        \\  const entries = Object.entries(scope);
        \\  const names = entries.map(([name]) => name);
        \\  const values = entries.map(([, value]) => value);
        \\  return Function(...names, `return (${expression});`)(...values);
        \\}
        \\
        \\function applyBoundAttribute(element, name, value) {
        \\  if (name === "checked" || name === "disabled" || name === "selected") {
        \\    element[name] = Boolean(value);
        \\    if (value) {
        \\      element.setAttribute(name, "");
        \\    } else {
        \\      element.removeAttribute(name);
        \\    }
        \\    return;
        \\  }
        \\  if (name === "value") {
        \\    const next = value ?? "";
        \\    element.value = String(next);
        \\    element.setAttribute(name, String(next));
        \\    return;
        \\  }
        \\  if (value === false || value === null || value === undefined) {
        \\    element.removeAttribute(name);
        \\    return;
        \\  }
        \\  if (value === true) {
        \\    element.setAttribute(name, "");
        \\    return;
        \\  }
        \\  element.setAttribute(name, String(value));
        \\}
        \\
        \\function replaceBetween(start, end, content) {
        \\  const parent = start.parentNode;
        \\  if (!parent || parent !== end.parentNode) {
        \\    throw new Error("Conditional boundary is detached");
        \\  }
        \\  let current = start.nextSibling;
        \\  while (current && current !== end) {
        \\    const next = current.nextSibling;
        \\    parent.removeChild(current);
        \\    current = next;
        \\  }
        \\  parent.insertBefore(content, end);
        \\}
        \\
        \\function moveBoundaryBefore(start, end, reference) {
        \\  const parent = reference.parentNode;
        \\  if (!parent || parent !== start.parentNode || parent !== end.parentNode) {
        \\    throw new Error("Boundary move target is detached");
        \\  }
        \\  const nodes = [];
        \\  let current = start;
        \\  while (current) {
        \\    nodes.push(current);
        \\    if (current === end) break;
        \\    current = current.nextSibling;
        \\  }
        \\  for (const node of nodes) {
        \\    parent.insertBefore(node, reference);
        \\  }
        \\}
        \\
        \\function cloneScope(scope) {
        \\  const snapshot = {};
        \\  for (const key of Object.keys(scope)) {
        \\    snapshot[key] = scope[key];
        \\  }
        \\  return snapshot;
        \\}
        \\
        \\function hasScopeChanged(beforeScope, afterScope) {
        \\  const beforeKeys = Object.keys(beforeScope);
        \\  const afterKeys = Object.keys(afterScope);
        \\  if (beforeKeys.length !== afterKeys.length) {
        \\    return true;
        \\  }
        \\  for (const key of afterKeys) {
        \\    if (!Object.prototype.hasOwnProperty.call(beforeScope, key)) {
        \\      return true;
        \\    }
        \\    if (!Object.is(beforeScope[key], afterScope[key])) {
        \\      return true;
        \\    }
        \\  }
        \\  return false;
        \\}
        \\
    );
}

pub fn emitConditionalHelpers(
    nodes: []const browser_plan.Node,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    for (nodes) |node| {
        switch (node) {
            .element => |element| try emitConditionalHelpers(element.children, scope_id, out, allocator),
            .conditional => |conditional| {
                try emitSingleConditionalHelper(conditional, scope_id, out, allocator);
                try emitConditionalHelpers(conditional.consequent, scope_id, out, allocator);
                try emitConditionalHelpers(conditional.alternate, scope_id, out, allocator);
            },
            .for_loop => |for_loop| {
                try emitSingleForLoopHelper(for_loop, scope_id, out, allocator);
                try emitConditionalHelpers(for_loop.body, scope_id, out, allocator);
            },
            .slot_outlet => |slot_outlet| {
                try emitConditionalHelpers(slot_outlet.fallback_children, scope_id, out, allocator);
            },
            .component => |component_node| {
                for (component_node.slot_provisions) |slot_provision| {
                    try emitConditionalHelpers(slot_provision.children, scope_id, out, allocator);
                }
                if (component_node.slot_provisions.len > 0) {
                    try emitProjectedSlotHelpers(component_node, scope_id, out, allocator);
                }
            },
            .text, .interpolation => {},
        }
    }
}

fn emitProjectedSlotHelpers(
    component_node: browser_plan.ComponentNode,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    for (component_node.slot_provisions, 0..) |slot_provision, idx| {
        try out.writer(allocator).print(
            "function mountProjectedSlot_{d}_{d}(start, end, ownerInstance) {{\n  const instance = {{ refs: [], refresh: () => ownerInstance.refresh(), update: () => ownerInstance.update() }};\n  const refs = instance.refs;\n  const fragment = document.createDocumentFragment();\n",
            .{ component_node.handle_ref_id, idx },
        );
        for (slot_provision.children) |child| {
            try node_codegen.emitCreateNode(child, "fragment", scope_id, out, allocator, 1, "instance.refresh()", "refs");
        }
        try out.appendSlice(allocator, "  replaceBetween(start, end, fragment);\n");
        try out.appendSlice(allocator, "  function update() {\n    const refs = instance.refs;\n    const scope = instance.refresh();\n");
        for (slot_provision.children) |child| {
            try node_codegen.emitUpdateNode(child, out, allocator, 2, "scope", "refs");
        }
        try out.appendSlice(allocator, "  }\n  update();\n  return { update, start, end };\n}\n\n");
    }
}

fn emitSingleConditionalHelper(
    conditional: browser_plan.ConditionalNode,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.writer(allocator).print(
        "function createConditionalFragment_{d}(instance, scope, isConsequent) {{\n  const refs = instance.refs;\n  const fragment = document.createDocumentFragment();\n",
        .{conditional.start_ref_id},
    );
    try out.appendSlice(allocator, "  if (isConsequent) {\n");
    for (conditional.consequent) |node| {
        try node_codegen.emitCreateNode(node, "fragment", scope_id, out, allocator, 2, "scope", "refs");
    }
    for (conditional.consequent) |node| {
        try node_codegen.emitUpdateNode(node, out, allocator, 2, "scope", "refs");
    }
    try out.appendSlice(allocator, "  } else {\n");
    for (conditional.alternate) |node| {
        try node_codegen.emitCreateNode(node, "fragment", scope_id, out, allocator, 2, "scope", "refs");
    }
    for (conditional.alternate) |node| {
        try node_codegen.emitUpdateNode(node, out, allocator, 2, "scope", "refs");
    }
    try out.appendSlice(allocator, "  }\n  return fragment;\n}\n\n");

    try out.writer(allocator).print(
        "function updateConditional_{d}(instance, scope) {{\n  const refs = instance.refs;\n  const next = Boolean(evaluate(",
        .{conditional.start_ref_id},
    );
    try common.emitString(conditional.condition, out, allocator);
    try out.writer(allocator).print(
        ", scope));\n  if (refs[{d}] !== next) {{\n    refs[{d}] = next;\n    replaceBetween(refs[{d}], refs[{d}], createConditionalFragment_{d}(instance, scope, next));\n  }}\n",
        .{
            conditional.state_ref_id,
            conditional.state_ref_id,
            conditional.start_ref_id,
            conditional.end_ref_id,
            conditional.start_ref_id,
        },
    );
    try out.appendSlice(allocator, "  if (next) {\n");
    for (conditional.consequent) |node| {
        try node_codegen.emitUpdateNode(node, out, allocator, 2, "scope", "refs");
    }
    try out.appendSlice(allocator, "  } else {\n");
    for (conditional.alternate) |node| {
        try node_codegen.emitUpdateNode(node, out, allocator, 2, "scope", "refs");
    }
    try out.appendSlice(allocator, "  }\n}\n\n");
}

fn emitSingleForLoopHelper(
    for_loop: browser_plan.ForLoopNode,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    if (for_loop.body.len == 1 and std.meta.activeTag(for_loop.body[0]) == .component) {
        const component_node = for_loop.body[0].component;
        try emitKeyedComponentLoopHelper(for_loop, component_node, out, allocator);
        return;
    }
    try emitKeyedGenericLoopHelper(for_loop, scope_id, out, allocator);
}

fn emitKeyedComponentLoopHelper(
    for_loop: browser_plan.ForLoopNode,
    component_node: browser_plan.ComponentNode,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.writer(allocator).print(
        "function createForComponentEntry_{d}(instance, scope, item, reference) {{\n  const refs = instance.refs;\n  const parent = reference.parentNode;\n  const start = document.createComment(\"for:item:start\");\n  const end = document.createComment(\"for:item:end\");\n  parent.insertBefore(start, reference);\n  parent.insertBefore(end, reference);\n  const loopScope = {{ ...scope, [",
        .{for_loop.start_ref_id},
    );
    try common.emitString(for_loop.item_name, out, allocator);
    try out.appendSlice(allocator, "]: item };\n  const props = ");
    try node_codegen.emitPropsObject(component_node.bind_effects, out, allocator, "loopScope");
    try out.appendSlice(allocator, ";\n  const handlers = ");
    try node_codegen.emitChildHandlersObject(component_node.event_effects, out, allocator, "loopScope");
    if (component_node.slot_provisions.len > 0) {
        try out.appendSlice(allocator, ";\n  const slots = ");
        try emitProjectedSlotsObject(component_node, out, allocator);
    }
    try out.writer(allocator).print(
        ";\n  const handle = {s}.mountIntoBoundary(start, end, props, handlers{s});\n  return {{ key: item?.id ?? item, start, end, handle }};\n}}\n\n",
        .{
            component_node.tag_name,
            if (component_node.slot_provisions.len > 0) ", slots" else "",
        },
    );

    try out.writer(allocator).print(
        "function updateForLoop_{d}(instance, scope) {{\n  const refs = instance.refs;\n  const iterable = evaluate(",
        .{for_loop.start_ref_id},
    );
    try common.emitString(for_loop.iterable_expr, out, allocator);
    try out.writer(allocator).print(
        ", scope) ?? [];\n  const previous = refs[{d}] ?? [];\n  const previousByKey = new Map(previous.map((record) => [record.key, record]));\n  const nextRecords = [];\n  for (const item of iterable) {{\n    const key = item?.id ?? item;\n    let record = previousByKey.get(key);\n    const loopScope = {{ ...scope, [",
        .{for_loop.state_ref_id},
    );
    try common.emitString(for_loop.item_name, out, allocator);
    try out.appendSlice(allocator, "]: item };\n    if (record) {\n      previousByKey.delete(key);\n      record.handle.setProps(");
    try node_codegen.emitPropsObject(component_node.bind_effects, out, allocator, "loopScope");
    try out.appendSlice(allocator, ");\n      record.handle.setEventHandlers(");
    try node_codegen.emitChildHandlersObject(component_node.event_effects, out, allocator, "loopScope");
    if (component_node.slot_provisions.len > 0) {
        try out.appendSlice(allocator, ");\n      record.handle.setSlots(");
        try emitProjectedSlotsObject(component_node, out, allocator);
    }
    try out.writer(allocator).print(
        ");\n      record.handle.update();\n      moveBoundaryBefore(record.start, record.end, refs[{d}]);\n    }} else {{\n      record = createForComponentEntry_{d}(instance, scope, item, refs[{d}]);\n    }}\n    nextRecords.push(record);\n  }}\n  for (const record of previousByKey.values()) {{\n    replaceBetween(record.start, record.end, document.createDocumentFragment());\n    record.start.parentNode.removeChild(record.start);\n    record.end.parentNode.removeChild(record.end);\n  }}\n  refs[{d}] = nextRecords;\n}}\n\n",
        .{ for_loop.end_ref_id, for_loop.start_ref_id, for_loop.end_ref_id, for_loop.state_ref_id },
    );
}

fn emitKeyedGenericLoopHelper(
    for_loop: browser_plan.ForLoopNode,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.writer(allocator).print(
        "function createForEntry_{d}(instance, scope, item, reference) {{\n  const parent = reference.parentNode;\n  const start = document.createComment(\"for:item:start\");\n  const end = document.createComment(\"for:item:end\");\n  parent.insertBefore(start, reference);\n  parent.insertBefore(end, reference);\n  const entryRefs = [];\n  let currentItem = item;\n  function update(nextScope, nextItem) {{\n    if (arguments.length > 1) currentItem = nextItem;\n    const refs = entryRefs;\n    const loopScope = {{ ...nextScope, [",
        .{for_loop.start_ref_id},
    );
    try common.emitString(for_loop.item_name, out, allocator);
    try out.appendSlice(allocator, "]: currentItem };\n");
    for (for_loop.body) |node| {
        try node_codegen.emitUpdateNode(node, out, allocator, 2, "loopScope", "entryRefs");
    }
    try out.appendSlice(allocator, "  }\n  const fragment = document.createDocumentFragment();\n");
    for (for_loop.body) |node| {
        try node_codegen.emitCreateNode(node, "fragment", scope_id, out, allocator, 1, "scope", "entryRefs");
    }
    try out.appendSlice(allocator, "  replaceBetween(start, end, fragment);\n  update(scope, item);\n  return { key: item?.id ?? item, start, end, refs: entryRefs, update };\n}\n\n");

    try out.writer(allocator).print(
        "function updateForLoop_{d}(instance, scope) {{\n  const refs = instance.refs;\n  const iterable = evaluate(",
        .{for_loop.start_ref_id},
    );
    try common.emitString(for_loop.iterable_expr, out, allocator);
    try out.writer(allocator).print(
        ", scope) ?? [];\n  const previous = refs[{d}] ?? [];\n  const previousByKey = new Map(previous.map((record) => [record.key, record]));\n  const nextRecords = [];\n  for (const item of iterable) {{\n    const key = item?.id ?? item;\n    let record = previousByKey.get(key);\n    if (record) {{\n      previousByKey.delete(key);\n      record.update(scope, item);\n      moveBoundaryBefore(record.start, record.end, refs[{d}]);\n    }} else {{\n      record = createForEntry_{d}(instance, scope, item, refs[{d}]);\n    }}\n    nextRecords.push(record);\n  }}\n  for (const record of previousByKey.values()) {{\n    replaceBetween(record.start, record.end, document.createDocumentFragment());\n    record.start.parentNode.removeChild(record.start);\n    record.end.parentNode.removeChild(record.end);\n  }}\n  refs[{d}] = nextRecords;\n}}\n\n",
        .{ for_loop.state_ref_id, for_loop.end_ref_id, for_loop.start_ref_id, for_loop.end_ref_id, for_loop.state_ref_id },
    );
}

fn emitProjectedSlotsObject(
    component_node: browser_plan.ComponentNode,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator, "{ ");
    for (component_node.slot_provisions, 0..) |slot_provision, idx| {
        if (idx > 0) try out.appendSlice(allocator, ", ");
        if (slot_provision.name) |name| {
            try common.emitString(name, out, allocator);
        } else {
            try out.appendSlice(allocator, "default");
        }
        try out.writer(allocator).print(": {{ mountIntoBoundary: (start, end) => mountProjectedSlot_{d}_{d}(start, end, instance) }}", .{
            component_node.handle_ref_id,
            idx,
        });
    }
    try out.appendSlice(allocator, " }");
}
