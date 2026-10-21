const std = @import("std");
const browser_render_tree = @import("../../render_tree/index.zig");
const common = @import("common.zig");
const node_codegen = @import("node_codegen.zig");

pub fn emitPrelude(out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try out.appendSlice(allocator,
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
        \\function collectDirtyBindings(beforeScope, afterScope) {
        \\  const dirty = [];
        \\  const seen = new Set();
        \\  for (const key of Object.keys(beforeScope)) {
        \\    seen.add(key);
        \\    if (!Object.prototype.hasOwnProperty.call(afterScope, key) || !Object.is(beforeScope[key], afterScope[key])) {
        \\      dirty.push(key);
        \\    }
        \\  }
        \\  for (const key of Object.keys(afterScope)) {
        \\    if (seen.has(key)) {
        \\      continue;
        \\    }
        \\    if (!Object.prototype.hasOwnProperty.call(beforeScope, key)) {
        \\      dirty.push(key);
        \\    }
        \\  }
        \\  return dirty;
        \\}
        \\
        \\function normalizeDirtyState(dirtyState) {
        \\  if (Array.isArray(dirtyState)) {
        \\    return { bindings: dirtyState, paths: [], preciseBindings: [] };
        \\  }
        \\  if (!dirtyState || typeof dirtyState !== "object") {
        \\    return { bindings: [], paths: [], preciseBindings: [] };
        \\  }
        \\  return {
        \\    bindings: Array.isArray(dirtyState.bindings) ? dirtyState.bindings : [],
        \\    paths: Array.isArray(dirtyState.paths) ? dirtyState.paths : [],
        \\    preciseBindings: Array.isArray(dirtyState.preciseBindings) ? dirtyState.preciseBindings : [],
        \\  };
        \\}
        \\
        \\const __weiv_observableBrand = Symbol.for("weiv.observable");
        \\
        \\function __weiv_getObservableNode(value) {
        \\  if (!value || (typeof value !== "object" && typeof value !== "function")) {
        \\    return null;
        \\  }
        \\  const node = Reflect.get(value, __weiv_observableBrand);
        \\  if (!node || typeof node !== "object") {
        \\    return null;
        \\  }
        \\  return node;
        \\}
        \\
        \\function __weiv_isObservable(value) {
        \\  return __weiv_getObservableNode(value) !== null;
        \\}
        \\
        \\const __weiv_trackedRootCache = new Map();
        \\const __weiv_trackedSubscribers = new Set();
        \\const __weiv_pendingTrackedPathIds = new Set();
        \\let __weiv_trackedFlushScheduled = false;
        \\
        \\function __weiv_findTrackedRootPlan(bindingName) {
        \\  if (!trackedStateGraph || !Array.isArray(trackedStateGraph.roots)) {
        \\    return null;
        \\  }
        \\  for (const root of trackedStateGraph.roots) {
        \\    if (root && root.bindingName === bindingName) {
        \\      return root;
        \\    }
        \\  }
        \\  return null;
        \\}
        \\
        \\function __weiv_markTrackedPathsForWrite(rootId, fullPath) {
        \\  if (!trackedStateGraph || !Array.isArray(trackedStateGraph.paths)) {
        \\    return;
        \\  }
        \\  for (const pathRecord of trackedStateGraph.paths) {
        \\    if (!pathRecord || pathRecord.rootId !== rootId || typeof pathRecord.path !== "string") continue;
        \\    if (pathRecord.path === fullPath || pathRecord.path.startsWith(`${fullPath}.`)) {
        \\      __weiv_pendingTrackedPathIds.add(pathRecord.pathId);
        \\    }
        \\  }
        \\}
        \\
        \\function __weiv_scheduleTrackedFlush() {
        \\  if (__weiv_trackedFlushScheduled) {
        \\    return;
        \\  }
        \\  __weiv_trackedFlushScheduled = true;
        \\  globalThis.queueMicrotask(() => {
        \\    __weiv_trackedFlushScheduled = false;
        \\    const dirtyPaths = Array.from(__weiv_pendingTrackedPathIds);
        \\    __weiv_pendingTrackedPathIds.clear();
        \\    if (dirtyPaths.length === 0) {
        \\      return;
        \\    }
        \\    for (const instance of Array.from(__weiv_trackedSubscribers)) {
        \\      if (!instance || instance.destroyed) {
        \\        __weiv_trackedSubscribers.delete(instance);
        \\        continue;
        \\      }
        \\      if (typeof instance.updateDirty === "function") {
        \\        const scope = instance.refresh();
        \\        instance.updateDirty({ bindings: [], paths: dirtyPaths }, scope);
        \\      } else if (typeof instance.update === "function") {
        \\        instance.update();
        \\      }
        \\    }
        \\  });
        \\}
        \\
        \\function __weiv_wrapTrackedValue(rootId, currentPath, value) {
        \\  if (!value || (typeof value !== "object" && typeof value !== "function")) {
        \\    return value;
        \\  }
        \\  const proxy = new Proxy(value, {
        \\    get(target, prop, receiver) {
        \\      const result = Reflect.get(target, prop, receiver);
        \\      if (typeof prop !== "string") {
        \\        return result;
        \\      }
        \\      const nextPath = currentPath ? `${currentPath}.${prop}` : prop;
        \\      return __weiv_wrapTrackedValue(rootId, nextPath, result);
        \\    },
        \\    set(target, prop, nextValue, receiver) {
        \\      const updated = Reflect.set(target, prop, nextValue, receiver);
        \\      if (updated && typeof prop === "string") {
        \\        const nextPath = currentPath ? `${currentPath}.${prop}` : prop;
        \\        __weiv_markTrackedPathsForWrite(rootId, nextPath);
        \\        __weiv_scheduleTrackedFlush();
        \\      }
        \\      return updated;
        \\    },
        \\    deleteProperty(target, prop) {
        \\      const updated = Reflect.deleteProperty(target, prop);
        \\      if (updated && typeof prop === "string") {
        \\        const nextPath = currentPath ? `${currentPath}.${prop}` : prop;
        \\        __weiv_markTrackedPathsForWrite(rootId, nextPath);
        \\        __weiv_scheduleTrackedFlush();
        \\      }
        \\      return updated;
        \\    },
        \\  });
        \\  return proxy;
        \\}
        \\
        \\function __weiv_getTrackedRoot(bindingName, value) {
        \\  if (__weiv_isObservable(value)) {
        \\    return value;
        \\  }
        \\  const rootPlan = __weiv_findTrackedRootPlan(bindingName);
        \\  if (!rootPlan) {
        \\    return value;
        \\  }
        \\  const cachedEntry = __weiv_trackedRootCache.get(rootPlan.rootId);
        \\  if (cachedEntry && Object.is(cachedEntry.value, value)) {
        \\    return cachedEntry.proxy;
        \\  }
        \\  const trackedValue = __weiv_wrapTrackedValue(rootPlan.rootId, bindingName, value);
        \\  __weiv_trackedRootCache.set(rootPlan.rootId, { value, proxy: trackedValue });
        \\  return trackedValue;
        \\}
        \\
        \\function collectTrackedDirtyPaths() {
        \\  if (__weiv_pendingTrackedPathIds.size === 0) {
        \\    return [];
        \\  }
        \\  const dirtyPaths = Array.from(__weiv_pendingTrackedPathIds);
        \\  __weiv_pendingTrackedPathIds.clear();
        \\  return dirtyPaths;
        \\}
        \\
        \\function __weiv_hasTrackedRoots() {
        \\  return trackedStateGraph && Array.isArray(trackedStateGraph.roots) && trackedStateGraph.roots.length > 0;
        \\}
        \\
        \\function __weiv_registerTrackedSubscriber(instance) {
        \\  if (__weiv_hasTrackedRoots()) {
        \\    __weiv_trackedSubscribers.add(instance);
        \\  }
        \\}
        \\
        \\function __weiv_unregisterTrackedSubscriber(instance) {
        \\  __weiv_trackedSubscribers.delete(instance);
        \\}
        \\
        \\function flushOwnedBoundary(instance, beforeScope) {
        \\  if (instance.destroyed) {
        \\    return beforeScope;
        \\  }
        \\  const afterScope = instance.refresh();
        \\  const dirtyBindings = collectDirtyBindings(beforeScope, afterScope);
        \\  const dirtyPaths = collectTrackedDirtyPaths();
        \\  if (dirtyBindings.length > 0 || dirtyPaths.length > 0) {
        \\    if (typeof instance.updateDirty === "function") {
        \\      instance.updateDirty({ bindings: dirtyBindings, paths: dirtyPaths }, afterScope);
        \\    } else {
        \\      instance.update();
        \\    }
        \\    return cloneScope(instance.refresh());
        \\  }
        \\  return cloneScope(afterScope);
        \\}
        \\
        \\function runOwnedBoundary(instance, callback) {
        \\  let beforeScope = cloneScope(instance.refresh());
        \\  let result;
        \\  try {
        \\    result = callback();
        \\  } catch (error) {
        \\    flushOwnedBoundary(instance, beforeScope);
        \\    throw error;
        \\  }
        \\  beforeScope = flushOwnedBoundary(instance, beforeScope);
        \\  if (result && typeof result.then === "function") {
        \\    return result.finally(() => {
        \\      flushOwnedBoundary(instance, beforeScope);
        \\    });
        \\  }
        \\  return result;
        \\}
        \\
    );
}

