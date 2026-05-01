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
            try out.writer(allocator).print("{s}[{d}] = null;\n", .{ refs_expr, slot_outlet.handle_ref_id });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, start_var_name });
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}.append({s});\n", .{ parent_ref, end_var_name });
            try common.writeIndent(indent, out, allocator);
            if (slot_outlet.name) |name| {
                try out.writer(allocator).print("const {s} = instance.slots?.[", .{slot_var_name});
                try common.emitString(name, out, allocator);
                try out.appendSlice(allocator, "];\n");
            } else {
                try out.writer(allocator).print("const {s} = instance.slots?.default;\n", .{slot_var_name});
            }
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
            try common.writeIndent(indent + 1, out, allocator);
            try out.appendSlice(allocator, "const fragment = document.createDocumentFragment();\n");
            for (slot_outlet.fallback_children) |child| {
                try emitCreateNode(child, "fragment", scope_id, out, allocator, indent + 1, scope_expr, refs_expr);
            }
            try common.writeIndent(indent + 1, out, allocator);
            try out.writer(allocator).print("replaceBetween({s}, {s}, fragment);\n", .{ start_var_name, end_var_name });
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
            const props_var_name = try std.fmt.allocPrint(allocator, "__props_{d}", .{component_node.handle_ref_id});
            defer allocator.free(props_var_name);
            const handlers_var_name = try std.fmt.allocPrint(allocator, "__handlers_{d}", .{component_node.handle_ref_id});
            defer allocator.free(handlers_var_name);
            const slots_var_name = if (component_node.slot_provisions.len > 0)
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
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("const {s} = ", .{props_var_name});
            try emitPropsObject(component_node.bind_effects, out, allocator, scope_expr);
            try out.appendSlice(allocator, ";\n");
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("const {s} = ", .{handlers_var_name});
            try emitChildHandlersObject(component_node.event_effects, out, allocator, scope_expr);
            try out.appendSlice(allocator, ";\n");
            if (component_node.slot_provisions.len > 0) {
                try common.writeIndent(indent, out, allocator);
                try out.writer(allocator).print("const __slots_{d} = ", .{component_node.handle_ref_id});
                try emitSlotsObject(component_node, out, allocator);
                try out.appendSlice(allocator, ";\n");
            }
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}] = {s}.mountIntoBoundary({s}, {s}, {s}, {s}, {s});\n", .{
                refs_expr,
                component_node.handle_ref_id,
                component_node.tag_name,
                start_var_name,
                end_var_name,
                props_var_name,
                handlers_var_name,
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
            try out.writer(allocator).print("{s}[{d}].data = String(evaluate(", .{ refs_expr, interp.ref_id });
            try common.emitString(interp.expression, out, allocator);
            try out.writer(allocator).print(", {s}) ?? \"\");\n", .{scope_expr});
        },
        .slot_outlet => |slot_outlet| {
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("if ({s}[{d}]) {{ {s}[{d}].update(); }} else {{\n", .{
                refs_expr,
                slot_outlet.handle_ref_id,
                refs_expr,
                slot_outlet.handle_ref_id,
            });
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
                        try common.writeIndent(indent, out, allocator);
                        try out.writer(allocator).print("applyBoundAttribute({s}[{d}], \"{s}\", evaluate(", .{ refs_expr, element.ref_id, bind_dir.target_name });
                        try common.emitString(bind_dir.expression, out, allocator);
                        try out.writer(allocator).print(", {s}));\n", .{scope_expr});
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
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}].setProps(", .{ refs_expr, component_node.handle_ref_id });
            try emitPropsObject(component_node.bind_effects, out, allocator, scope_expr);
            try out.appendSlice(allocator, ");\n");
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}].setEventHandlers(", .{ refs_expr, component_node.handle_ref_id });
            try emitChildHandlersObject(component_node.event_effects, out, allocator, scope_expr);
            try out.appendSlice(allocator, ");\n");
            if (component_node.slot_provisions.len > 0) {
                try common.writeIndent(indent, out, allocator);
                try out.writer(allocator).print("{s}[{d}].setSlots(", .{
                    refs_expr,
                    component_node.handle_ref_id,
                });
                try emitSlotsObject(component_node, out, allocator);
                try out.appendSlice(allocator, ");\n");
            }
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("{s}[{d}].update();\n", .{ refs_expr, component_node.handle_ref_id });
        },
        .for_loop => |for_loop| {
            try common.writeIndent(indent, out, allocator);
            try out.writer(allocator).print("updateForLoop_{d}(instance, {s});\n", .{ for_loop.start_ref_id, scope_expr });
        },
    }
}

fn emitSlotsObject(
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
