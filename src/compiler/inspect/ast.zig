const std = @import("std");
const parser = @import("../parser/index.zig");

pub fn formatSource(source: []const u8, source_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const sfc_document = try parser.parseSfc(source);
    var template_document = try parser.parseTemplate(sfc_document.template.content, allocator);
    defer template_document.deinit(allocator);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.print("AST source={s}\n", .{source_path});
    try writer.print("sfc\n", .{});
    try writer.print("  template content=[{d}..{d}]\n", .{ sfc_document.template.content_span.start, sfc_document.template.content_span.end });
    try writer.print("  script content=[{d}..{d}]\n", .{ sfc_document.script.content_span.start, sfc_document.script.content_span.end });
    if (sfc_document.style) |style_section| {
        try writer.print("  style content=[{d}..{d}]\n", .{ style_section.content_span.start, style_section.content_span.end });
    } else {
        try writer.writeAll("  style <none>\n");
    }
    try writer.print("template-ast roots={d}\n", .{template_document.nodes.len});
    try formatNodes(template_document.nodes, 1, writer);
    return out.toOwnedSlice();
}

fn formatNodes(nodes: []const parser.template.Node, indent: usize, writer: anytype) !void {
    for (nodes) |node| {
        try writeIndent(indent, writer);
        switch (node) {
            .text => |text| try writer.print("text `{s}` [{d}..{d}]\n", .{ text.content, text.span.start, text.span.end }),
            .interpolation => |interp| try writer.print("interpolation `{s}` [{d}..{d}]\n", .{ interp.expression, interp.span.start, interp.span.end }),
            .slot_outlet => |slot_outlet| {
                if (slot_outlet.name) |name| {
                    try writer.print("slot name=\"{s}\" [{d}..{d}]\n", .{ name, slot_outlet.span.start, slot_outlet.span.end });
                } else {
                    try writer.print("slot <default> [{d}..{d}]\n", .{ slot_outlet.span.start, slot_outlet.span.end });
                }
                try formatNodes(slot_outlet.fallback_children, indent + 1, writer);
            },
            .element => |element| {
                try writer.print("element <{s}> attrs={d} directives={d} children={d} [{d}..{d}]\n", .{
                    element.tag_name,
                    element.attributes.len,
                    element.directives.len,
                    element.children.len,
                    element.span.start,
                    element.span.end,
                });
                for (element.attributes) |attribute| {
                    try writeIndent(indent + 1, writer);
                    if (attribute.value) |value| {
                        try writer.print("attr {s}=\"{s}\" [{d}..{d}]\n", .{ attribute.name, value, attribute.span.start, attribute.span.end });
                    } else {
                        try writer.print("attr {s} [{d}..{d}]\n", .{ attribute.name, attribute.span.start, attribute.span.end });
                    }
                }
                for (element.directives) |directive| {
                    try formatDirective(directive, indent + 1, writer);
                }
                try formatNodes(element.children, indent + 1, writer);
            },
        }
    }
}

fn formatDirective(directive: parser.template.Directive, indent: usize, writer: anytype) !void {
    try writeIndent(indent, writer);
    switch (directive) {
        .if_expr => |if_expr| try writer.print("directive if=\"{s}\"\n", .{if_expr.expression}),
        .else_branch => try writer.print("directive else\n", .{}),
        .for_expr => |for_expr| try writer.print("directive for {s} in {s}\n", .{ for_expr.item_name, for_expr.iterable_expr }),
        .event => |event_dir| try writer.print("directive on:{s}=\"{s}\"\n", .{ event_dir.event_name, event_dir.expression }),
        .bind => |bind_dir| try writer.print("directive bind:{s}=\"{s}\"\n", .{ bind_dir.target_name, bind_dir.expression }),
        .slot_assign => |slot_assign| try writer.print("directive slot:{s} [{d}..{d}]\n", .{ slot_assign.slot_name, slot_assign.span.start, slot_assign.span.end }),
    }
}

fn writeIndent(indent: usize, writer: anytype) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeAll("  ");
    }
}
