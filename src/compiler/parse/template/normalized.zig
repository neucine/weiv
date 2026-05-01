const std = @import("std");
const directives = @import("directives.zig");
const sfc = @import("../sfc.zig");

pub const NodeTag = enum {
    element,
    text,
    interpolation,
    conditional,
    for_loop,
    slot_outlet,
};

pub const ElementNode = struct {
    tag_name: []const u8,
    attributes: []const @import("ast.zig").Attribute,
    directives: []const directives.Directive,
    children: []Node,
    span: sfc.Span,
};

pub const TextNode = struct {
    content: []const u8,
    span: sfc.Span,
};

pub const InterpolationNode = struct {
    expression: []const u8,
    span: sfc.Span,
};

pub const ConditionalNode = struct {
    condition: []const u8,
    consequent: []Node,
    alternate: []Node,
    span: sfc.Span,
};

pub const ForLoopNode = struct {
    item_name: []const u8,
    iterable_expr: []const u8,
    body: []Node,
    span: sfc.Span,
};

pub const SlotOutletNode = struct {
    name: ?[]const u8,
    fallback_children: []Node,
    span: sfc.Span,
};

pub const Node = union(NodeTag) {
    element: ElementNode,
    text: TextNode,
    interpolation: InterpolationNode,
    conditional: ConditionalNode,
    for_loop: ForLoopNode,
    slot_outlet: SlotOutletNode,

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .element => |*element| {
                allocator.free(element.directives);
                for (element.children) |*child| child.deinit(allocator);
                allocator.free(element.children);
            },
            .conditional => |*conditional| {
                for (conditional.consequent) |*child| child.deinit(allocator);
                allocator.free(conditional.consequent);
                for (conditional.alternate) |*child| child.deinit(allocator);
                allocator.free(conditional.alternate);
            },
            .for_loop => |*for_loop| {
                for (for_loop.body) |*child| child.deinit(allocator);
                allocator.free(for_loop.body);
            },
            .slot_outlet => |*slot_outlet| {
                for (slot_outlet.fallback_children) |*child| child.deinit(allocator);
                allocator.free(slot_outlet.fallback_children);
            },
            .text, .interpolation => {},
        }
    }
};

pub const Document = struct {
    nodes: []Node,

    pub fn deinit(self: *Document, allocator: std.mem.Allocator) void {
        for (self.nodes) |*node| node.deinit(allocator);
        allocator.free(self.nodes);
        self.* = undefined;
    }
};
