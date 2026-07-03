const std = @import("std");
const browser_render_tree = @import("../../render_tree/index.zig");
const lir = @import("../../../../lower/lir.zig");
const component = @import("../../../../component_unit.zig");
const sir = @import("../../../../sema/sir.zig");
const tracked_root = @import("../../../../sema/tracked_root.zig");
const common = @import("common.zig");
const script_backend = @import("../../../../../ffi/script_backend.zig");

const TrackedRoot = struct {
    id: usize,
    binding_name: []const u8,
    kind: []const u8,
};

const TrackedPath = struct {
    id: usize,
    root_id: usize,
    path: []const u8,
    parent_path_id: ?usize,
};

const TrackedGraphBuilder = struct {
    allocator: std.mem.Allocator,
    component_model: *const component.ComponentUnit,
    roots: std.ArrayList(TrackedRoot) = .empty,
    paths: std.ArrayList(TrackedPath) = .empty,
    region_paths: std.ArrayList(std.ArrayList(usize)) = .empty,

    fn deinit(self: *TrackedGraphBuilder) void {
        self.roots.deinit(self.allocator);
        self.paths.deinit(self.allocator);
        for (self.region_paths.items) |*items| items.deinit(self.allocator);
        self.region_paths.deinit(self.allocator);
    }

    fn ensureRoot(self: *TrackedGraphBuilder, binding_name: []const u8, kind: []const u8) !usize {
        for (self.roots.items) |root| {
            if (std.mem.eql(u8, root.binding_name, binding_name)) return root.id;
        }
        const id = self.roots.items.len + 1;
        try self.roots.append(self.allocator, .{ .id = id, .binding_name = binding_name, .kind = kind });
        return id;
    }

    fn findPathId(self: *const TrackedGraphBuilder, path: []const u8) ?usize {
        for (self.paths.items) |tracked_path| {
            if (std.mem.eql(u8, tracked_path.path, path)) return tracked_path.id;
        }
        return null;
    }

    fn ensurePathChain(self: *TrackedGraphBuilder, full_path: []const u8) !usize {
        if (self.findPathId(full_path)) |id| return id;
        const first_dot = std.mem.indexOfScalar(u8, full_path, '.') orelse return error.InvalidTrackedPath;
        const root_name = full_path[0..first_dot];
        const kind = tracked_root.kindByName(self.component_model, root_name) orelse return error.InvalidTrackedPath;
        const root_id = try self.ensureRoot(root_name, kind.label());

        var parent_path_id: ?usize = null;
        var search_from: usize = 0;
        while (true) {
            const maybe_dot = std.mem.indexOfScalarPos(u8, full_path, search_from, '.');
            const end_index = maybe_dot orelse full_path.len;
            const prefix = full_path[0..end_index];
            const path_id = if (self.findPathId(prefix)) |existing|
                existing
            else blk: {
                const new_id = self.paths.items.len + 1;
                try self.paths.append(self.allocator, .{
                    .id = new_id,
                    .root_id = root_id,
                    .path = prefix,
                    .parent_path_id = parent_path_id,
                });
                break :blk new_id;
            };
            parent_path_id = path_id;
            if (maybe_dot == null) return path_id;
            search_from = end_index + 1;
        }
    }
};

pub fn emitCreateFunction(
    render_tree: browser_render_tree.Document,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator,
        \\function createDom(instance) {
        \\  const fragment = document.createDocumentFragment();
        \\  const refs = instance.refs;
        \\
    );
    for (render_tree.nodes) |node| {
        try emitCreateNode(node, "fragment", scope_id, out, allocator, 1, "instance.refresh()", "refs");
    }
    try out.appendSlice(allocator,
        \\  return fragment;
        \\}
        \\
    );
}

pub fn emitCreateNode(
    node: browser_render_tree.Node,
    parent_ref: []const u8,
    scope_id: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
) !void {
    switch (node) {
        .text => |text| {
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append(document.createTextNode(", .{parent_ref});
            try common.emitString(text.content, out, allocator);
            try out.appendSlice(allocator, "));\n");
        },
        .interpolation => |interp| {
            const var_name = try common.refVarName(interp.ref_id, allocator);
            defer allocator.free(var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createTextNode(\"\");\n", .{var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, interp.ref_id, var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, var_name });
        },
        .slot_outlet => |slot_outlet| {
            const start_var_name = try common.refVarName(slot_outlet.start_ref_id, allocator);
            defer allocator.free(start_var_name);
            const end_var_name = try common.refVarName(slot_outlet.end_ref_id, allocator);
            defer allocator.free(end_var_name);
            const slot_var_name = try std.fmt.allocPrint(allocator, "__slot_{d}", .{slot_outlet.handle_ref_id});
            defer allocator.free(slot_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"slot:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"slot:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, slot_outlet.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, slot_outlet.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = false;\n", .{ refs_expr, slot_outlet.handle_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, end_var_name });
            try emitSlotLookupLine(slot_outlet, slot_var_name, indent, out, allocator);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "if ({s}) {{\n", .{slot_var_name});
            try common.writeIndent(indent + 1, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s}.mountIntoBoundary({s}, {s});\n", .{
                refs_expr,
                slot_outlet.handle_ref_id,
                slot_var_name,
                start_var_name,
                end_var_name,
            });
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "} else {\n");
            try emitSlotFallbackReplaceLine(slot_outlet, start_var_name, end_var_name, scope_expr, indent + 1, out, allocator);
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
        },
        .element => |element| {
            const var_name = try common.refVarName(element.ref_id, allocator);
            defer allocator.free(var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createElement(\"{s}\");\n", .{ var_name, element.tag_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, element.ref_id, var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.setAttribute(\"data-weiv-scope\", \"{s}\");\n", .{ var_name, scope_id });
            for (element.attributes) |attribute| {
                try common.writeIndent(indent, out, allocator);
                try out.print(allocator, "{s}.setAttribute(\"{s}\", ", .{ var_name, attribute.name });
                try common.emitString(attribute.value orelse "", out, allocator);
                try out.appendSlice(allocator, ");\n");
            }
            for (element.event_effects) |effect| {
                switch (effect) {
                    .event => |event_dir| {
                        try common.writeIndent(indent, out, allocator);
                        try out.print(allocator, "{s}.addEventListener(\"{s}\", (event) => {{\n", .{ var_name, event_dir.event_name });
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "const resolved = ");
                        try emitResolvedExpression(event_dir.expression, scope_expr, "", out, allocator);
                        try out.appendSlice(allocator, ";\n");
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "if (typeof resolved === \"function\") {\n");
                        try common.writeIndent(indent + 2, out, allocator);
                        try out.appendSlice(allocator, "return runOwnedBoundary(instance, () => resolved(event));\n");
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "}\n");
                        try common.writeIndent(indent, out, allocator);
                        try out.appendSlice(allocator, "});\n");
                    },
                    .bind => unreachable,
                }
            }
            for (element.children) |child| {
                try emitCreateNode(child, var_name, scope_id, out, allocator, indent, scope_expr, refs_expr);
            }
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, var_name });
        },
        .conditional => |conditional| {
            const start_var_name = try common.refVarName(conditional.start_ref_id, allocator);
            defer allocator.free(start_var_name);
            const end_var_name = try common.refVarName(conditional.end_ref_id, allocator);
            defer allocator.free(end_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"if:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"if:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, conditional.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, conditional.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = undefined;\n", .{ refs_expr, conditional.state_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, end_var_name });
        },
        .component => |component_node| {
            const start_var_name = try common.refVarName(component_node.start_ref_id, allocator);
            defer allocator.free(start_var_name);
            const end_var_name = try common.refVarName(component_node.end_ref_id, allocator);
            defer allocator.free(end_var_name);
            const has_props = componentHasProps(component_node);
            const has_handlers = componentHasEventHandlers(component_node);
            const has_slots = componentHasSlots(component_node);
            const props_var_name = if (has_props)
                try std.fmt.allocPrint(allocator, "__props_{d}", .{component_node.handle_ref_id})
            else
                null;
            defer if (props_var_name) |name| allocator.free(name);
            const handlers_var_name = if (has_handlers)
                try std.fmt.allocPrint(allocator, "__handlers_{d}", .{component_node.handle_ref_id})
            else
                null;
            defer if (handlers_var_name) |name| allocator.free(name);
            const slots_var_name = if (has_slots)
                try std.fmt.allocPrint(allocator, "__slots_{d}", .{component_node.handle_ref_id})
            else
                null;
            defer if (slots_var_name) |name| allocator.free(name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"component:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"component:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, component_node.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, component_node.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, end_var_name });
            if (props_var_name) |name| {
                try common.writeIndent(indent, out, allocator);
                try out.print(allocator, "const {s} = ", .{name});
                try emitPropsObject(component_node.bind_effects, out, allocator, scope_expr, "");
                try out.appendSlice(allocator, ";\n");
            }
            if (handlers_var_name) |name| {
                try common.writeIndent(indent, out, allocator);
                try out.print(allocator, "const {s} = ", .{name});
                try emitChildHandlersObject(component_node.event_effects, out, allocator, scope_expr, "");
                try out.appendSlice(allocator, ";\n");
            }
            if (has_slots) {
                try common.writeIndent(indent, out, allocator);
                try out.print(allocator, "const {s} = ", .{slots_var_name.?});
                try common.emitProjectedSlotObject(component_node, "instance", out, allocator);
                try out.appendSlice(allocator, ";\n");
            }
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s}.mountIntoBoundary({s}, {s}, {s}, {s}, {s});\n", .{
                refs_expr,
                component_node.handle_ref_id,
                component_node.tag_name,
                start_var_name,
                end_var_name,
                props_var_name orelse "undefined",
                handlers_var_name orelse "undefined",
                slots_var_name orelse "undefined",
            });
        },
        .for_loop => |for_loop| {
            const start_var_name = try common.refVarName(for_loop.start_ref_id, allocator);
            defer allocator.free(start_var_name);
            const end_var_name = try common.refVarName(for_loop.end_ref_id, allocator);
            defer allocator.free(end_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"for:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = document.createComment(\"for:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, for_loop.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = {s};\n", .{ refs_expr, for_loop.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}[{d}] = [];\n", .{ refs_expr, for_loop.state_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "{s}.append({s});\n", .{ parent_ref, end_var_name });
        },
    }
}

