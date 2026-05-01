const std = @import("std");
const ir = @import("../ir.zig");

pub fn splitEffects(
    allocator: std.mem.Allocator,
    effects: []const ir.DirectiveEffect,
    comptime effect_tag: std.meta.Tag(ir.DirectiveEffect),
) ![]ir.DirectiveEffect {
    var out = std.ArrayList(ir.DirectiveEffect){};
    defer out.deinit(allocator);

    for (effects) |effect| {
        if (std.meta.activeTag(effect) == effect_tag) {
            try out.append(allocator, effect);
        }
    }

    return try out.toOwnedSlice(allocator);
}
