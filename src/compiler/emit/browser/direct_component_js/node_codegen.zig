const std = @import("std");
const browser_plan = @import("../../../lower/browser_plan.zig");
const ir = @import("../../../lower/ir.zig");
const common = @import("common.zig");

pub fn emitCreateFunction(
    plan: browser_plan.Document,
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
    for (plan.nodes) |node| {
        try emitCreateNode(node, "fragment", scope_id, out, allocator, 1, "instance.refresh()", "refs");
    }
    try out.appendSlice(allocator,
        \\  return fragment;
        \\}
        \\
    );
}

pub fn emitCreateNode(
    node: browser_plan.Node,
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
            try out.writer(allocator).print("{s}.append(document.createTextNode(", .{parent_ref});
            try common.emitString(text.content, out, allocator);
            try out.appendSlice(allocator, "));\n");
        },
        .interpolation => |interp| {
            const var_name = try common.refVarName(interp.ref_id, allocator);
            defer allocator.free(var_name);
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("const {s} = document.createTextNode(\"\");\n", .{var_name});
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s};\n", .{ refs_expr, interp.ref_id, var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, var_name });
        },
        .slot_outlet => |slot_outlet| {
            const start_var_name = try common.refVarName(slot_outlet.start_ref_id, allocator);
            defer allocator.free(start_var_name);
            const end_var_name = try common.refVarName(slot_outlet.end_ref_id, allocator);
            defer allocator.free(end_var_name);
            const slot_var_name = try std.fmt.allocPrint(allocator, "__slot_{d}", .{slot_outlet.handle_ref_id});
            defer allocator.free(slot_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("const {s} = document.createComment(\"slot:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("const {s} = document.createComment(\"slot:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s};\n", .{ refs_expr, slot_outlet.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s};\n", .{ refs_expr, slot_outlet.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = false;\n", .{ refs_expr, slot_outlet.handle_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, end_var_name });
            try emitSlotLookupLine(slot_outlet, slot_var_name, indent, out, allocator);
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("if ({s}) {{\n", .{slot_var_name});
            try common.writeIndent(indent + 1, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s}.mountIntoBoundary({s}, {s});\n", .{
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
            try out.writer(allocator).print("const {s} = document.createElement(\"{s}\");\n", .{ var_name, element.tag_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s};\n", .{ refs_expr, element.ref_id, var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.setAttribute(\"data-weiv-scope\", \"{s}\");\n", .{ var_name, scope_id });
            for (element.attributes) |attribute| {
                try common.writeIndent(indent, out, allocator);
                try out.writer(allocator).print("{s}.setAttribute(\"{s}\", ", .{ var_name, attribute.name });
                try common.emitString(attribute.value orelse "", out, allocator);
                try out.appendSlice(allocator, ");\n");
            }
            for (element.event_effects) |effect| {
                switch (effect) {
                    .event => |event_dir| {
                        try common.writeIndent(indent, out, allocator);
                        try out.writer(allocator).print("{s}.addEventListener(\"{s}\", (event) => {{\n", .{ var_name, event_dir.event_name });
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "const beforeScope = cloneScope(instance.refresh());\n");
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "const resolved = evaluate(");
                        try common.emitString(event_dir.expression, out, allocator);
                        try out.writer(allocator).print(", {s});\n", .{scope_expr});
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "if (typeof resolved === \"function\") {\n");
                        try common.writeIndent(indent + 2, out, allocator);
                        try out.appendSlice(allocator, "resolved(event);\n");
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "}\n");
                        try common.writeIndent(indent + 1, out, allocator);
                        try out.appendSlice(allocator, "if (hasScopeChanged(beforeScope, instance.refresh())) {\n");
                        try common.writeIndent(indent + 2, out, allocator);
                        try out.appendSlice(allocator, "instance.update();\n");
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
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, var_name });
        },
        .conditional => |conditional| {
            const start_var_name = try common.refVarName(conditional.start_ref_id, allocator);
            defer allocator.free(start_var_name);
            const end_var_name = try common.refVarName(conditional.end_ref_id, allocator);
            defer allocator.free(end_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("const {s} = document.createComment(\"if:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("const {s} = document.createComment(\"if:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s};\n", .{ refs_expr, conditional.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s};\n", .{ refs_expr, conditional.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = undefined;\n", .{ refs_expr, conditional.state_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, end_var_name });
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
            try out.writer(allocator).print("const {s} = document.createComment(\"component:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("const {s} = document.createComment(\"component:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s};\n", .{ refs_expr, component_node.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s};\n", .{ refs_expr, component_node.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, end_var_name });
            if (props_var_name) |name| {
                try common.writeIndent(indent, out, allocator);
                try out.writer(allocator).print("const {s} = ", .{name});
                try emitPropsObject(component_node.bind_effects, out, allocator, scope_expr);
                try out.appendSlice(allocator, ";\n");
            }
            if (handlers_var_name) |name| {
                try common.writeIndent(indent, out, allocator);
                try out.writer(allocator).print("const {s} = ", .{name});
                try emitChildHandlersObject(component_node.event_effects, out, allocator, scope_expr);
                try out.appendSlice(allocator, ";\n");
            }
            if (has_slots) {
                try common.writeIndent(indent, out, allocator);
                try out.writer(allocator).print("const {s} = ", .{slots_var_name.?});
                try common.emitProjectedSlotObject(component_node, "instance", out, allocator);
                try out.appendSlice(allocator, ";\n");
            }
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s}.mountIntoBoundary({s}, {s}, {s}, {s}, {s});\n", .{
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
            try out.writer(allocator).print("const {s} = document.createComment(\"for:start\");\n", .{start_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("const {s} = document.createComment(\"for:end\");\n", .{end_var_name});
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s};\n", .{ refs_expr, for_loop.start_ref_id, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s};\n", .{ refs_expr, for_loop.end_ref_id, end_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = [];\n", .{ refs_expr, for_loop.state_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, end_var_name });
        },
    }
}

pub fn emitUpdateFunction(
    plan: browser_plan.Document,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator,
        \\function updateDom(instance) {
        \\  const refs = instance.refs;
        \\  const scope = instance.refresh();
        \\
    );
    for (plan.nodes) |node| {
        try emitUpdateNode(node, out, allocator, 1, "scope", "refs");
    }
    try out.appendSlice(allocator,
        \\}
        \\
    );
}

pub fn emitDestroyFunction(
    plan: browser_plan.Document,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator,
        \\function destroyDom(instance) {
        \\  const refs = instance.refs;
        \\
    );
    for (plan.nodes) |node| {
        try emitDestroyNode(node, out, allocator, 1, "refs");
    }
    try out.appendSlice(allocator,
        \\}
        \\
    );
}

pub fn emitUpdateNode(
    node: browser_plan.Node,
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
            try out.writer(allocator).print("const __next_text_{d} = String(evaluate(", .{interp.ref_id});
            try common.emitString(interp.expression, out, allocator);
            try out.writer(allocator).print(", {s}) ?? \"\");\n", .{scope_expr});
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("if ({s}[{d}].data !== __next_text_{d}) {{\n", .{
                refs_expr,
                interp.ref_id,
                interp.ref_id,
            });
            try common.writeIndent(indent + 1, out, allocator);
            try out.writer(allocator).print("{s}[{d}].data = __next_text_{d};\n", .{
                refs_expr,
                interp.ref_id,
                interp.ref_id,
            });
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
        },
        .slot_outlet => |slot_outlet| {
            const next_slot_var_name = try std.fmt.allocPrint(allocator, "__next_slot_{d}", .{slot_outlet.handle_ref_id});
            defer allocator.free(next_slot_var_name);
            const current_slot_var_name = try std.fmt.allocPrint(allocator, "__current_slot_{d}", .{slot_outlet.handle_ref_id});
            defer allocator.free(current_slot_var_name);
            try emitSlotLookupLine(slot_outlet, next_slot_var_name, indent, out, allocator);
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("const {s} = {s}[{d}];\n", .{
                current_slot_var_name,
                refs_expr,
                slot_outlet.handle_ref_id,
            });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("if ({s}) {{\n", .{next_slot_var_name});
            try common.writeIndent(indent + 1, out, allocator);
            try out.writer(allocator).print("if ({s} && {s} !== false) {{\n", .{
                current_slot_var_name,
                current_slot_var_name,
            });
            try common.writeIndent(indent + 2, out, allocator);
            try out.writer(allocator).print("{s}.update();\n", .{current_slot_var_name});
            try common.writeIndent(indent + 1, out, allocator);
            try out.appendSlice(allocator, "} else {\n");
            try common.writeIndent(indent + 2, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s}.mountIntoBoundary({s}[{d}], {s}[{d}]);\n", .{
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
            try out.writer(allocator).print("if ({s} !== false) {{\n", .{current_slot_var_name});
            try common.writeIndent(indent + 2, out, allocator);
            try out.writer(allocator).print("if ({s} && typeof {s}.destroy === \"function\") {{ {s}.destroy(); }}\n", .{
                current_slot_var_name,
                current_slot_var_name,
                current_slot_var_name,
            });
            try common.writeIndent(indent + 2, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = false;\n", .{ refs_expr, slot_outlet.handle_ref_id });
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
        },
        .element => |element| {
            for (element.bind_effects) |effect| {
                switch (effect) {
                    .bind => |bind_dir| {
                        try emitBoundAttributeUpdate(bind_dir.target_name, bind_dir.expression, refs_expr, element.ref_id, scope_expr, indent, out, allocator);
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
            try out.writer(allocator).print("updateConditional_{d}(instance, {s});\n", .{ conditional.start_ref_id, scope_expr });
        },
        .component => |component_node| {
            if (componentHasProps(component_node)) {
                try common.writeIndent(indent, out, allocator);
                try out.writer(allocator).print("{s}[{d}].setProps(", .{ refs_expr, component_node.handle_ref_id });
                try emitPropsObject(component_node.bind_effects, out, allocator, scope_expr);
                try out.appendSlice(allocator, ");\n");
            }
            if (componentHasEventHandlers(component_node)) {
                try common.writeIndent(indent, out, allocator);
                try out.writer(allocator).print("{s}[{d}].setEventHandlers(", .{ refs_expr, component_node.handle_ref_id });
                try emitChildHandlersObject(component_node.event_effects, out, allocator, scope_expr);
                try out.appendSlice(allocator, ");\n");
            }
            if (componentHasSlots(component_node)) {
                try common.writeIndent(indent, out, allocator);
                try out.writer(allocator).print("{s}[{d}].setSlots(", .{
                    refs_expr,
                    component_node.handle_ref_id,
                });
                try common.emitProjectedSlotObject(component_node, "instance", out, allocator);
                try out.appendSlice(allocator, ");\n");
            }
            if (componentNeedsParentUpdate(component_node)) {
                try common.writeIndent(indent, out, allocator);
                try out.writer(allocator).print("{s}[{d}].update();\n", .{ refs_expr, component_node.handle_ref_id });
            }
        },
        .for_loop => |for_loop| {
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("updateForLoop_{d}(instance, {s});\n", .{ for_loop.start_ref_id, scope_expr });
        },
    }
}

pub fn emitDestroyNode(
    node: browser_plan.Node,
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
            try out.writer(allocator).print("const {s} = {s}[{d}];\n", .{
                current_slot_var_name,
                refs_expr,
                slot_outlet.handle_ref_id,
            });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("if ({s} && {s} !== false && typeof {s}.destroy === \"function\") {{\n", .{
                current_slot_var_name,
                current_slot_var_name,
                current_slot_var_name,
            });
            try common.writeIndent(indent + 1, out, allocator);
            try out.writer(allocator).print("{s}.destroy();\n", .{current_slot_var_name});
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
            try out.writer(allocator).print("if ({s}[{d}] === true) {{\n", .{ refs_expr, conditional.state_ref_id });
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
            try out.writer(allocator).print("if ({s}[{d}] && typeof {s}[{d}].destroy === \"function\") {{\n", .{
                refs_expr,
                component_node.handle_ref_id,
                refs_expr,
                component_node.handle_ref_id,
            });
            try common.writeIndent(indent + 1, out, allocator);
            try out.writer(allocator).print("{s}[{d}].destroy();\n", .{ refs_expr, component_node.handle_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.appendSlice(allocator, "}\n");
        },
        .for_loop => |for_loop| {
            const records_var_name = try std.fmt.allocPrint(allocator, "__records_{d}", .{for_loop.state_ref_id});
            defer allocator.free(records_var_name);
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("const {s} = {s}[{d}] ?? [];\n", .{
                records_var_name,
                refs_expr,
                for_loop.state_ref_id,
            });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("for (const record of {s}) {{\n", .{records_var_name});
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
    slot_outlet: browser_plan.SlotOutletNode,
    var_name: []const u8,
    indent: usize,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try common.writeIndent(indent, out, allocator);
    if (slot_outlet.name) |name| {
        try out.writer(allocator).print("const {s} = instance.slots?.[", .{var_name});
        try common.emitString(name, out, allocator);
        try out.appendSlice(allocator, "];\n");
    } else {
        try out.writer(allocator).print("const {s} = instance.slots?.default;\n", .{var_name});
    }
}

fn emitSlotFallbackReplaceLine(
    slot_outlet: browser_plan.SlotOutletNode,
    start_expr: []const u8,
    end_expr: []const u8,
    scope_expr: []const u8,
    indent: usize,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try common.writeIndent(indent, out, allocator);
    try out.writer(allocator).print("replaceBetween({s}, {s}, createSlotFallbackFragment_{d}(instance, {s}));\n", .{
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
        try out.writer(allocator).print("const __value_{d}_{s} = evaluate(", .{ ref_id, suffix });
        try common.emitString(expression, out, allocator);
        try out.writer(allocator).print(", {s});\n", .{scope_expr});
        try common.writeIndent(indent, out, allocator);
        try out.writer(allocator).print("const __next_{d}_{s} = Boolean(__value_{d}_{s});\n", .{
            ref_id,
            suffix,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent, out, allocator);
        try out.writer(allocator).print("if ({s}[{d}].{s} !== __next_{d}_{s}) {{\n", .{
            refs_expr,
            ref_id,
            target_name,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent + 1, out, allocator);
        try out.writer(allocator).print("{s}[{d}].{s} = __next_{d}_{s};\n", .{
            refs_expr,
            ref_id,
            target_name,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "}\n");
        try common.writeIndent(indent, out, allocator);
        try out.writer(allocator).print("const __has_attr_{d}_{s} = {s}[{d}].hasAttribute(\"{s}\");\n", .{
            ref_id,
            suffix,
            refs_expr,
            ref_id,
            target_name,
        });
        try common.writeIndent(indent, out, allocator);
        try out.writer(allocator).print("if (__next_{d}_{s}) {{\n", .{ ref_id, suffix });
        try common.writeIndent(indent + 1, out, allocator);
        try out.writer(allocator).print("if (!__has_attr_{d}_{s}) {{ {s}[{d}].setAttribute(\"{s}\", \"\"); }}\n", .{
            ref_id,
            suffix,
            refs_expr,
            ref_id,
            target_name,
        });
        try common.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "} else {\n");
        try common.writeIndent(indent + 1, out, allocator);
        try out.writer(allocator).print("if (__has_attr_{d}_{s}) {{ {s}[{d}].removeAttribute(\"{s}\"); }}\n", .{
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
        try out.writer(allocator).print("const __value_{d}_{s} = evaluate(", .{ ref_id, suffix });
        try common.emitString(expression, out, allocator);
        try out.writer(allocator).print(", {s});\n", .{scope_expr});
        try common.writeIndent(indent, out, allocator);
        try out.writer(allocator).print("const __next_{d}_{s} = __value_{d}_{s} ?? \"\";\n", .{ ref_id, suffix, ref_id, suffix });
        try common.writeIndent(indent, out, allocator);
        try out.writer(allocator).print("const __next_string_{d}_{s} = String(__next_{d}_{s});\n", .{
            ref_id,
            suffix,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent, out, allocator);
        try out.writer(allocator).print("if ({s}[{d}].value !== __next_string_{d}_{s}) {{\n", .{
            refs_expr,
            ref_id,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent + 1, out, allocator);
        try out.writer(allocator).print("{s}[{d}].value = __next_string_{d}_{s};\n", .{
            refs_expr,
            ref_id,
            ref_id,
            suffix,
        });
        try common.writeIndent(indent, out, allocator);
        try out.appendSlice(allocator, "}\n");
        try common.writeIndent(indent, out, allocator);
        try out.writer(allocator).print("{s}[{d}].setAttribute(\"value\", __next_string_{d}_{s});\n", .{
            refs_expr,
            ref_id,
            ref_id,
            suffix,
        });
        return;
    }

    try common.writeIndent(indent, out, allocator);
    try out.writer(allocator).print("const __value_{d}_{s} = evaluate(", .{ ref_id, suffix });
    try common.emitString(expression, out, allocator);
    try out.writer(allocator).print(", {s});\n", .{scope_expr});
    try common.writeIndent(indent, out, allocator);
    try out.writer(allocator).print("if (__value_{d}_{s} === false || __value_{d}_{s} === null || __value_{d}_{s} === undefined) {{\n", .{
        ref_id,
        suffix,
        ref_id,
        suffix,
        ref_id,
        suffix,
    });
    try common.writeIndent(indent + 1, out, allocator);
    try out.writer(allocator).print("if ({s}[{d}].hasAttribute(\"{s}\")) {{ {s}[{d}].removeAttribute(\"{s}\"); }}\n", .{
        refs_expr,
        ref_id,
        target_name,
        refs_expr,
        ref_id,
        target_name,
    });
    try common.writeIndent(indent, out, allocator);
    try out.writer(allocator).print("}} else if (__value_{d}_{s} === true) {{\n", .{ ref_id, suffix });
    try common.writeIndent(indent + 1, out, allocator);
    try out.writer(allocator).print("if (!{s}[{d}].hasAttribute(\"{s}\")) {{ {s}[{d}].setAttribute(\"{s}\", \"\"); }}\n", .{
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
    try out.writer(allocator).print("{s}[{d}].setAttribute(\"{s}\", String(__value_{d}_{s}));\n", .{
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
    var out = std.ArrayList(u8){};
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

pub fn componentHasProps(component_node: browser_plan.ComponentNode) bool {
    return component_node.bind_effects.len > 0;
}

pub fn componentHasEventHandlers(component_node: browser_plan.ComponentNode) bool {
    return component_node.event_effects.len > 0;
}

pub fn componentHasSlots(component_node: browser_plan.ComponentNode) bool {
    return component_node.slot_provisions.len > 0;
}

pub fn componentNeedsParentUpdate(component_node: browser_plan.ComponentNode) bool {
    return componentHasProps(component_node) or componentHasSlots(component_node);
}

pub fn emitPropsObject(
    effects: []const ir.DirectiveEffect,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    scope_expr: []const u8,
) !void {
    try out.appendSlice(allocator, "{");
    for (effects, 0..) |effect, idx| {
        switch (effect) {
            .bind => |bind_dir| {
                if (idx > 0) try out.appendSlice(allocator, ", ");
                try out.writer(allocator).print("\"{s}\": evaluate(", .{bind_dir.target_name});
                try common.emitString(bind_dir.expression, out, allocator);
                try out.writer(allocator).print(", {s})", .{scope_expr});
            },
            .event => unreachable,
        }
    }
    try out.appendSlice(allocator, "}");
}

pub fn emitChildHandlersObject(
    effects: []const ir.DirectiveEffect,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    scope_expr: []const u8,
) !void {
    try out.appendSlice(allocator, "{");
    for (effects, 0..) |effect, idx| {
        switch (effect) {
            .event => |event_dir| {
                if (idx > 0) try out.appendSlice(allocator, ", ");
                try out.writer(allocator).print("\"{s}\": (payload) => {{ const resolved = evaluate(", .{event_dir.event_name});
                try common.emitString(event_dir.expression, out, allocator);
                try out.writer(allocator).print(", {s}); const beforeScope = cloneScope(instance.refresh()); let result = undefined; if (typeof resolved === \"function\") {{ result = resolved(payload); }} if (hasScopeChanged(beforeScope, instance.refresh())) {{ instance.update(); }} return result; }}", .{scope_expr});
            },
            .bind => unreachable,
        }
    }
    try out.appendSlice(allocator, "}");
}
