const std = @import("std");
const ast = @import("ast.zig");
const attrs = @import("attributes.zig");
const common = @import("common.zig");
const directives = @import("directives.zig");
const interp = @import("interpolation.zig");
const sfc = @import("../sfc.zig");

pub const ParseError = error{
    OutOfMemory,
    UnexpectedCloseTag,
    UnterminatedTag,
    UnterminatedInterpolation,
    MismatchedCloseTag,
    InvalidDirective,
};

pub fn parse(source: []const u8, allocator: std.mem.Allocator) ParseError!ast.Document {
    var index: usize = 0;
    const nodes = try parseNodes(source, allocator, &index, null);
    return .{
        .source = source,
        .nodes = nodes,
    };
}

fn parseNodes(
    source: []const u8,
    allocator: std.mem.Allocator,
    index: *usize,
    until_tag: ?[]const u8,
) ParseError![]ast.Node {
    var list = std.ArrayList(ast.Node){};
    defer list.deinit(allocator);

    while (index.* < source.len) {
        if (until_tag) |tag_name| {
            if (startsWithCloseTag(source, index.*, tag_name)) break;
        }

        if (common.startsWith(source, index.*, "{{")) {
            try list.append(allocator, try interp.parseInterpolation(source, index));
            continue;
        }

        if (source[index.*] == '<') {
            if (common.startsWith(source, index.*, "</")) {
                if (until_tag == null) return error.UnexpectedCloseTag;
                break;
            }
            var node = try parseElement(source, allocator, index);
            errdefer node.deinit(allocator);
            try list.append(allocator, node);
            continue;
        }

        const text_node = interp.parseText(source, index);
        if (!common.isWhitespaceOnly(text_node.text.content)) {
            try list.append(allocator, text_node);
        }
    }

    return try list.toOwnedSlice(allocator);
}

fn parseElement(source: []const u8, allocator: std.mem.Allocator, index: *usize) ParseError!ast.Node {
    const open_start = index.*;
    const gt = common.findOpenTagEnd(source, open_start) orelse return error.UnterminatedTag;
    const open_end = gt + 1;
    const self_closing = gt > open_start and source[gt - 1] == '/';
    const raw_inner = source[open_start + 1 .. if (self_closing) gt - 1 else gt];
    const inner = std.mem.trim(u8, raw_inner, &std.ascii.whitespace);

    var parts = std.mem.tokenizeAny(u8, inner, &std.ascii.whitespace);
    const tag_name = parts.next() orelse return error.UnterminatedTag;
    const attrs_source = std.mem.trim(u8, inner[tag_name.len..], &std.ascii.whitespace);
    const raw_attributes = try attrs.parseAttributes(attrs_source, allocator);
    defer allocator.free(raw_attributes);
    const split_attributes = try directives.split(raw_attributes, allocator);
    errdefer {
        allocator.free(split_attributes.attributes);
        allocator.free(split_attributes.directives);
    }

    index.* = open_end;

    var children: []ast.Node = &.{};
    if (!self_closing) {
        children = try parseNodes(source, allocator, index, tag_name);
        errdefer {
            for (children) |*child| child.deinit(allocator);
            allocator.free(children);
        }
        try consumeCloseTag(source, index, tag_name);
    }

    return .{
        .element = .{
            .tag_name = tag_name,
            .attributes = split_attributes.attributes,
            .directives = split_attributes.directives,
            .children = children,
            .span = .{ .start = open_start, .end = index.* },
        },
    };
}

fn consumeCloseTag(source: []const u8, index: *usize, tag_name: []const u8) ParseError!void {
    if (!startsWithCloseTag(source, index.*, tag_name)) return error.MismatchedCloseTag;
    const gt = std.mem.indexOfScalarPos(u8, source, index.*, '>') orelse return error.UnterminatedTag;
    index.* = gt + 1;
}

fn startsWithCloseTag(source: []const u8, index: usize, tag_name: []const u8) bool {
    if (!common.startsWith(source, index, "</")) return false;
    if (index + 2 + tag_name.len >= source.len) return false;
    if (!std.mem.eql(u8, source[index + 2 .. index + 2 + tag_name.len], tag_name)) return false;
    const next = source[index + 2 + tag_name.len];
    return next == '>' or std.ascii.isWhitespace(next);
}
