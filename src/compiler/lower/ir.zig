const std = @import("std");

pub const NodeTag = enum {
    element,
    text,
    interpolation,
    conditional,
    for_loop,
    component,
    slot_outlet,
};

pub const DirectiveEffect = union(enum) {
    event: struct {
        event_name: []const u8,
        expression: []const u8,
    },
    bind: struct {
        target_name: []const u8,
        expression: []const u8,
    },
};

pub const Attribute = struct {
    name: []const u8,
    value: ?[]const u8,
};

pub const ElementNode = struct {
    tag_name: []const u8,
    attributes: []Attribute,
    effects: []DirectiveEffect,
    children: []Node,
};

pub const TextNode = struct {
    content: []const u8,
};

pub const InterpolationNode = struct {
    expression: []const u8,
};

pub const ConditionalNode = struct {
    condition: []const u8,
    consequent: []Node,
    alternate: []Node,
};

pub const ForLoopNode = struct {
    item_name: []const u8,
    iterable_expr: []const u8,
    body: []Node,
};

pub const ComponentNode = struct {
    tag_name: []const u8,
    effects: []DirectiveEffect,
    slot_provisions: []SlotProvision,
};

pub const SlotOutletNode = struct {
    name: ?[]const u8,
    fallback_children: []Node,
};

pub const SlotProvision = struct {
    name: ?[]const u8,
    children: []Node,
};

pub const Node = union(NodeTag) {
    element: ElementNode,
    text: TextNode,
    interpolation: InterpolationNode,
    conditional: ConditionalNode,
    for_loop: ForLoopNode,
    component: ComponentNode,
    slot_outlet: SlotOutletNode,

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .element => |*element| {
                allocator.free(element.attributes);
                allocator.free(element.effects);
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
            .component => |*component| {
                allocator.free(component.effects);
                for (component.slot_provisions) |*slot_provision| {
                    for (slot_provision.children) |*child| child.deinit(allocator);
                    allocator.free(slot_provision.children);
                }
                allocator.free(component.slot_provisions);
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
