const std = @import("std");
const lir = @import("../../../lower/lir.zig");

pub fn splitEffects(
    allocator: std.mem.Allocator,
    effects: []const lir.DirectiveEffect,
    comptime effect_tag: std.meta.Tag(lir.DirectiveEffect),
) ![]lir.DirectiveEffect {
    var out = std.ArrayList(lir.DirectiveEffect).empty;
    defer out.deinit(allocator);

    for (effects) |effect| {
        if (std.meta.activeTag(effect) == effect_tag) {
            try out.append(allocator, effect);
        }
    }

    return try out.toOwnedSlice(allocator);
}
