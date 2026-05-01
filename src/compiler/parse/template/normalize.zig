const std = @import("std");
const ast = @import("ast.zig");
const directives = @import("directives.zig");
const normalized = @import("normalized.zig");

pub const NormalizeError = error{
    OutOfMemory,
    UnexpectedElse,
};

pub fn normalize(document: *const ast.Document, allocator: std.mem.Allocator) NormalizeError!normalized.Document {
    return .{
        .nodes = try normalizeNodes(document.nodes, allocator),
    };
}

fn normalizeNodes(nodes: []const ast.Node, allocator: std.mem.Allocator) NormalizeError![]normalized.Node {
    var out = std.ArrayList(normalized.Node){};
    defer out.deinit(allocator);

    var i: usize = 0;
    while (i < nodes.len) {
        const node = nodes[i];
        switch (node) {
            .text => |text| try out.append(allocator, .{
                .text = .{ .content = text.content, .span = text.span },
            }),
            .interpolation => |interp| try out.append(allocator, .{
                .interpolation = .{ .expression = interp.expression, .span = interp.span },
            }),
            .slot_outlet => |slot_outlet| {
                const fallback_nodes = try normalizeNodes(slot_outlet.fallback_children, allocator);
                errdefer freeNormalizedNodes(fallback_nodes, allocator);
                try out.append(allocator, .{
                    .slot_outlet = .{
                        .name = slot_outlet.name,
                        .fallback_children = fallback_nodes,
                        .span = slot_outlet.span,
                    },
                });
            },
            .element => |element| {
                if (findIfDirective(element.directives)) |if_dir| {
                    var alternate_nodes: []normalized.Node = &.{};
                    if (i + 1 < nodes.len) {
                        switch (nodes[i + 1]) {
                            .element => |next_element| {
                                if (hasElseDirective(next_element.directives)) {
                                    alternate_nodes = try normalizeNodeAsBranch(.{ .element = next_element }, allocator, .drop_else);
                                    i += 1;
                                }
                            },
                            else => {},
                        }
                    }

                    const consequent_nodes = try normalizeNodeAsBranch(node, allocator, .drop_if);
                    errdefer freeNormalizedNodes(consequent_nodes, allocator);
                    errdefer freeNormalizedNodes(alternate_nodes, allocator);

                    try out.append(allocator, .{
                        .conditional = .{
                            .condition = if_dir.expression,
                            .consequent = consequent_nodes,
                            .alternate = alternate_nodes,
                            .span = element.span,
                        },
                    });
                } else if (findForDirective(element.directives)) |for_dir| {
                    const body_nodes = try normalizeNodeAsBranch(node, allocator, .drop_for);
                    errdefer freeNormalizedNodes(body_nodes, allocator);
                    try out.append(allocator, .{
                        .for_loop = .{
                            .item_name = for_dir.item_name,
                            .iterable_expr = for_dir.iterable_expr,
                            .body = body_nodes,
                            .span = element.span,
                        },
                    });
                } else if (hasElseDirective(element.directives)) {
                    return error.UnexpectedElse;
                } else {
                    try out.append(allocator, try normalizePlainElement(&element, allocator, .keep_all));
                }
            },
        }
        i += 1;
    }

    return try out.toOwnedSlice(allocator);
}

const DirectiveFilter = enum {
    keep_all,
    drop_if,
    drop_else,
    drop_for,
};

fn normalizeNodeAsBranch(node: ast.Node, allocator: std.mem.Allocator, filter: DirectiveFilter) NormalizeError![]normalized.Node {
    switch (node) {
        .element => |element| {
            var single = try allocator.alloc(normalized.Node, 1);
            errdefer allocator.free(single);
            single[0] = try normalizePlainElement(&element, allocator, filter);
            return single;
        },
        .text => |text| {
            var single = try allocator.alloc(normalized.Node, 1);
            errdefer allocator.free(single);
            single[0] = .{ .text = .{ .content = text.content, .span = text.span } };
            return single;
        },
        .interpolation => |interp| {
            var single = try allocator.alloc(normalized.Node, 1);
            errdefer allocator.free(single);
            single[0] = .{ .interpolation = .{ .expression = interp.expression, .span = interp.span } };
            return single;
        },
        .slot_outlet => |slot_outlet| {
            var single = try allocator.alloc(normalized.Node, 1);
            errdefer allocator.free(single);
            const fallback_nodes = try normalizeNodes(slot_outlet.fallback_children, allocator);
            errdefer freeNormalizedNodes(fallback_nodes, allocator);
            single[0] = .{
                .slot_outlet = .{
                    .name = slot_outlet.name,
                    .fallback_children = fallback_nodes,
                    .span = slot_outlet.span,
                },
            };
            return single;
        },
    }
}

fn normalizePlainElement(element: *const ast.ElementNode, allocator: std.mem.Allocator, filter: DirectiveFilter) NormalizeError!normalized.Node {
    const child_nodes = try normalizeNodes(element.children, allocator);
    errdefer freeNormalizedNodes(child_nodes, allocator);
    const kept_directives = try filterDirectives(element.directives, allocator, filter);
    errdefer allocator.free(kept_directives);

    return .{
        .element = .{
            .tag_name = element.tag_name,
            .attributes = element.attributes,
            .directives = kept_directives,
            .children = child_nodes,
            .span = element.span,
        },
    };
}

fn filterDirectives(input: []const directives.Directive, allocator: std.mem.Allocator, filter: DirectiveFilter) NormalizeError![]directives.Directive {
    var out = std.ArrayList(directives.Directive){};
    defer out.deinit(allocator);

    for (input) |directive| {
        const keep = switch (filter) {
            .keep_all => !isStructuralDirective(directive),
            .drop_if => switch (directive) {
                .if_expr => false,
                else => !isStructuralDirective(directive),
            },
            .drop_else => switch (directive) {
                .else_branch => false,
                else => !isStructuralDirective(directive),
            },
            .drop_for => switch (directive) {
                .for_expr => false,
                else => !isStructuralDirective(directive),
            },
        };
        if (keep) try out.append(allocator, directive);
    }

    return try out.toOwnedSlice(allocator);
}

fn isStructuralDirective(directive: directives.Directive) bool {
    return switch (directive) {
        .if_expr, .else_branch, .for_expr => true,
        .event, .bind, .slot_assign => false,
    };
}

fn findIfDirective(input: []const directives.Directive) ?directives.IfDirective {
    for (input) |directive| {
        switch (directive) {
            .if_expr => |if_dir| return if_dir,
            else => {},
        }
    }
    return null;
}

fn findForDirective(input: []const directives.Directive) ?directives.ForDirective {
    for (input) |directive| {
        switch (directive) {
            .for_expr => |for_dir| return for_dir,
            else => {},
        }
    }
    return null;
}

fn hasElseDirective(input: []const directives.Directive) bool {
    for (input) |directive| {
        switch (directive) {
            .else_branch => return true,
            else => {},
        }
    }
    return false;
}

fn freeNormalizedNodes(nodes: []normalized.Node, allocator: std.mem.Allocator) void {
    for (nodes) |*node| node.deinit(allocator);
    allocator.free(nodes);
}
