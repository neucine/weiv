const std = @import("std");
const types = @import("browser_plan/types.zig");
const lowerer = @import("browser_plan/lowerer.zig");
pub const debug = @import("browser_plan/debug.zig");

pub const UnsupportedNodeKind = types.UnsupportedNodeKind;
pub const TextNode = types.TextNode;
pub const InterpolationNode = types.InterpolationNode;
pub const ElementNode = types.ElementNode;
pub const ConditionalNode = types.ConditionalNode;
pub const ForLoopNode = types.ForLoopNode;
pub const ComponentNode = types.ComponentNode;
pub const SlotOutletNode = types.SlotOutletNode;
pub const NodeTag = types.NodeTag;
pub const Node = types.Node;
pub const Document = types.Document;

pub fn lower(document: *const @import("ir.zig").Document, allocator: std.mem.Allocator) anyerror!Document {
    return try lowerer.lower(document, allocator);
}