pub fn emitUpdateFunction(
    render_tree: browser_render_tree.Document,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator,
        \\function updateDom(instance) {
        \\  const refs = instance.refs;
        \\  const scope = instance.refresh();
        \\
    );
    for (render_tree.nodes) |node| {
        try emitUpdateNode(node, out, allocator, 1, "scope", "refs");
    }
    try out.appendSlice(allocator,
        \\}
        \\
    );
}

pub fn emitTrackedStateGraphMetadata(
    component_model: *const component.ComponentUnit,
    render_tree: browser_render_tree.Document,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    var builder = TrackedGraphBuilder{ .allocator = allocator, .component_model = component_model };
    defer builder.deinit();

    try builder.region_paths.ensureTotalCapacity(allocator, countRegions(render_tree.nodes));
    try collectTrackedGraphForNodes(component_model, render_tree.nodes, &builder, allocator);

    try out.appendSlice(allocator, "export const trackedStateGraph = ");
    try emitTrackedStateGraphObject(&builder, out, allocator);
    try out.appendSlice(allocator, ";\n");
}

pub fn emitSelectiveUpdateFunction(
    component_model: *const component.ComponentUnit,
    render_tree: browser_render_tree.Document,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator,
        \\function updateDirtyRegions(instance, dirtyState, scope = instance.refresh()) {
        \\  const refs = instance.refs;
        \\  const normalizedDirtyState = normalizeDirtyState(dirtyState);
        \\  const dirtySet = new Set(normalizedDirtyState.bindings);
        \\  const dirtyPathSet = new Set(normalizedDirtyState.paths);
        \\  const dirtyRegionSet = new Set();
        \\  if (dirtyPathSet.size > 0 && trackedStateGraph && Array.isArray(trackedStateGraph.regions)) {
        \\    for (const region of trackedStateGraph.regions) {
        \\      if (!region || !Array.isArray(region.trackedPathIds)) continue;
        \\      for (const pathId of region.trackedPathIds) {
        \\        if (dirtyPathSet.has(pathId)) {
        \\          dirtyRegionSet.add(region.regionId);
        \\          break;
        \\        }
        \\      }
        \\    }
        \\  }
        \\
    );
    var next_region_id: usize = 1;
    for (render_tree.nodes) |node| {
        try emitSelectiveUpdateNode(component_model, node, out, allocator, 1, "scope", "refs", &.{}, &next_region_id);
    }
    try out.appendSlice(allocator,
        \\}
        \\
    );
}

pub fn emitRegionUpdateFunctions(
    render_tree: browser_render_tree.Document,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    for (render_tree.nodes) |node| {
        try emitRegionUpdateFunctionsForNode(node, bindings_json, out, allocator);
    }
}

fn emitRegionUpdateFunctionsForNode(
    node: browser_render_tree.Node,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    switch (node) {
        .text => {},
        .interpolation => |interp| {
            try emitTextRegionUpdateFunction(interp, bindings_json, out, allocator);
        },
        .element => |element| {
            for (element.bind_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| try emitAttributeRegionUpdateFunction(element.ref_id, bind_dir.target_name, bind_dir.expression, bindings_json, out, allocator),
                    .event => unreachable,
                }
            }
            for (element.children) |child| {
                try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
            }
        },
        .conditional => |conditional| {
            try emitConditionalRegionUpdateFunction(conditional, bindings_json, out, allocator);
            for (conditional.consequent) |child| {
                try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
            }
            for (conditional.alternate) |child| {
                try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
            }
        },
        .for_loop => |for_loop| {
            try emitLoopRegionUpdateFunction(for_loop, bindings_json, out, allocator);
            for (for_loop.body) |child| {
                try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
            }
        },
        .component => |component_node| {
            try emitChildRegionUpdateFunction(component_node, bindings_json, out, allocator);
            for (component_node.slot_provisions) |slot| {
                for (slot.children) |child| {
                    try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
                }
            }
        },
        .slot_outlet => |slot_outlet| {
            try emitSlotRegionUpdateFunction(slot_outlet, bindings_json, out, allocator);
            for (slot_outlet.fallback_children) |child| {
                try emitRegionUpdateFunctionsForNode(child, bindings_json, out, allocator);
            }
        },
    }
}

fn emitTrackedStateGraphObject(
    builder: *const TrackedGraphBuilder,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator, "{ roots: [");
    for (builder.roots.items, 0..) |root, idx| {
        if (idx > 0) try out.appendSlice(allocator, ", ");
        try out.print(allocator, "{{ rootId: {d}, bindingName: ", .{root.id});
        try common.emitString(root.binding_name, out, allocator);
        try out.appendSlice(allocator, ", kind: \"");
        try out.appendSlice(allocator, root.kind);
        try out.appendSlice(allocator, "\" }");
    }
    try out.appendSlice(allocator, "], paths: [");
    for (builder.paths.items, 0..) |path, idx| {
        if (idx > 0) try out.appendSlice(allocator, ", ");
        try out.print(allocator, "{{ pathId: {d}, rootId: {d}, path: ", .{ path.id, path.root_id });
        try common.emitString(path.path, out, allocator);
        if (path.parent_path_id) |parent_id| {
            try out.print(allocator, ", parentPathId: {d} }}", .{parent_id});
        } else {
            try out.appendSlice(allocator, ", parentPathId: null }");
        }
    }
    try out.appendSlice(allocator, "], regions: [");
    var wrote_region = false;
    for (builder.region_paths.items, 0..) |region_paths, idx| {
        if (region_paths.items.len == 0) continue;
        if (wrote_region) try out.appendSlice(allocator, ", ");
        try out.print(allocator, "{{ regionId: {d}, trackedPathIds: [", .{idx + 1});
        for (region_paths.items, 0..) |path_id, path_idx| {
            if (path_idx > 0) try out.appendSlice(allocator, ", ");
            try out.print(allocator, "{d}", .{path_id});
        }
        try out.appendSlice(allocator, "] }");
        wrote_region = true;
    }
    try out.appendSlice(allocator, "] }");
}

