const std = @import("std");
const lower = @import("../lower/index.zig");

pub fn formatDocument(document: lower.lir.Document, allocator: std.mem.Allocator) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.print("LIR\n", .{});
    try formatNodes(document.nodes, 1, writer);
    return out.toOwnedSlice();
}

fn formatNodes(nodes: []const lower.lir.Node, indent: usize, writer: anytype) !void {
    for (nodes) |node| {
        try writeIndent(indent, writer);
        switch (node) {
            .text => |text| try writer.print("text `{s}`\n", .{text.content}),
            .interpolation => |interp| try writer.print("interpolation `{s}`\n", .{interp.expression}),
            .slot_outlet => |slot_outlet| {
                if (slot_outlet.name) |name| {
                    try writer.print("slot name=\"{s}\"\n", .{name});
                } else {
                    try writer.print("slot <default>\n", .{});
                }
                try formatNodes(slot_outlet.fallback_children, indent + 1, writer);
            },
            .component => |component_node| {
                try writer.print("component <{s}>\n", .{component_node.tag_name});
                try formatEffects(component_node.effects, indent + 1, writer);
                for (component_node.slot_provisions) |slot_provision| {
                    try writeIndent(indent + 1, writer);
                    if (slot_provision.name) |name| {
                        try writer.print("slot provision {s}\n", .{name});
                    } else {
                        try writer.print("slot provision <default>\n", .{});
                    }
                    try formatNodes(slot_provision.children, indent + 2, writer);
                }
            },
            .element => |element| {
                try writer.print("element <{s}>\n", .{element.tag_name});
                for (element.attributes) |attribute| {
                    try writeIndent(indent + 1, writer);
                    if (attribute.value) |value| {
                        try writer.print("attr {s}=\"{s}\"\n", .{ attribute.name, value });
                    } else {
                        try writer.print("attr {s}\n", .{attribute.name});
                    }
                }
                try formatEffects(element.effects, indent + 1, writer);
                try formatNodes(element.children, indent + 1, writer);
            },
            .conditional => |conditional| {
                try writer.print("conditional if=\"{s}\"\n", .{conditional.condition});
                try writeIndent(indent + 1, writer);
                try writer.print("consequent\n", .{});
                try formatNodes(conditional.consequent, indent + 2, writer);
                if (conditional.alternate.len > 0) {
                    try writeIndent(indent + 1, writer);
                    try writer.print("alternate\n", .{});
                    try formatNodes(conditional.alternate, indent + 2, writer);
                }
            },
            .for_loop => |for_loop| {
                try writer.print("for {s} in {s}\n", .{ for_loop.item_name, for_loop.iterable_expr });
                try formatNodes(for_loop.body, indent + 1, writer);
            },
        }
    }
}

fn formatEffects(effects: []const lower.lir.DirectiveEffect, indent: usize, writer: anytype) !void {
    for (effects) |effect| {
        try writeIndent(indent, writer);
        switch (effect) {
            .bind => |bind_dir| try writer.print("bind {s} <- {s}\n", .{ bind_dir.target_name, bind_dir.expression }),
            .event => |event_dir| try writer.print("event {s} -> {s}\n", .{ event_dir.event_name, event_dir.expression }),
        }
    }
}

fn writeIndent(indent: usize, writer: anytype) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeAll("  ");
    }
}
