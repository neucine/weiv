const std = @import("std");
const component_unit = @import("../../component_unit.zig");
const browser_render_tree = @import("render_tree/index.zig");

// Browser-specific lowering result. Its unit owns all data borrowed by render_tree;
// callers must deinit BrowserComponent before deiniting the ComponentUnit.
pub const BrowserComponent = struct {
    unit: *const component_unit.ComponentUnit,
    render_tree: browser_render_tree.Document,

    pub fn deinit(self: *BrowserComponent, allocator: std.mem.Allocator) void {
        self.render_tree.deinit(allocator);
        self.* = undefined;
    }
};

pub fn build(unit: *const component_unit.ComponentUnit, allocator: std.mem.Allocator) !BrowserComponent {
    return .{
        .unit = unit,
        .render_tree = try browser_render_tree.lower(&unit.lir_document, allocator),
    };
}