fn collectTrackedGraphForNodes(
    component_model: *const component.ComponentUnit,
    nodes: []const browser_render_tree.Node,
    builder: *TrackedGraphBuilder,
    allocator: std.mem.Allocator,
) !void {
    for (nodes) |node| {
        switch (node) {
            .text => {},
            .interpolation => |interp| try appendRegionTrackedPaths(component_model, interp.expression, builder, allocator),
            .element => |element| {
                for (element.bind_effects) |effect| {
                    switch (effect) {
                        .bind => |bind| try appendRegionTrackedPaths(component_model, bind.expression, builder, allocator),
                        .event => {},
                    }
                }
                try collectTrackedGraphForNodes(component_model, element.children, builder, allocator);
            },
            .conditional => |conditional| {
                try appendRegionTrackedPaths(component_model, conditional.condition, builder, allocator);
            },
            .for_loop => |for_loop| {
                try appendRegionTrackedPaths(component_model, for_loop.iterable_expr, builder, allocator);
            },
            .component => |component_node| {
                var paths = std.ArrayList(usize).empty;
                errdefer paths.deinit(allocator);
                for (component_node.bind_effects) |effect| {
                    switch (effect) {
                        .bind => |bind| try collectTrackedPathIds(component_model, bind.expression, &paths, builder, allocator),
                        .event => {},
                    }
                }
                for (component_node.event_effects) |effect| {
                    switch (effect) {
                        .bind => |bind| try collectTrackedPathIds(component_model, bind.expression, &paths, builder, allocator),
                        .event => |event| try collectTrackedPathIds(component_model, event.expression, &paths, builder, allocator),
                    }
                }
                try builder.region_paths.append(allocator, paths);
            },
            .slot_outlet => {
                try builder.region_paths.append(allocator, std.ArrayList(usize).empty);
            },
        }
    }
}

fn appendRegionTrackedPaths(
    component_model: *const component.ComponentUnit,
    expr: []const u8,
    builder: *TrackedGraphBuilder,
    allocator: std.mem.Allocator,
) !void {
    var paths = std.ArrayList(usize).empty;
    errdefer paths.deinit(allocator);
    try collectTrackedPathIds(component_model, expr, &paths, builder, allocator);
    try builder.region_paths.append(allocator, paths);
}

fn collectTrackedPathIds(
    component_model: *const component.ComponentUnit,
    expr: []const u8,
    path_ids: *std.ArrayList(usize),
    builder: *TrackedGraphBuilder,
    allocator: std.mem.Allocator,
) !void {
    var i: usize = 0;
    while (i < expr.len) {
        const ch = expr[i];
        if (!isIdentStart(ch)) {
            i += 1;
            continue;
        }

        const root_start = i;
        i += 1;
        while (i < expr.len and isIdentContinue(expr[i])) i += 1;
        const root_name = expr[root_start..i];

        if (isKeyword(root_name)) continue;
        if (isPropertyAccessExpr(expr, root_start)) continue;
        if (tracked_root.kindByName(component_model, root_name) == null) continue;

        var cursor = i;
        var segment_count: usize = 0;
        var leaf_end = i;

        while (true) {
            const dot_index = nextNonSpaceIndex(expr, cursor) orelse break;
            if (expr[dot_index] != '.') break;

            var segment_start = dot_index + 1;
            while (segment_start < expr.len and isWhitespace(expr[segment_start])) segment_start += 1;
            if (segment_start >= expr.len or !isIdentStart(expr[segment_start])) break;

            var segment_end = segment_start + 1;
            while (segment_end < expr.len and isIdentContinue(expr[segment_end])) segment_end += 1;

            const call_index = nextNonSpaceIndex(expr, segment_end);
            if (call_index != null and expr[call_index.?] == '(') break;

            segment_count += 1;
            leaf_end = segment_end;
            cursor = segment_end;
        }

        if (segment_count == 0) continue;

        const full_path = std.mem.trimEnd(u8, expr[root_start..leaf_end], " \t\r\n");
        const leaf_path_id = try builder.ensurePathChain(full_path);
        try appendUniqueUsize(allocator, path_ids, leaf_path_id);
    }
}

fn countRegions(nodes: []const browser_render_tree.Node) usize {
    var total: usize = 0;
    for (nodes) |node| {
        switch (node) {
            .text => {},
            .interpolation => total += 1,
            .element => |element| {
                for (element.bind_effects) |effect| {
                    switch (effect) {
                        .bind => total += 1,
                        .event => {},
                    }
                }
                total += countRegions(element.children);
            },
            .conditional => {
                total += 1;
            },
            .for_loop => {
                total += 1;
            },
            .component => {
                total += 1;
            },
            .slot_outlet => {
                total += 1;
            },
        }
    }
    return total;
}

fn emitTextRegionUpdateFunction(
    interp: browser_render_tree.InterpolationNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.print(allocator, "function updateRegion_text_{d}(instance, scope, refs) {{\n", .{interp.ref_id});
    try emitInterpolationUpdate(interp, bindings_json, out, allocator, 1, "scope", "refs");
    try out.appendSlice(allocator, "}\n");
}

fn emitAttributeRegionUpdateFunction(
    ref_id: usize,
    target_name: []const u8,
    expression: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const suffix = try sanitizedIdentifierFragment(target_name, allocator);
    defer allocator.free(suffix);

    try out.print(allocator, "function updateRegion_attribute_{d}_{s}(instance, scope, refs) {{\n", .{ ref_id, suffix });
    try emitBoundAttributeUpdate(target_name, expression, "refs", ref_id, "scope", bindings_json, 1, out, allocator);
    try out.appendSlice(allocator, "}\n");
}

fn emitConditionalRegionUpdateFunction(
    conditional: browser_render_tree.ConditionalNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    _ = bindings_json; // conditional regions delegate to updateConditional_ which handles its own expressions
    try out.print(allocator, "function updateRegion_conditional_{d}(instance, scope, refs) {{\n", .{conditional.start_ref_id});
    try common.writeIndent(1, out, allocator);
    try out.print(allocator, "updateConditional_{d}(instance, scope);\n", .{conditional.start_ref_id});
    try out.appendSlice(allocator, "}\n");
}

fn emitLoopRegionUpdateFunction(
    for_loop: browser_render_tree.ForLoopNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    _ = bindings_json; // loop regions delegate to updateForLoop_ which handles its own expressions
    try out.print(allocator, "function updateRegion_loop_{d}(instance, scope, refs) {{\n", .{for_loop.start_ref_id});
    try common.writeIndent(1, out, allocator);
    try out.print(allocator, "updateForLoop_{d}(instance, scope);\n", .{for_loop.start_ref_id});
    try out.appendSlice(allocator, "}\n");
}

fn emitChildRegionUpdateFunction(
    component_node: browser_render_tree.ComponentNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.print(allocator, "function updateRegion_child_{d}(instance, scope, refs) {{\n", .{component_node.handle_ref_id});
    try emitChildComponentUpdateBody(component_node, bindings_json, out, allocator, 1, "scope", "refs");
    try out.appendSlice(allocator, "}\n");
}

fn emitSlotRegionUpdateFunction(
    slot_outlet: browser_render_tree.SlotOutletNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    _ = bindings_json; // slot regions don't directly resolve expressions
    try out.print(allocator, "function updateRegion_slot_{d}(instance, scope, refs) {{\n", .{slot_outlet.handle_ref_id});
    try emitSlotOutletUpdateBody(slot_outlet, out, allocator, 1, "scope", "refs");
    try out.appendSlice(allocator, "}\n");
}

