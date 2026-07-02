const std = @import("std");
const ast = @import("ast.zig");
const sfc = @import("../sfc.zig");

pub const ParseError = error{
    UnterminatedInterpolation,
};

pub fn parseInterpolation(source: []const u8, index: *usize) ParseError!ast.Node {
    const start = index.*;
    const close = std.mem.indexOfPos(u8, source, start + 2, "}}") orelse return error.UnterminatedInterpolation;
    const end = close + 2;
    const expression = std.mem.trim(u8, source[start + 2 .. close], &std.ascii.whitespace);
    index.* = end;
    return .{
        .interpolation = .{
            .expression = expression,
            .span = .{ .start = start, .end = end },
        },
    };
}

pub fn parseText(source: []const u8, index: *usize) ast.Node {
    const start = index.*;
    while (index.* < source.len and source[index.*] != '<' and !std.mem.eql(u8, source[index.*..@min(index.* + 2, source.len)], "{{")) : (index.* += 1) {}
    return .{
        .text = .{
            .content = source[start..index.*],
            .span = .{ .start = start, .end = index.* },
        },
    };
}