pub fn emitConditionalHelpers(
    nodes: []const browser_render_tree.Node,
    scope_id: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    for (nodes) |node| {
        switch (node) {
            .element => |element| try emitConditionalHelpers(element.children, scope_id, bindings_json, out, allocator),
            .conditional => |conditional| {
                try emitSingleConditionalHelper(conditional, scope_id, bindings_json, out, allocator);
                try emitConditionalHelpers(conditional.consequent, scope_id, bindings_json, out, allocator);
                try emitConditionalHelpers(conditional.alternate, scope_id, bindings_json, out, allocator);
            },
            .for_loop => |for_loop| {
                try emitSingleForLoopHelper(for_loop, scope_id, bindings_json, out, allocator);
                try emitConditionalHelpers(for_loop.body, scope_id, bindings_json, out, allocator);
            },
            .slot_outlet => |slot_outlet| {
                try emitSingleSlotFallbackHelper(slot_outlet, scope_id, out, allocator);
                try emitConditionalHelpers(slot_outlet.fallback_children, scope_id, bindings_json, out, allocator);
            },
            .component => |component_node| {
                for (component_node.slot_provisions) |slot_provision| {
                    try emitConditionalHelpers(slot_provision.children, scope_id, bindings_json, out, allocator);
                }
                if (component_node.slot_provisions.len > 0) {
                    try emitProjectedSlotHelpers(component_node, scope_id, out, allocator);
                }
            },
            .text, .interpolation => {},
        }
    }
}