fn emitSelectiveUpdateNode(
    component_model: *const component.ComponentUnit,
    node: browser_render_tree.Node,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
    loop_locals: []const []const u8,
    next_region_id: *usize,
) !void {
    switch (node) {
        .text => {},
        .interpolation => |interp| {
            var deps = DepList{};
            defer deps.deinit(allocator);
            try collectExpressionDeps(component_model, interp.expression, loop_locals, &deps, allocator);
            retainVisibleBindingDeps(component_model, &deps);
            const region_id = next_region_id.*;
            next_region_id.* += 1;
            try emitSelectiveStep(indent, deps.items.items, region_id, out, allocator);
            try out.print(allocator, "updateRegion_text_{d}(instance, {s}, {s});\n", .{ interp.ref_id, scope_expr, refs_expr });
            if (deps.items.items.len > 0 or region_id > 0) {
                try common.writeIndent(indent, out, allocator);
                try out.appendSlice(allocator, "}\n");
            }
        },
        .slot_outlet => |slot_outlet| {
            var deps = DepList{};
            defer deps.deinit(allocator);
            try collectNodeDeps(component_model, node, loop_locals, &deps, allocator);
            retainVisibleBindingDeps(component_model, &deps);
            const region_id = next_region_id.*;
            next_region_id.* += 1;
            try emitSelectiveStep(indent, deps.items.items, region_id, out, allocator);
            try out.print(allocator, "updateRegion_slot_{d}(instance, {s}, {s});\n", .{ slot_outlet.handle_ref_id, scope_expr, refs_expr });
            if (deps.items.items.len > 0 or region_id > 0) {
                try common.writeIndent(indent, out, allocator);
                try out.appendSlice(allocator, "}\n");
            }
        },
        .element => |element| {
            for (element.bind_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| {
                        var deps = DepList{};
                        defer deps.deinit(allocator);
                        try collectExpressionDeps(component_model, bind_dir.expression, loop_locals, &deps, allocator);
                        retainVisibleBindingDeps(component_model, &deps);
                        const suffix = try sanitizedIdentifierFragment(bind_dir.target_name, allocator);
                        defer allocator.free(suffix);
                        const region_id = next_region_id.*;
                        next_region_id.* += 1;
                        try emitSelectiveStep(indent, deps.items.items, region_id, out, allocator);
                        try out.print(allocator, "updateRegion_attribute_{d}_{s}(instance, {s}, {s});\n", .{
                            element.ref_id,
                            suffix,
                            scope_expr,
                            refs_expr,
                        });
                        if (deps.items.items.len > 0 or region_id > 0) {
                            try common.writeIndent(indent, out, allocator);
                            try out.appendSlice(allocator, "}\n");
                        }
                    },
                    .event => unreachable,
                }
            }
            for (element.children) |child| {
                try emitSelectiveUpdateNode(component_model, child, out, allocator, indent, scope_expr, refs_expr, loop_locals, next_region_id);
            }
        },
        .conditional => |conditional| {
            var deps = DepList{};
            defer deps.deinit(allocator);
            try collectNodeDeps(component_model, node, loop_locals, &deps, allocator);
            retainVisibleBindingDeps(component_model, &deps);
            const region_id = next_region_id.*;
            next_region_id.* += 1;
            try emitSelectiveStep(indent, deps.items.items, region_id, out, allocator);
            try out.print(allocator, "updateRegion_conditional_{d}(instance, {s}, {s});\n", .{ conditional.start_ref_id, scope_expr, refs_expr });
            if (deps.items.items.len > 0 or region_id > 0) {
                try common.writeIndent(indent, out, allocator);
                try out.appendSlice(allocator, "}\n");
            }
        },
        .component => |component_node| {
            var deps = DepList{};
            defer deps.deinit(allocator);
            try collectNodeDeps(component_model, node, loop_locals, &deps, allocator);
            retainVisibleBindingDeps(component_model, &deps);
            const region_id = next_region_id.*;
            next_region_id.* += 1;
            try emitSelectiveStep(indent, deps.items.items, region_id, out, allocator);
            try out.print(allocator, "updateRegion_child_{d}(instance, {s}, {s});\n", .{ component_node.handle_ref_id, scope_expr, refs_expr });
            if (deps.items.items.len > 0 or region_id > 0) {
                try common.writeIndent(indent, out, allocator);
                try out.appendSlice(allocator, "}\n");
            }
        },
        .for_loop => |for_loop| {
            var deps = DepList{};
            defer deps.deinit(allocator);
            try collectNodeDeps(component_model, node, loop_locals, &deps, allocator);
            retainVisibleBindingDeps(component_model, &deps);
            const region_id = next_region_id.*;
            next_region_id.* += 1;
            try emitSelectiveStep(indent, deps.items.items, region_id, out, allocator);
            try out.print(allocator, "updateRegion_loop_{d}(instance, {s}, {s});\n", .{ for_loop.start_ref_id, scope_expr, refs_expr });
            if (deps.items.items.len > 0 or region_id > 0) {
                try common.writeIndent(indent, out, allocator);
                try out.appendSlice(allocator, "}\n");
            }
        },
    }
}

const DepList = struct {
    items: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *DepList, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
    }

    fn appendUnique(self: *DepList, allocator: std.mem.Allocator, name: []const u8) !void {
        for (self.items.items) |item| {
            if (std.mem.eql(u8, item, name)) return;
        }
        try self.items.append(allocator, name);
    }
};

fn emitSelectiveStep(indent: usize, deps: []const []const u8, region_id: usize, out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    if (deps.len == 0 and region_id == 0) return;
    try common.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "if (");
    var wrote_clause = false;
    for (deps, 0..) |dep, idx| {
        _ = idx;
        if (wrote_clause) try out.appendSlice(allocator, " || ");
        try out.appendSlice(allocator, "dirtySet.has(");
        try common.emitString(dep, out, allocator);
        try out.appendSlice(allocator, ")");
        wrote_clause = true;
    }
    if (region_id != 0) {
        if (wrote_clause) try out.appendSlice(allocator, " || ");
        try out.print(allocator, "dirtyRegionSet.has({d})", .{region_id});
    }
    try out.appendSlice(allocator, ") {\n");
    try common.writeIndent(indent + 1, out, allocator);
}

fn collectNodeDeps(
    component_model: *const component.ComponentUnit,
    node: browser_render_tree.Node,
    loop_locals: []const []const u8,
    deps: *DepList,
    allocator: std.mem.Allocator,
) !void {
    switch (node) {
        .text => {},
        .interpolation => |interp| try collectExpressionDeps(component_model, interp.expression, loop_locals, deps, allocator),
        .element => |element| {
            for (element.bind_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| try collectExpressionDeps(component_model, bind_dir.expression, loop_locals, deps, allocator),
                    .event => {},
                }
            }
            for (element.children) |child| {
                try collectNodeDeps(component_model, child, loop_locals, deps, allocator);
            }
        },
        .conditional => |conditional| {
            try collectExpressionDeps(component_model, conditional.condition, loop_locals, deps, allocator);
            for (conditional.consequent) |child| {
                try collectNodeDeps(component_model, child, loop_locals, deps, allocator);
            }
            for (conditional.alternate) |child| {
                try collectNodeDeps(component_model, child, loop_locals, deps, allocator);
            }
        },
        .for_loop => |for_loop| {
            try collectExpressionDeps(component_model, for_loop.iterable_expr, loop_locals, deps, allocator);
            var next_locals = std.ArrayList([]const u8).empty;
            defer next_locals.deinit(allocator);
            try next_locals.appendSlice(allocator, loop_locals);
            try next_locals.append(allocator, for_loop.item_name);
            for (for_loop.body) |child| {
                try collectNodeDeps(component_model, child, next_locals.items, deps, allocator);
            }
        },
        .component => |component_node| {
            for (component_node.bind_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| try collectExpressionDeps(component_model, bind_dir.expression, loop_locals, deps, allocator),
                    .event => |event_dir| try collectExpressionDeps(component_model, event_dir.expression, loop_locals, deps, allocator),
                }
            }
            for (component_node.event_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| try collectExpressionDeps(component_model, bind_dir.expression, loop_locals, deps, allocator),
                    .event => |event_dir| try collectExpressionDeps(component_model, event_dir.expression, loop_locals, deps, allocator),
                }
            }
            for (component_node.slot_provisions) |slot| {
                for (slot.children) |child| {
                    try collectNodeDeps(component_model, child, loop_locals, deps, allocator);
                }
            }
        },
        .slot_outlet => |slot_outlet| {
            for (slot_outlet.fallback_children) |child| {
                try collectNodeDeps(component_model, child, loop_locals, deps, allocator);
            }
        },
    }
}

fn collectExpressionDeps(
    component_model: *const component.ComponentUnit,
    expr: []const u8,
    loop_locals: []const []const u8,
    deps: *DepList,
    allocator: std.mem.Allocator,
) anyerror!void {
    try collectExpressionDepsWithTrail(component_model, expr, loop_locals, deps, allocator, &.{});
}

fn collectExpressionDepsWithTrail(
    component_model: *const component.ComponentUnit,
    expr: []const u8,
    loop_locals: []const []const u8,
    deps: *DepList,
    allocator: std.mem.Allocator,
    call_trail: []const []const u8,
) anyerror!void {
    var i: usize = 0;
    while (i < expr.len) {
        const ch = expr[i];
        if (!isIdentStart(ch)) {
            i += 1;
            continue;
        }

        const start = i;
        i += 1;
        while (i < expr.len and isIdentContinue(expr[i])) i += 1;
        const ident = expr[start..i];
        const call = nextNonSpaceIs(expr, i, '(');

        if (isKeyword(ident)) continue;
        if (isPropertyAccessExpr(expr, start)) continue;
        if (call and tracked_root.isImportedBinding(component_model, ident)) continue;

        if (call) {
            if (findVisibleBinding(component_model, ident)) |binding| {
                try deps.appendUnique(allocator, ident);
                if (binding.callable and !containsName(call_trail, ident)) {
                    try collectCallableBindingDeps(component_model, binding, deps, allocator, call_trail);
                }
                continue;
            }
        }

        if (isVisibleBinding(component_model, ident) or containsName(loop_locals, ident)) {
            try deps.appendUnique(allocator, ident);
        }
    }
}

