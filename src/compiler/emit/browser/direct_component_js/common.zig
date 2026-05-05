const std = @import("std");
const browser_plan = @import("../../../lower/browser_plan/index.zig");
const script_analysis = @import("../../../analyze/ts/analysis.zig");

pub fn emitString(value: []const u8, out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try out.append(allocator, '"');
    for (value) |ch| {
        switch (ch) {
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '"' => try out.appendSlice(allocator, "\\\""),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, ch),
        }
    }
    try out.append(allocator, '"');
}

pub fn refVarName(ref_id: usize, allocator: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(allocator, "__ref_{d}", .{ref_id});
}

pub fn writeIndent(indent: usize, out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try out.appendSlice(allocator, "  ");
    }
}

pub fn shouldPreserveImport(record: script_analysis.ImportRecord, script: *const script_analysis.ScriptAnalysis) bool {
    if (std.mem.eql(u8, record.kind, "side_effect")) return true;
    for (script.bindings) |binding| {
        if (!std.mem.eql(u8, binding.name, record.local_name)) continue;
        return !std.mem.eql(u8, binding.kind, "type_only");
    }
    return true;
}

pub fn emittedRuntimeImportSpecifier(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return rewriteModuleExtension(source, allocator);
}

pub fn emittedDirectImportSpecifier(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.endsWith(u8, source, ".weiv")) {
        return try std.fmt.allocPrint(allocator, "{s}.mjs", .{source[0 .. source.len - ".weiv".len]});
    }
    return rewriteModuleExtension(source, allocator);
}

pub fn rewriteModuleExtension(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.endsWith(u8, source, ".ts")) {
        return try std.fmt.allocPrint(allocator, "{s}.js", .{source[0 .. source.len - ".ts".len]});
    }
    if (std.mem.endsWith(u8, source, ".mts")) {
        return try std.fmt.allocPrint(allocator, "{s}.mjs", .{source[0 .. source.len - ".mts".len]});
    }
    return try allocator.dupe(u8, source);
}

pub fn emitProjectedSlotObject(
    component_node: browser_plan.ComponentNode,
    owner_instance_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    try out.appendSlice(allocator, "{ ");
    for (component_node.slot_provisions, 0..) |slot_provision, idx| {
        if (idx > 0) try out.appendSlice(allocator, ", ");
        if (slot_provision.name) |name| {
            try emitString(name, out, allocator);
        } else {
            try out.appendSlice(allocator, "default");
        }
        try out.writer(allocator).print(": {{ mountIntoBoundary: (start, end) => mountProjectedSlot_{d}_{d}(start, end, {s}) }}", .{
            component_node.handle_ref_id,
            idx,
            owner_instance_expr,
        });
    }
    try out.appendSlice(allocator, " }");
}
