const std = @import("std");
const ir = @import("../../lower/ir.zig");

pub fn emitDocument(document: *const ir.Document, allocator: std.mem.Allocator) anyerror![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);

    try out.appendSlice(allocator,
        \\export const template = 
    );
    try emitNodes(document.nodes, 0, &out, allocator);
    try out.appendSlice(allocator, ";\n");

    return try out.toOwnedSlice(allocator);
}

fn emitNodes(nodes: []const ir.Node, indent: usize, out: *std.ArrayList(u8), allocator: std.mem.Allocator) anyerror!void {
    try out.appendSlice(allocator, "[\n");
    for (nodes, 0..) |node, idx| {
        try writeIndent(indent + 1, out, allocator);
        try emitNode(node, indent + 1, out, allocator);
        if (idx + 1 < nodes.len) {
            try out.appendSlice(allocator, ",");
        }
        try out.appendSlice(allocator, "\n");
    }
    try writeIndent(indent, out, allocator);
    try out.appendSlice(allocator, "]");
}

fn emitNode(node: ir.Node, indent: usize, out: *std.ArrayList(u8), allocator: std.mem.Allocator) anyerror!void {
    switch (node) {
        .text => |text| {
            try out.writer(allocator).print("{{ kind: \"text\", content: ", .{});
            try emitString(text.content, out, allocator);
            try out.appendSlice(allocator, " }");
        },
        .interpolation => |interp| {
            try out.writer(allocator).print("{{ kind: \"interpolation\", expression: ", .{});
            try emitString(interp.expression, out, allocator);
            try out.appendSlice(allocator, " }");
        },
        .component => |component| {
            try out.appendSlice(allocator, "{ kind: \"component\", tag: ");
            try emitString(component.tag_name, out, allocator);
            try out.appendSlice(allocator, ", effects: ");
            try emitEffects(component.effects, indent, out, allocator);
            try out.appendSlice(allocator, " }");
        },
        .element => |element| {
            try out.appendSlice(allocator, "{ kind: \"element\", tag: ");
            try emitString(element.tag_name, out, allocator);
            try out.appendSlice(allocator, ", attributes: ");
            try emitAttributes(element.attributes, out, allocator);
            try out.appendSlice(allocator, ", effects: ");
            try emitEffects(element.effects, indent, out, allocator);
            try out.appendSlice(allocator, ", children: ");
            try emitNodes(element.children, indent, out, allocator);
            try out.appendSlice(allocator, " }");
        },
        .conditional => |conditional| {
            try out.appendSlice(allocator, "{ kind: \"conditional\", condition: ");
            try emitString(conditional.condition, out, allocator);
            try out.appendSlice(allocator, ", consequent: ");
            try emitNodes(conditional.consequent, indent, out, allocator);
            try out.appendSlice(allocator, ", alternate: ");
            try emitNodes(conditional.alternate, indent, out, allocator);
            try out.appendSlice(allocator, " }");
        },
        .for_loop => |for_loop| {
            try out.appendSlice(allocator, "{ kind: \"for\", item: ");
            try emitString(for_loop.item_name, out, allocator);
            try out.appendSlice(allocator, ", iterable: ");
            try emitString(for_loop.iterable_expr, out, allocator);
            try out.appendSlice(allocator, ", body: ");
            try emitNodes(for_loop.body, indent, out, allocator);
            try out.appendSlice(allocator, " }");
        },
    }
}

fn emitAttributes(attributes: []const ir.Attribute, out: *std.ArrayList(u8), allocator: std.mem.Allocator) anyerror!void {
    try out.appendSlice(allocator, "[");
    for (attributes, 0..) |attribute, idx| {
        try out.appendSlice(allocator, "{ name: ");
        try emitString(attribute.name, out, allocator);
        try out.appendSlice(allocator, ", value: ");
        if (attribute.value) |value| {
            try emitString(value, out, allocator);
        } else {
            try out.appendSlice(allocator, "null");
        }
        try out.appendSlice(allocator, " }");
        if (idx + 1 < attributes.len) {
            try out.appendSlice(allocator, ", ");
        }
    }
    try out.appendSlice(allocator, "]");
}

fn emitEffects(effects: []const ir.DirectiveEffect, indent: usize, out: *std.ArrayList(u8), allocator: std.mem.Allocator) anyerror!void {
    _ = indent;
    try out.appendSlice(allocator, "[");
    for (effects, 0..) |effect, idx| {
        switch (effect) {
            .bind => |bind_dir| {
                try out.appendSlice(allocator, "{ kind: \"bind\", target: ");
                try emitString(bind_dir.target_name, out, allocator);
                try out.appendSlice(allocator, ", expression: ");
                try emitString(bind_dir.expression, out, allocator);
                try out.appendSlice(allocator, " }");
            },
            .event => |event_dir| {
                try out.appendSlice(allocator, "{ kind: \"event\", event: ");
                try emitString(event_dir.event_name, out, allocator);
                try out.appendSlice(allocator, ", expression: ");
                try emitString(event_dir.expression, out, allocator);
                try out.appendSlice(allocator, " }");
            },
        }
        if (idx + 1 < effects.len) {
            try out.appendSlice(allocator, ", ");
        }
    }
    try out.appendSlice(allocator, "]");
}

pub fn emitString(value: []const u8, out: *std.ArrayList(u8), allocator: std.mem.Allocator) anyerror!void {
    try out.append(allocator, '"');
    for (value) |char| {
        switch (char) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, char),
        }
    }
    try out.append(allocator, '"');
}

fn writeIndent(indent: usize, out: *std.ArrayList(u8), allocator: std.mem.Allocator) anyerror!void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try out.appendSlice(allocator, "  ");
    }
}