fn isVisibleBinding(component_model: *const component.ComponentUnit, name: []const u8) bool {
    return findVisibleBinding(component_model, name) != null;
}

fn findVisibleBinding(
    component_model: *const component.ComponentUnit,
    name: []const u8,
) ?sir.ScriptBinding {
    for (component_model.script.bindings) |binding| {
        if (binding.template_visible and std.mem.eql(u8, binding.name, name)) return binding;
    }
    return null;
}

fn retainVisibleBindingDeps(component_model: *const component.ComponentUnit, deps: *DepList) void {
    var write_index: usize = 0;
    for (deps.items.items) |dep| {
        if (!isVisibleBinding(component_model, dep)) continue;
        deps.items.items[write_index] = dep;
        write_index += 1;
    }
    deps.items.items.len = write_index;
}

fn nextNonSpaceIs(expr: []const u8, start: usize, needle: u8) bool {
    var cursor = start;
    while (cursor < expr.len and isWhitespace(expr[cursor])) cursor += 1;
    return cursor < expr.len and expr[cursor] == needle;
}

fn nextNonSpaceIndex(expr: []const u8, start: usize) ?usize {
    var cursor = start;
    while (cursor < expr.len) : (cursor += 1) {
        if (isWhitespace(expr[cursor])) continue;
        return cursor;
    }
    return null;
}

fn isPropertyAccessExpr(expr: []const u8, ident_start: usize) bool {
    var cursor = ident_start;
    while (cursor > 0) {
        cursor -= 1;
        if (isWhitespace(expr[cursor])) continue;
        return expr[cursor] == '.';
    }
    return false;
}

fn isKeyword(ident: []const u8) bool {
    const keywords = [_][]const u8{
        "true",
        "false",
        "null",
        "undefined",
        "typeof",
        "instanceof",
        "return",
        "new",
        "await",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, ident, keyword)) return true;
    }
    return false;
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_' or ch == '$';
}

fn isIdentContinue(ch: u8) bool {
    return isIdentStart(ch) or std.ascii.isDigit(ch);
}

fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t';
}

fn appendUniqueUsize(allocator: std.mem.Allocator, list: *std.ArrayList(usize), value: usize) !void {
    for (list.items) |item| {
        if (item == value) return;
    }
    try list.append(allocator, value);
}

fn collectCallableBindingDeps(
    component_model: *const component.ComponentUnit,
    binding: sir.ScriptBinding,
    deps: *DepList,
    allocator: std.mem.Allocator,
    call_trail: []const []const u8,
) anyerror!void {
    const helper = findHelperFacts(component_model, binding.name) orelse return;

    var next_trail = std.ArrayList([]const u8).empty;
    defer next_trail.deinit(allocator);
    try next_trail.appendSlice(allocator, call_trail);
    try next_trail.append(allocator, binding.name);

    for (helper.reads) |name| {
        try deps.appendUnique(allocator, name);
    }

    for (helper.calls) |name| {
        try deps.appendUnique(allocator, name);
        if (containsName(next_trail.items, name)) continue;
        if (findVisibleBinding(component_model, name)) |next_binding| {
            if (next_binding.callable) {
                try collectCallableBindingDeps(component_model, next_binding, deps, allocator, next_trail.items);
            }
        }
    }
}

fn findHelperFacts(
    component_model: *const component.ComponentUnit,
    name: []const u8,
) ?sir.HelperFacts {
    for (component_model.script.state_facts.helpers) |helper| {
        if (std.mem.eql(u8, helper.name, name)) return helper;
    }
    return null;
}

pub fn emitDestroyFunction(
    render_tree: browser_render_tree.Document,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator,
        \\function destroyDom(instance) {
        \\  const refs = instance.refs;
        \\
    );
    for (render_tree.nodes) |node| {
        try emitDestroyNode(node, out, allocator, 1, "refs");
    }
    try out.appendSlice(allocator,
        \\}
        \\
    );
}

pub fn emitUpdateNode(
    node: browser_render_tree.Node,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
) !void {
    switch (node) {
        .text => {},
        .interpolation => |interp| {
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "updateRegion_text_{d}(instance, {s}, {s});\n", .{ interp.ref_id, scope_expr, refs_expr });
        },
        .slot_outlet => |slot_outlet| {
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "updateRegion_slot_{d}(instance, {s}, {s});\n", .{ slot_outlet.handle_ref_id, scope_expr, refs_expr });
        },
        .element => |element| {
            for (element.bind_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| {
                        const suffix = try sanitizedIdentifierFragment(bind_dir.target_name, allocator);
                        defer allocator.free(suffix);
                        try common.writeIndent(indent, out, allocator);
                        try out.print(allocator, "updateRegion_attribute_{d}_{s}(instance, {s}, {s});\n", .{
                            element.ref_id,
                            suffix,
                            scope_expr,
                            refs_expr,
                        });
                    },
                    .event => unreachable,
                }
            }
            for (element.children) |child| {
                try emitUpdateNode(child, out, allocator, indent, scope_expr, refs_expr);
            }
        },
        .conditional => |conditional| {
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "updateRegion_conditional_{d}(instance, {s}, {s});\n", .{ conditional.start_ref_id, scope_expr, refs_expr });
        },
        .component => |component_node| {
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "updateRegion_child_{d}(instance, {s}, {s});\n", .{ component_node.handle_ref_id, scope_expr, refs_expr });
        },
        .for_loop => |for_loop| {
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "updateRegion_loop_{d}(instance, {s}, {s});\n", .{ for_loop.start_ref_id, scope_expr, refs_expr });
        },
    }
}

fn emitChildComponentUpdateBody(
    component_node: browser_render_tree.ComponentNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
) !void {
    if (componentHasProps(component_node)) {
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "{s}[{d}].setProps(", .{ refs_expr, component_node.handle_ref_id });
        try emitPropsObject(component_node.bind_effects, out, allocator, scope_expr, bindings_json);
        try out.appendSlice(allocator, ");\n");
    }
    if (componentHasEventHandlers(component_node)) {
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "{s}[{d}].setEventHandlers(", .{ refs_expr, component_node.handle_ref_id });
        try emitChildHandlersObject(component_node.event_effects, out, allocator, scope_expr, bindings_json);
        try out.appendSlice(allocator, ");\n");
    }
    if (componentHasSlots(component_node)) {
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "{s}[{d}].setSlots(", .{
            refs_expr,
            component_node.handle_ref_id,
        });
        try common.emitProjectedSlotObject(component_node, "instance", out, allocator);
        try out.appendSlice(allocator, ");\n");
    }
    if (componentNeedsParentUpdate(component_node)) {
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "{s}[{d}].update();\n", .{ refs_expr, component_node.handle_ref_id });
    }
}

fn emitSlotOutletUpdateBody(
    slot_outlet: browser_render_tree.SlotOutletNode,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
) !void {
    const next_slot_var_name = try std.fmt.allocPrint(allocator, "__next_slot_{d}", .{slot_outlet.handle_ref_id});
    defer allocator.free(next_slot_var_name);
    const current_slot_var_name = try std.fmt.allocPrint(allocator, "__current_slot_{d}", .{slot_outlet.handle_ref_id});
    defer allocator.free(current_slot_var_name);
    try emitSlotLookupLine(slot_outlet, next_slot_var_name, indent, out, allocator);
    try common.writeIndent(indent, out, allocator);
    try out.print(allocator, "const {s} = {s}[{d}];\n", .{
        current_slot_var_name,
        refs_expr,
        slot_outlet.handle_ref_id,
    });
    try common.writeIndent(indent, out, allocator);
    try out.print(allocator, "if ({s}) {{\n", .{next_slot_var_name});
    try common.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "if ({s} && {s} !== false) {{\n", .{
        current_slot_var_name,
        current_slot_var_name,
    });
    try common.writeIndent(indent + 2, out, allocator);
    try out.print(allocator, "{s}.update();\n", .{current_slot_var_name});
    try common.writeIndent(indent + 1, out, allocator);
    try out.appendSlice(allocator, "} else {\n");
    try common.writeIndent(indent + 2, out, allocator);
    try out.print(allocator, "{s}[{d}] = {s}.mountIntoBoundary({s}[{d}], {s}[{d}]);\n", .{
        refs_expr,
        slot_outlet.handle_ref_id,
        next_slot_var_name,
        refs_expr,
        slot_outlet.start_ref_id,
        refs_expr,
        slot_outlet.end_ref_id,
    });
    try common.writeIndent(indent + 1, out, allocator);
    try out.appendSlice(allocator, "}\n");
    try common.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "} else {\n");
    try common.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "if ({s} !== false) {{\n", .{current_slot_var_name});
    try common.writeIndent(indent + 2, out, allocator);
    try out.print(allocator, "if ({s} && typeof {s}.destroy === \"function\") {{ {s}.destroy(); }}\n", .{
        current_slot_var_name,
        current_slot_var_name,
        current_slot_var_name,
    });
    try common.writeIndent(indent + 2, out, allocator);
    try out.print(allocator, "{s}[{d}] = false;\n", .{ refs_expr, slot_outlet.handle_ref_id });
    const start_ref_expr = try std.fmt.allocPrint(allocator, "{s}[{d}]", .{ refs_expr, slot_outlet.start_ref_id });
    defer allocator.free(start_ref_expr);
    const end_ref_expr = try std.fmt.allocPrint(allocator, "{s}[{d}]", .{ refs_expr, slot_outlet.end_ref_id });
    defer allocator.free(end_ref_expr);
    try emitSlotFallbackReplaceLine(slot_outlet, start_ref_expr, end_ref_expr, scope_expr, indent + 2, out, allocator);
    try common.writeIndent(indent + 1, out, allocator);
    try out.appendSlice(allocator, "}\n");
    for (slot_outlet.fallback_children) |child| {
        try emitUpdateNode(child, out, allocator, indent + 1, scope_expr, refs_expr);
    }
    try common.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "}\n");
}

