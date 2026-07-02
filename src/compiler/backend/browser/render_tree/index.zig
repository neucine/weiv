const std = @import("std");
const types = @import("types.zig");
const lowerer = @import("lowerer.zig");
pub const debug = @import("debug.zig");

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

pub fn lower(document: *const @import("../../../lower/lir.zig").Document, allocator: std.mem.Allocator) anyerror!Document {
    return try lowerer.lower(document, allocator);
}
