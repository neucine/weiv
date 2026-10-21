const std = @import("std");
const browser_render_tree = @import("../../render_tree/index.zig");
const common = @import("common.zig");

pub fn emitSlotLookupLine(
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

pub fn emitSlotFallbackReplaceLine(
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