fn emitInterpolationUpdate(
    interp: browser_render_tree.InterpolationNode,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    scope_expr: []const u8,
    refs_expr: []const u8,
) !void {
    try common.writeIndent(indent, out, allocator);
    try out.print(allocator, "const __next_text_{d} = String((", .{interp.ref_id});
    try emitResolvedExpression(interp.expression, scope_expr, bindings_json, out, allocator);
    try out.appendSlice(allocator, ") ?? \"\");\n");
    try common.writeIndent(indent, out, allocator);
    try out.print(allocator, "if ({s}[{d}].data !== __next_text_{d}) {{\n", .{
        refs_expr,
        interp.ref_id,
        interp.ref_id,
    });
    try common.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "{s}[{d}].data = __next_text_{d};\n", .{
        refs_expr,
        interp.ref_id,
        interp.ref_id,
    });
    try common.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "}\n");
}

pub fn emitDestroyNode(
    node: browser_render_tree.Node,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    indent: usize,
    refs_expr: []const u8,
) !void {
    switch (node) {
        .text, .interpolation => {},
        .element => |element| {
            for (element.children) |child| {
                try emitDestroyNode(child, out, allocator, indent, refs_expr);
            }
        },
        .slot_outlet => |slot_outlet| {
            const current_slot_var_name = try std.fmt.allocPrint(allocator, "__destroy_slot_{d}", .{slot_outlet.handle_ref_id});
            defer allocator.free(current_slot_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = {s}[{d}];\n", .{
                current_slot_var_name,
                refs_expr,
                slot_outlet.handle_ref_id,
            });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "if ({s} && {s} !== false && typeof {s}.destroy === \"function\") {{\n", .{
                current_slot_var_name,
                current_slot_var_name,
                current_slot_var_name,
            });
            try common.writeIndent(indent + 1, out, allocator);
            try out.print(allocator, "{s}.destroy();\n", .{current_slot_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "} else {\n");
            for (slot_outlet.fallback_children) |child| {
                try emitDestroyNode(child, out, allocator, indent + 1, refs_expr);
            }
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
        },
        .conditional => |conditional| {
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "if ({s}[{d}] === true) {{\n", .{ refs_expr, conditional.state_ref_id });
            for (conditional.consequent) |child| {
                try emitDestroyNode(child, out, allocator, indent + 1, refs_expr);
            }
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "} else {\n");
            for (conditional.alternate) |child| {
                try emitDestroyNode(child, out, allocator, indent + 1, refs_expr);
            }
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
        },
        .component => |component_node| {
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "if ({s}[{d}] && typeof {s}[{d}].destroy === \"function\") {{\n", .{
                refs_expr,
                component_node.handle_ref_id,
                refs_expr,
                component_node.handle_ref_id,
            });
            try common.writeIndent(indent + 1, out, allocator);
            try out.print(allocator, "{s}[{d}].destroy();\n", .{ refs_expr, component_node.handle_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
        },
        .for_loop => |for_loop| {
            const records_var_name = try std.fmt.allocPrint(allocator, "__records_{d}", .{for_loop.state_ref_id});
            defer allocator.free(records_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "const {s} = {s}[{d}] ?? [];\n", .{
                records_var_name,
                refs_expr,
                for_loop.state_ref_id,
            });
            try common.writeIndent(indent, out, allocator);
            try out.print(allocator, "for (const record of {s}) {{\n", .{records_var_name});
            try common.writeIndent(indent + 1, out, allocator);
            try out.appendSlice(allocator, "if (record.handle && typeof record.handle.destroy === \"function\") {\n");
            try common.writeIndent(indent + 2, out, allocator);
            try out.appendSlice(allocator, "record.handle.destroy();\n");
            try common.writeIndent(indent + 1, out, allocator);
            try out.appendSlice(allocator, "} else if (typeof record.destroy === \"function\") {\n");
            try common.writeIndent(indent + 2, out, allocator);
            try out.appendSlice(allocator, "record.destroy();\n");
            try common.writeIndent(indent + 1, out, allocator);
            try out.appendSlice(allocator, "}\n");
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
        },
    }
}

fn emitSlotLookupLine(
    slot_outlet: browser_render_tree.SlotOutletNode,
    var_name: []const u8,
    indent: usize,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try common.writeIndent(indent, out, allocator);
    if (slot_outlet.name) |name| {
        try out.print(allocator, "const {s} = instance.slots?.[", .{var_name});
        try common.emitString(name, out, allocator);
        try out.appendSlice(allocator, "];\n");
    } else {
        try out.print(allocator, "const {s} = instance.slots?.default;\n", .{var_name});
    }
}

fn emitSlotFallbackReplaceLine(
    slot_outlet: browser_render_tree.SlotOutletNode,
    start_expr: []const u8,
    end_expr: []const u8,
    scope_expr: []const u8,
    indent: usize,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try common.writeIndent(indent, out, allocator);
    try out.print(allocator, "replaceBetween({s}, {s}, createSlotFallbackFragment_{d}(instance, {s}));\n", .{
        start_expr,
        end_expr,
        slot_outlet.handle_ref_id,
        scope_expr,
    });
}