fn emitSingleSlotFallbackHelper(
    slot_outlet: browser_render_tree.SlotOutletNode,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.print(
        allocator,
        "function createSlotFallbackFragment_{d}(instance, scope) {{\n  const refs = instance.refs;\n  const fragment = document.createDocumentFragment();\n",
        .{slot_outlet.handle_ref_id},
    );
    for (slot_outlet.fallback_children) |child| {
        try node_codegen.emitCreateNode(child, "fragment", scope_id, out, allocator, 1, "scope", "refs");
    }
    for (slot_outlet.fallback_children) |child| {
        try node_codegen.emitUpdateNode(child, out, allocator, 1, "scope", "refs");
    }
    try out.appendSlice(allocator, "  return fragment;\n}\n\n");
}

fn emitProjectedSlotHelpers(
    component_node: browser_render_tree.ComponentNode,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    for (component_node.slot_provisions, 0..) |slot_provision, idx| {
        try out.print(
            allocator,
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
        try out.appendSlice(allocator, "  }\n  function destroy() {\n    const refs = instance.refs;\n");
        for (slot_provision.children) |child| {
            try node_codegen.emitDestroyNode(child, out, allocator, 2, "refs");
        }
        try out.appendSlice(allocator, "  }\n  update();\n  return { update, destroy, start, end };\n}\n\n");
    }
}

fn emitSingleConditionalHelper(
    conditional: browser_render_tree.ConditionalNode,
    scope_id: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.print(
        allocator,
        "function createConditionalFragment_{d}(instance, scope, refs, isConsequent) {{\n  const fragment = document.createDocumentFragment();\n",
        .{conditional.start_ref_id},
    );
    try out.appendSlice(allocator, "  if (isConsequent) {\n");
    for (conditional.consequent) |node| {
        try node_codegen.emitCreateNode(node, "fragment", scope_id, out, allocator, 2, "scope", "refs");
    }
    try out.appendSlice(allocator, "  } else {\n");
    for (conditional.alternate) |node| {
        try node_codegen.emitCreateNode(node, "fragment", scope_id, out, allocator, 2, "scope", "refs");
    }
    try out.appendSlice(allocator, "  }\n  return fragment;\n}\n\n");

    try out.print(
        allocator,
        "function destroyConditionalBranch_{d}(instance, refs, wasConsequent) {{\n  if (wasConsequent) {{\n",
        .{conditional.start_ref_id},
    );
    for (conditional.consequent) |node| {
        try node_codegen.emitDestroyNode(node, out, allocator, 2, "refs");
    }
    try out.appendSlice(allocator, "  } else {\n");
    for (conditional.alternate) |node| {
        try node_codegen.emitDestroyNode(node, out, allocator, 2, "refs");
    }
    try out.appendSlice(allocator, "  }\n}\n\n");

    try out.print(
        allocator,
        "function updateConditional_{d}(instance, scope, refs) {{\n  const next = Boolean(",
        .{conditional.start_ref_id},
    );
    try node_codegen.emitResolvedExpression(conditional.condition, "scope", bindings_json, out, allocator);
    try out.print(
        allocator,
        ");\n  if (refs[{d}] !== next) {{\n    const previous = refs[{d}];\n    destroyConditionalBranch_{d}(instance, refs, previous === true);\n    refs[{d}] = next;\n    replaceBetween(refs[{d}], refs[{d}], createConditionalFragment_{d}(instance, scope, refs, next));\n  }}\n",
        .{
            conditional.state_ref_id,
            conditional.state_ref_id,
            conditional.start_ref_id,
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
    for_loop: browser_render_tree.ForLoopNode,
    scope_id: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    if (for_loop.body.len == 1 and std.meta.activeTag(for_loop.body[0]) == .component) {
        const component_node = for_loop.body[0].component;
        try emitKeyedComponentLoopHelper(for_loop, component_node, bindings_json, out, allocator);
        return;
    }
    try emitKeyedGenericLoopHelper(for_loop, scope_id, bindings_json, out, allocator);
}

fn emitKeyedComponentLoopHelper(
    for_loop: browser_render_tree.ForLoopNode,
    component_node: browser_render_tree.ComponentNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const has_props = node_codegen.componentHasProps(component_node);
    const has_handlers = node_codegen.componentHasEventHandlers(component_node);
    const has_slots = node_codegen.componentHasSlots(component_node);
    const needs_update = node_codegen.componentNeedsParentUpdate(component_node);
    try out.print(
        allocator,
        "function createForComponentEntry_{d}(instance, scope, item, reference) {{\n  const parent = reference.parentNode;\n  const start = document.createComment(\"for:item:start\");\n  const end = document.createComment(\"for:item:end\");\n  parent.insertBefore(start, reference);\n  parent.insertBefore(end, reference);\n  const loopScope = {{ ...scope, [",
        .{for_loop.start_ref_id},
    );
    try common.emitString(for_loop.item_name, out, allocator);
    try out.appendSlice(allocator, "]: item };\n");
    if (has_props) {
        try out.appendSlice(allocator, "  const props = ");
        try node_codegen.emitPropsObject(component_node.bind_effects, out, allocator, "loopScope", bindings_json);
        try out.appendSlice(allocator, ";\n");
    }
    if (has_handlers) {
        try out.appendSlice(allocator, "  const handlers = ");
        try node_codegen.emitChildHandlersObject(component_node.event_effects, out, allocator, "loopScope", bindings_json);
        try out.appendSlice(allocator, ";\n");
    }
    if (has_slots) {
        try out.appendSlice(allocator, "  const slotOwner = { refresh: () => loopScope, update: () => instance.update() };\n");
        try out.appendSlice(allocator, "  const slots = ");
        try common.emitProjectedSlotObject(component_node, "slotOwner", out, allocator);
        try out.appendSlice(allocator, ";\n");
    }
    try out.print(
        allocator,
        "  const handle = {s}.mountIntoBoundary(start, end, {s}, {s}, {s});\n  return {{ key: item?.id ?? item, start, end, handle }};\n}}\n\n",
        .{
            component_node.tag_name,
            if (has_props) "props" else "undefined",
            if (has_handlers) "handlers" else "undefined",
            if (has_slots) "slots" else "undefined",
        },
    );

    try out.print(
        allocator,
        "function updateForLoop_{d}(instance, scope, refs) {{\n  const iterable = (",
        .{for_loop.start_ref_id},
    );
    try node_codegen.emitResolvedExpression(for_loop.iterable_expr, "scope", bindings_json, out, allocator);
    try out.print(
        allocator,
        ") ?? [];\n  const previous = refs[{d}] ?? [];\n  const previousByKey = new Map(previous.map((record) => [record.key, record]));\n  const nextRecords = [];\n  for (const item of iterable) {{\n    const key = item?.id ?? item;\n    let record = previousByKey.get(key);\n    const loopScope = {{ ...scope, [",
        .{for_loop.state_ref_id},
    );
    try common.emitString(for_loop.item_name, out, allocator);
    try out.appendSlice(allocator, "]: item };\n    if (record) {\n      previousByKey.delete(key);\n");
    if (has_props) {
        try out.appendSlice(allocator, "      record.handle.setProps(");
        try node_codegen.emitPropsObject(component_node.bind_effects, out, allocator, "loopScope", bindings_json);
        try out.appendSlice(allocator, ");\n");
    }
    if (has_handlers) {
        try out.appendSlice(allocator, "      record.handle.setEventHandlers(");
        try node_codegen.emitChildHandlersObject(component_node.event_effects, out, allocator, "loopScope", bindings_json);
        try out.appendSlice(allocator, ");\n");
    }
    if (has_slots) {
        try out.appendSlice(allocator, "      const slotOwner = { refresh: () => loopScope, update: () => instance.update() };\n");
        try out.appendSlice(allocator, "      record.handle.setSlots(");
        try common.emitProjectedSlotObject(component_node, "slotOwner", out, allocator);
        try out.appendSlice(allocator, ");\n");
    }
    if (needs_update) {
        try out.appendSlice(allocator, "      record.handle.update();\n");
    }
    try out.print(
        allocator,
        "      moveBoundaryBefore(record.start, record.end, refs[{d}]);\n    }} else {{\n      record = createForComponentEntry_{d}(instance, scope, item, refs[{d}]);\n    }}\n    nextRecords.push(record);\n  }}\n  for (const record of previousByKey.values()) {{\n    if (record.handle && typeof record.handle.destroy === \"function\") {{\n      record.handle.destroy();\n    }}\n    replaceBetween(record.start, record.end, document.createDocumentFragment());\n    record.start.parentNode.removeChild(record.start);\n    record.end.parentNode.removeChild(record.end);\n  }}\n  refs[{d}] = nextRecords;\n}}\n\n",
        .{ for_loop.end_ref_id, for_loop.start_ref_id, for_loop.end_ref_id, for_loop.state_ref_id },
    );
}

fn emitKeyedGenericLoopHelper(
    for_loop: browser_render_tree.ForLoopNode,
    scope_id: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.print(
        allocator,
        "function createForEntry_{d}(instance, scope, item, reference) {{\n  const parent = reference.parentNode;\n  const start = document.createComment(\"for:item:start\");\n  const end = document.createComment(\"for:item:end\");\n  parent.insertBefore(start, reference);\n  parent.insertBefore(end, reference);\n  const entryRefs = [];\n  let currentItem = item;\n  let loopScope = {{ ...scope, [",
        .{for_loop.start_ref_id},
    );
    try common.emitString(for_loop.item_name, out, allocator);
    try out.appendSlice(allocator, "]: currentItem };\n  function update(nextScope, nextItem) {\n    if (arguments.length > 1) currentItem = nextItem;\n    const refs = entryRefs;\n    loopScope = { ...nextScope, [");
    try common.emitString(for_loop.item_name, out, allocator);
    try out.appendSlice(allocator, "]: currentItem };\n");
    for (for_loop.body) |node| {
        try node_codegen.emitUpdateNode(node, out, allocator, 2, "loopScope", "entryRefs");
    }
    try out.appendSlice(allocator, "  }\n  const fragment = document.createDocumentFragment();\n");
    for (for_loop.body) |node| {
        try node_codegen.emitCreateNode(node, "fragment", scope_id, out, allocator, 1, "loopScope", "entryRefs");
    }
    try out.appendSlice(allocator, "  function destroy() {\n    const refs = entryRefs;\n");
    for (for_loop.body) |node| {
        try node_codegen.emitDestroyNode(node, out, allocator, 2, "entryRefs");
    }
    try out.appendSlice(allocator, "  }\n  replaceBetween(start, end, fragment);\n  update(scope, item);\n  return { key: item?.id ?? item, start, end, refs: entryRefs, update, destroy };\n}\n\n");

    try out.print(
        allocator,
        "function updateForLoop_{d}(instance, scope, refs) {{\n  const iterable = (",
        .{for_loop.start_ref_id},
    );
    try node_codegen.emitResolvedExpression(for_loop.iterable_expr, "scope", bindings_json, out, allocator);
    try out.print(
        allocator,
        ") ?? [];\n  const previous = refs[{d}] ?? [];\n  const previousByKey = new Map(previous.map((record) => [record.key, record]));\n  const nextRecords = [];\n  for (const item of iterable) {{\n    const key = item?.id ?? item;\n    let record = previousByKey.get(key);\n    if (record) {{\n      previousByKey.delete(key);\n      record.update(scope, item);\n      moveBoundaryBefore(record.start, record.end, refs[{d}]);\n    }} else {{\n      record = createForEntry_{d}(instance, scope, item, refs[{d}]);\n    }}\n    nextRecords.push(record);\n  }}\n  for (const record of previousByKey.values()) {{\n    if (typeof record.destroy === \"function\") {{\n      record.destroy();\n    }}\n    replaceBetween(record.start, record.end, document.createDocumentFragment());\n    record.start.parentNode.removeChild(record.start);\n    record.end.parentNode.removeChild(record.end);\n  }}\n  refs[{d}] = nextRecords;\n}}\n\n",
        .{ for_loop.state_ref_id, for_loop.end_ref_id, for_loop.start_ref_id, for_loop.end_ref_id, for_loop.state_ref_id },
    );
}
