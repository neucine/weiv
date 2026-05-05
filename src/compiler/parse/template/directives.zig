const std = @import("std");
const ast = @import("ast.zig");
const sfc = @import("../sfc.zig");

pub const DirectiveTag = enum {
    if_expr,
    else_branch,
    for_expr,
    event,
    bind,
    slot_assign,
};

pub const IfDirective = struct {
    expression: []const u8,
};

pub const ElseDirective = struct {};

pub const ForDirective = struct {
    item_name: []const u8,
    iterable_expr: []const u8,
};

pub const EventDirective = struct {
    event_name: []const u8,
    expression: []const u8,
};

pub const BindDirective = struct {
    target_name: []const u8,
    expression: []const u8,
};

pub const SlotAssignDirective = struct {
    slot_name: []const u8,
    span: sfc.Span,
};

pub const Directive = union(DirectiveTag) {
    if_expr: IfDirective,
    else_branch: ElseDirective,
    for_expr: ForDirective,
    event: EventDirective,
    bind: BindDirective,
    slot_assign: SlotAssignDirective,
};

pub const SplitAttributes = struct {
    attributes: []ast.Attribute,
    directives: []Directive,
};

pub const ParseError = error{
    OutOfMemory,
    InvalidDirective,
};

pub fn split(raw_attributes: []const ast.Attribute, allocator: std.mem.Allocator) ParseError!SplitAttributes {
    var attributes = std.ArrayList(ast.Attribute){};
    defer attributes.deinit(allocator);
    var directives = std.ArrayList(Directive){};
    defer directives.deinit(allocator);

    for (raw_attributes) |attribute| {
        if (std.mem.eql(u8, attribute.name, "if")) {
            const value = attribute.value orelse return error.InvalidDirective;
            try directives.append(allocator, .{
                .if_expr = .{ .expression = value },
            });
            continue;
        }

        if (std.mem.eql(u8, attribute.name, "else")) {
            try directives.append(allocator, .{
                .else_branch = .{},
            });
            continue;
        }

        if (std.mem.eql(u8, attribute.name, "for")) {
            const value = attribute.value orelse return error.InvalidDirective;
            const parsed = parseForExpression(value) orelse return error.InvalidDirective;
            try directives.append(allocator, .{
                .for_expr = parsed,
            });
            continue;
        }

        if (std.mem.startsWith(u8, attribute.name, "on:")) {
            const value = attribute.value orelse return error.InvalidDirective;
            try directives.append(allocator, .{
                .event = .{
                    .event_name = attribute.name["on:".len..],
                    .expression = value,
                },
            });
            continue;
        }

        if (std.mem.startsWith(u8, attribute.name, "bind:")) {
            const value = attribute.value orelse return error.InvalidDirective;
            try directives.append(allocator, .{
                .bind = .{
                    .target_name = attribute.name["bind:".len..],
                    .expression = value,
                },
            });
            continue;
        }

        if (std.mem.startsWith(u8, attribute.name, "slot:")) {
            if (attribute.value != null) return error.InvalidDirective;
            const slot_name = attribute.name["slot:".len..];
            if (slot_name.len == 0) return error.InvalidDirective;
            try directives.append(allocator, .{
                .slot_assign = .{
                    .slot_name = slot_name,
                    .span = attribute.span,
                },
            });
            continue;
        }

        try attributes.append(allocator, attribute);
    }

    return .{
        .attributes = try attributes.toOwnedSlice(allocator),
        .directives = try directives.toOwnedSlice(allocator),
    };
}

fn parseForExpression(value: []const u8) ?ForDirective {
    const marker = " in ";
    const pos = std.mem.indexOf(u8, value, marker) orelse return null;
    const item_name = std.mem.trim(u8, value[0..pos], &std.ascii.whitespace);
    const iterable_expr = std.mem.trim(u8, value[pos + marker.len ..], &std.ascii.whitespace);
    if (item_name.len == 0 or iterable_expr.len == 0) return null;
    return .{
        .item_name = item_name,
        .iterable_expr = iterable_expr,
    };
}