fn emitBoundAttributeUpdate(
    target_name: []const u8,
    expression: []const u8,
    refs_expr: []const u8,
    ref_id: usize,
    scope_expr: []const u8,
    bindings_json: []const u8,
    indent: usize,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const suffix = try sanitizedIdentifierFragment(target_name, allocator);
    defer allocator.free(suffix);

    if (std.mem.eql(u8, target_name, "checked") or
        std.mem.eql(u8, target_name, "disabled") or
        std.mem.eql(u8, target_name, "selected"))
    {
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __value_{d}_{s} = ", .{ ref_id, suffix });
        try emitResolvedExpression(expression, scope_expr, bindings_json, out, allocator);
        try out.appendSlice(allocator, ";\n");
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __next_{d}_{s} = Boolean(__value_{d}_{s});\n", .{
            ref_id,
            suffix,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "if ({s}[{d}].{s} !== __next_{d}_{s}) {{\n", .{
            refs_expr,
            ref_id,
            target_name,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "{s}[{d}].{s} = __next_{d}_{s};\n", .{
            refs_expr,
            ref_id,
            target_name,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "}\n");
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __has_attr_{d}_{s} = {s}[{d}].hasAttribute(\"{s}\");\n", .{
            ref_id,
            suffix,
            refs_expr,
            ref_id,
            target_name,
        });
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "if (__next_{d}_{s}) {{\n", .{ ref_id, suffix });
        try common.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "if (!__has_attr_{d}_{s}) {{ {s}[{d}].setAttribute(\"{s}\", \"\"); }}\n", .{
            ref_id,
            suffix,
            refs_expr,
            ref_id,
            target_name,
        });
        try common.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "} else {\n");
        try common.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "if (__has_attr_{d}_{s}) {{ {s}[{d}].removeAttribute(\"{s}\"); }}\n", .{
            ref_id,
            suffix,
            refs_expr,
            ref_id,
            target_name,
        });
        try common.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "}\n");
        return;
    }

    if (std.mem.eql(u8, target_name, "value")) {
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __value_{d}_{s} = ", .{ ref_id, suffix });
        try emitResolvedExpression(expression, scope_expr, bindings_json, out, allocator);
        try out.appendSlice(allocator, ";\n");
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __next_{d}_{s} = __value_{d}_{s} ?? \"\";\n", .{ ref_id, suffix, ref_id, suffix });
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "const __next_string_{d}_{s} = String(__next_{d}_{s});\n", .{
            ref_id,
            suffix,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "if ({s}[{d}].value !== __next_string_{d}_{s}) {{\n", .{
            refs_expr,
            ref_id,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent + 1, out, allocator);
        try out.print(allocator, "{s}[{d}].value = __next_string_{d}_{s};\n", .{
            refs_expr,
            ref_id,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "}\n");
        try common.writeIndent(indent, out, allocator);
        try out.print(allocator, "{s}[{d}].setAttribute(\"value\", __next_string_{d}_{s});\n", .{
            refs_expr,
            ref_id,
            ref_id,
            suffix,
        });
        return;
    }

    try common.writeIndent(indent, out, allocator);
    try out.print(allocator, "const __value_{d}_{s} = ", .{ ref_id, suffix });
    try emitResolvedExpression(expression, scope_expr, bindings_json, out, allocator);
    try out.appendSlice(allocator, ";\n");
    try common.writeIndent(indent, out, allocator);
    try out.print(allocator, "if (__value_{d}_{s} === false || __value_{d}_{s} === null || __value_{d}_{s} === undefined) {{\n", .{
        ref_id,
        suffix,
        ref_id,
        suffix,
        ref_id,
        suffix,
    });
    try common.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "if ({s}[{d}].hasAttribute(\"{s}\")) {{ {s}[{d}].removeAttribute(\"{s}\"); }}\n", .{
        refs_expr,
        ref_id,
        target_name,
        refs_expr,
        ref_id,
        target_name,
    });
    try common.writeIndent(indent, out, allocator);
    try out.print(allocator, "}} else if (__value_{d}_{s} === true) {{\n", .{ ref_id, suffix });
    try common.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "if (!{s}[{d}].hasAttribute(\"{s}\")) {{ {s}[{d}].setAttribute(\"{s}\", \"\"); }}\n", .{
        refs_expr,
        ref_id,
        target_name,
        refs_expr,
        ref_id,
        target_name,
    });
    try common.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "} else {\n");
    try common.writeIndent(indent + 1, out, allocator);
    try out.print(allocator, "{s}[{d}].setAttribute(\"{s}\", String(__value_{d}_{s}));\n", .{
        refs_expr,
        ref_id,
        target_name,
        ref_id,
        suffix,
    });
    try common.writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "}\n");
}

fn sanitizedIdentifierFragment(value: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (value, 0..) |ch, idx| {
        if ((idx == 0 and std.ascii.isAlphabetic(ch)) or
            (idx > 0 and (std.ascii.isAlphanumeric(ch) or ch == '_')))
        {
            try out.append(allocator, ch);
        } else if (idx == 0 and ch == '_') {
            try out.append(allocator, ch);
        } else {
            try out.append(allocator, '_');
        }
    }

    if (out.items.len == 0) {
        try out.appendSlice(allocator, "value");
    }

    return try out.toOwnedSlice(allocator);
}

pub fn componentHasProps(component_node: browser_render_tree.ComponentNode) bool {
    return component_node.bind_effects.len > 0;
}

pub fn componentHasEventHandlers(component_node: browser_render_tree.ComponentNode) bool {
    return component_node.event_effects.len > 0;
}

pub fn componentHasSlots(component_node: browser_render_tree.ComponentNode) bool {
    return component_node.slot_provisions.len > 0;
}

pub fn componentNeedsParentUpdate(component_node: browser_render_tree.ComponentNode) bool {
    return componentHasProps(component_node) or componentHasSlots(component_node);
}

pub fn emitPropsObject(
    effects: []const lir.DirectiveEffect,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    scope_expr: []const u8,
    bindings_json: []const u8,
) !void {
    try out.appendSlice(allocator, "{");
    for (effects, 0..) |effect, idx| {
        switch (effect) {
            .bind => |bind_dir| {
                if (idx > 0) try out.appendSlice(allocator, ", ");
                try out.print(allocator, "\"{s}\": ", .{bind_dir.target_name});
                try emitResolvedExpression(bind_dir.expression, scope_expr, bindings_json, out, allocator);
            },
            .event => unreachable,
        }
    }
    try out.appendSlice(allocator, "}");
}

pub fn emitChildHandlersObject(
    effects: []const lir.DirectiveEffect,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    scope_expr: []const u8,
    bindings_json: []const u8,
) !void {
    try out.appendSlice(allocator, "{");
    for (effects, 0..) |effect, idx| {
        switch (effect) {
            .event => |event_dir| {
                if (idx > 0) try out.appendSlice(allocator, ", ");
                try out.print(allocator, "\"{s}\": (payload) => {{ const resolved = ", .{event_dir.event_name});
                try emitResolvedExpression(event_dir.expression, scope_expr, bindings_json, out, allocator);
                try out.appendSlice(allocator, "; if (typeof resolved === \"function\") { return runOwnedBoundary(instance, () => resolved(payload)); } return undefined; }");
            },
            .bind => unreachable,
        }
    }
    try out.appendSlice(allocator, "}");
}

pub fn emitResolvedExpression(
    expression: []const u8,
    scope_expr: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const trimmed = std.mem.trim(u8, expression, &std.ascii.whitespace);
    if (trimmed.len == 0) {
        try out.appendSlice(allocator, "undefined");
        return;
    }

    if (isLiteralExpression(trimmed)) {
        try out.appendSlice(allocator, trimmed);
        return;
    }

    if (isSimpleAccessExpression(trimmed)) {
        try out.appendSlice(allocator, scope_expr);
        try out.append(allocator, '.');
        try out.appendSlice(allocator, trimmed);
        return;
    }

    if (try tryRewriteScopedCallExpression(trimmed, scope_expr, out, allocator)) {
        return;
    }

    if (try tryRewriteScopedExpression(trimmed, scope_expr, out, allocator)) {
        return;
    }

    if (bindings_json.len > 0) {
        if (script_backend.rewriteExpression(trimmed, bindings_json, scope_expr, allocator)) |rewritten| {
            defer allocator.free(rewritten);
            try out.appendSlice(allocator, rewritten);
            return;
        } else |_| {}
    }

    try out.appendSlice(allocator, "__weiv_evaluate(");
    try common.emitString(expression, out, allocator);
    try out.print(allocator, ", {s})", .{scope_expr});
}

fn isLiteralExpression(expression: []const u8) bool {
    if (expression.len == 0) return false;
    if ((expression[0] == '\'' and expression[expression.len - 1] == '\'') or
        (expression[0] == '"' and expression[expression.len - 1] == '"')) return expression.len >= 2;

    if (std.mem.eql(u8, expression, "true") or
        std.mem.eql(u8, expression, "false") or
        std.mem.eql(u8, expression, "null") or
        std.mem.eql(u8, expression, "undefined")) return true;

    var seen_digit = false;
    var seen_dot = false;
    for (expression, 0..) |ch, idx| {
        if (idx == 0 and (ch == '+' or ch == '-')) continue;
        if (std.ascii.isDigit(ch)) {
            seen_digit = true;
            continue;
        }
        if (ch == '.' and !seen_dot) {
            seen_dot = true;
            continue;
        }
        return false;
    }
    return seen_digit;
}

fn isSimpleAccessExpression(expression: []const u8) bool {
    var cursor: usize = 0;
    if (!consumeIdentifier(expression, &cursor)) return false;
    while (cursor < expression.len) {
        if (expression[cursor] != '.') return false;
        cursor += 1;
        if (!consumeIdentifier(expression, &cursor)) return false;
    }
    return true;
}

fn consumeIdentifier(expression: []const u8, cursor: *usize) bool {
    if (cursor.* >= expression.len or !isIdentStart(expression[cursor.*])) return false;
    cursor.* += 1;
    while (cursor.* < expression.len and isIdentContinue(expression[cursor.*])) cursor.* += 1;
    return true;
}

fn tryRewriteScopedExpression(
    expression: []const u8,
    scope_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    return try tryRewriteScopedExpressionWithLocals(expression, scope_expr, &.{}, out, allocator);
}

