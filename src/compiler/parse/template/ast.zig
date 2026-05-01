const std = @import("std");
const sfc = @import("../sfc.zig");
const directives = @import("directives.zig");

pub const NodeTag = enum {
    element,
    text,
    interpolation,
    slot_outlet,
};

pub const Attribute = struct {
    name: []const u8,
    value: ?[]const u8,
};

pub const ElementNode = struct {
    tag_name: []const u8,
    attributes: []Attribute,
    directives: []directives.Directive,
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

pub const SlotOutletNode = struct {
    name: ?[]const u8,
    fallback_children: []Node,
    span: sfc.Span,
};

pub const Node = union(NodeTag) {
    element: ElementNode,
    text: TextNode,
    interpolation: InterpolationNode,
    slot_outlet: SlotOutletNode,

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .element => |*element| {
                allocator.free(element.attributes);
                allocator.free(element.directives);
                for (element.children) |*child| child.deinit(allocator);
                allocator.free(element.children);
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
    source: []const u8,
    nodes: []Node,

    pub fn deinit(self: *Document, allocator: std.mem.Allocator) void {
        for (self.nodes) |*node| node.deinit(allocator);
        allocator.free(self.nodes);
        self.* = undefined;
    }
};
