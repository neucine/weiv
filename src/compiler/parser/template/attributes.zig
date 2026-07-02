const std = @import("std");
const ast = @import("ast.zig");
const sfc = @import("../sfc.zig");

pub const ParseError = error{
    OutOfMemory,
    UnterminatedTag,
};

pub fn parseAttributes(source: []const u8, base_offset: usize, allocator: std.mem.Allocator) ParseError![]ast.Attribute {
    var list = std.ArrayList(ast.Attribute).empty;
    defer list.deinit(allocator);

    var i: usize = 0;
    while (i < source.len) {
        while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
        if (i >= source.len) break;

        const name_start = i;
        while (i < source.len and !std.ascii.isWhitespace(source[i]) and source[i] != '=') : (i += 1) {}
        const name = source[name_start..i];

        while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}

        var value: ?[]const u8 = null;
        if (i < source.len and source[i] == '=') {
            i += 1;
            while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
            if (i < source.len and source[i] == '"') {
                const quote_start = i + 1;
                i += 1;
                while (i < source.len and source[i] != '"') : (i += 1) {}
                if (i >= source.len) return error.UnterminatedTag;
                value = source[quote_start..i];
                i += 1;
            } else {
                const value_start = i;
                while (i < source.len and !std.ascii.isWhitespace(source[i])) : (i += 1) {}
                value = source[value_start..i];
            }
        }

        try list.append(allocator, .{
            .name = name,
            .value = value,
            .span = .{ .start = base_offset + name_start, .end = base_offset + i },
        });
    }

    return try list.toOwnedSlice(allocator);
}