fn tryRewriteScopedExpressionWithLocals(
    expression: []const u8,
    scope_expr: []const u8,
    locals: []const []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    var rewritten = std.ArrayList(u8).empty;
    defer rewritten.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < expression.len) {
        const ch = expression[cursor];
        if (isWhitespace(ch)) {
            try rewritten.append(allocator, ch);
            cursor += 1;
            continue;
        }

        if (ch == '\'' or ch == '"') {
            const end = scanQuotedString(expression, cursor) orelse return false;
            try rewritten.appendSlice(allocator, expression[cursor .. end + 1]);
            cursor = end + 1;
            continue;
        }

        if (isIdentStart(ch)) {
            const start = cursor;
            cursor += 1;
            while (cursor < expression.len and isIdentContinue(expression[cursor])) cursor += 1;
            const ident = expression[start..cursor];

            if (nextNonSpaceIs(expression, cursor, '(')) return false;

            if (isKeyword(ident)) {
                try rewritten.appendSlice(allocator, ident);
                continue;
            }

            if (containsName(locals, ident)) {
                try rewritten.appendSlice(allocator, ident);
                continue;
            }

            if (isPropertyAccessExpr(expression, start)) {
                try rewritten.appendSlice(allocator, ident);
                continue;
            }

            try rewritten.appendSlice(allocator, scope_expr);
            try rewritten.append(allocator, '.');
            try rewritten.appendSlice(allocator, ident);
            continue;
        }

        if (std.ascii.isDigit(ch)) {
            const start = cursor;
            cursor += 1;
            while (cursor < expression.len and (std.ascii.isDigit(expression[cursor]) or expression[cursor] == '.')) cursor += 1;
            try rewritten.appendSlice(allocator, expression[start..cursor]);
            continue;
        }

        if (isSupportedExpressionPunctuation(ch)) {
            try rewritten.append(allocator, ch);
            cursor += 1;
            continue;
        }

        return false;
    }

    try out.appendSlice(allocator, rewritten.items);
    return true;
}

fn tryRewriteScopedCallExpression(
    expression: []const u8,
    scope_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    const open_paren = std.mem.indexOfScalar(u8, expression, '(') orelse return false;
    const callee = std.mem.trimEnd(u8, expression[0..open_paren], &std.ascii.whitespace);
    if (callee.len == 0 or !isSimpleAccessExpression(callee)) return false;

    const close_paren = findMatchingParen(expression, open_paren) orelse return false;
    const suffix = std.mem.trim(u8, expression[close_paren + 1 ..], &std.ascii.whitespace);
    if (suffix.len != 0 and !isSimpleCallSuffixExpression(suffix)) return false;

    var rewritten = std.ArrayList(u8).empty;
    defer rewritten.deinit(allocator);

    try rewritten.appendSlice(allocator, scope_expr);
    try rewritten.append(allocator, '.');
    try rewritten.appendSlice(allocator, callee);
    try rewritten.append(allocator, '(');

    const args_source = expression[open_paren + 1 .. close_paren];
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    try splitCallArguments(args_source, &args, allocator);

    for (args.items, 0..) |arg, idx| {
        if (idx > 0) try rewritten.appendSlice(allocator, ", ");
        const trimmed_arg = std.mem.trim(u8, arg, &std.ascii.whitespace);
        if (trimmed_arg.len == 0) continue;
        if (try tryRewriteArrowCallbackExpression(trimmed_arg, scope_expr, &rewritten, allocator)) continue;
        if (!try tryRewriteScopedExpression(trimmed_arg, scope_expr, &rewritten, allocator)) return false;
    }

    try rewritten.append(allocator, ')');
    if (suffix.len != 0) try rewritten.appendSlice(allocator, suffix);
    try out.appendSlice(allocator, rewritten.items);
    return true;
}

fn tryRewriteArrowCallbackExpression(
    expression: []const u8,
    scope_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    const arrow = std.mem.indexOf(u8, expression, "=>") orelse return false;
    const params_expr = std.mem.trim(u8, expression[0..arrow], &std.ascii.whitespace);
    const raw_body_expr = std.mem.trim(u8, expression[arrow + 2 ..], &std.ascii.whitespace);
    const body_expr = extractArrowCallbackReturnExpression(raw_body_expr) orelse return false;
    if (params_expr.len == 0 or body_expr.len == 0) return false;

    const param = parseArrowCallbackParam(params_expr) orelse return false;
    const locals = [_][]const u8{param};

    try out.appendSlice(allocator, params_expr);
    if (raw_body_expr.len > 0 and raw_body_expr[0] == '{') {
        try out.appendSlice(allocator, " => { return ");
        if (!try tryRewriteScopedExpressionWithLocals(body_expr, scope_expr, &locals, out, allocator)) return false;
        try out.appendSlice(allocator, "; }");
        return true;
    }

    try out.appendSlice(allocator, " => ");
    if (!try tryRewriteScopedExpressionWithLocals(body_expr, scope_expr, &locals, out, allocator)) return false;
    return true;
}

fn parseArrowCallbackParam(params_expr: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, params_expr, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    if (trimmed[0] == '(') {
        if (trimmed[trimmed.len - 1] != ')') return null;
        const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], &std.ascii.whitespace);
        if (inner.len == 0 or !isSimpleAccessExpression(inner)) return null;
        return inner;
    }
    if (!isSimpleAccessExpression(trimmed)) return null;
    return trimmed;
}

fn extractArrowCallbackReturnExpression(body_expr: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, body_expr, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    if (trimmed[0] != '{') return trimmed;
    if (trimmed[trimmed.len - 1] != '}') return null;

    const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], &std.ascii.whitespace);
    if (!std.mem.startsWith(u8, inner, "return")) return null;

    const return_expr = std.mem.trim(u8, inner["return".len..], &std.ascii.whitespace);
    if (return_expr.len == 0) return null;
    if (return_expr[return_expr.len - 1] != ';') return null;

    const expr = std.mem.trim(u8, return_expr[0 .. return_expr.len - 1], &std.ascii.whitespace);
    if (expr.len == 0) return null;
    return expr;
}

fn isSimpleCallSuffixExpression(expression: []const u8) bool {
    var cursor: usize = 0;
    while (cursor < expression.len) {
        if (expression[cursor] != '.') return false;
        cursor += 1;
        if (!consumeIdentifier(expression, &cursor)) return false;
    }
    return true;
}

fn containsName(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}

fn splitCallArguments(
    source: []const u8,
    out: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !void {
    var start: usize = 0;
    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_brace: usize = 0;
    var cursor: usize = 0;
    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (ch == '\'' or ch == '"') {
            const end = scanQuotedString(source, cursor) orelse return error.InvalidCallArgumentString;
            cursor = end;
            continue;
        }
        switch (ch) {
            '(' => depth_paren += 1,
            ')' => {
                if (depth_paren > 0) depth_paren -= 1;
            },
            '[' => depth_bracket += 1,
            ']' => {
                if (depth_bracket > 0) depth_bracket -= 1;
            },
            '{' => depth_brace += 1,
            '}' => {
                if (depth_brace > 0) depth_brace -= 1;
            },
            ',' => {
                if (depth_paren == 0 and depth_bracket == 0 and depth_brace == 0) {
                    try out.append(allocator, source[start..cursor]);
                    start = cursor + 1;
                }
            },
            else => {},
        }
    }
    if (start <= source.len) {
        try out.append(allocator, source[start..]);
    }
}

fn findMatchingParen(source: []const u8, open_paren: usize) ?usize {
    var depth: usize = 0;
    var cursor = open_paren;
    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (ch == '\'' or ch == '"') {
            cursor = scanQuotedString(source, cursor) orelse return null;
            continue;
        }
        if (ch == '(') {
            depth += 1;
            continue;
        }
        if (ch == ')') {
            depth -= 1;
            if (depth == 0) return cursor;
        }
    }
    return null;
}

fn scanQuotedString(expression: []const u8, start: usize) ?usize {
    const quote = expression[start];
    var cursor = start + 1;
    while (cursor < expression.len) : (cursor += 1) {
        if (expression[cursor] == '\\') {
            cursor += 1;
            continue;
        }
        if (expression[cursor] == quote) return cursor;
    }
    return null;
}

fn isSupportedExpressionPunctuation(ch: u8) bool {
    return switch (ch) {
        '.', '(', ')', '[', ']', '?', ':', '!', '=', '>', '<', '&', '|', '+', '-', '*', '/', '%', ',' => true,
        else => false,
    };
}
