const std = @import("std");
const component_unit = @import("../../component_unit.zig");
const browser_emit = @import("emit/index.zig");
const browser_render_tree = @import("render_tree/index.zig");
const setup = @import("emit/js_module/setup.zig");

pub const BrowserComponent = struct {
    unit: *const component_unit.ComponentUnit,
    render_tree: browser_render_tree.Document,
    scope_id: []const u8,
    css: []const u8,
    setup_js: []const u8,
    preserved_imports: []const u8,
    template_bindings_json: []const u8,

    pub fn deinit(self: *BrowserComponent, allocator: std.mem.Allocator) void {
        allocator.free(self.template_bindings_json);
        allocator.free(self.preserved_imports);
        allocator.free(self.setup_js);
        allocator.free(self.css);
        allocator.free(self.scope_id);
        self.render_tree.deinit(allocator);
        self.* = undefined;
    }
};

pub const Component = BrowserComponent;

pub fn build(unit: *const component_unit.ComponentUnit, allocator: std.mem.Allocator) !BrowserComponent {
    var render_tree = try browser_render_tree.lower(&unit.lir_document, allocator);
    errdefer render_tree.deinit(allocator);

    const scope_id = try browser_emit.scoped_css.scopeIdForPath(unit.source_path, allocator);
    errdefer allocator.free(scope_id);

    const css = try browser_emit.scoped_css.emitScopedCss(unit, allocator);
    errdefer allocator.free(css);

    const setup_js = try setup.buildSetupCode(unit, allocator);
    errdefer allocator.free(setup_js);

    const preserved_imports = try setup.buildPreservedImports(unit, allocator);
    errdefer allocator.free(preserved_imports);

    const template_bindings_json = try buildTemplateBindingsJson(unit, allocator);
    errdefer allocator.free(template_bindings_json);

    return .{
        .unit = unit,
        .render_tree = render_tree,
        .scope_id = scope_id,
        .css = css,
        .setup_js = setup_js,
        .preserved_imports = preserved_imports,
        .template_bindings_json = template_bindings_json,
    };
}

fn buildTemplateBindingsJson(unit: *const component_unit.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    var json = std.ArrayList(u8).empty;
    defer json.deinit(allocator);
    try json.append(allocator, '[');
    var first = true;
    for (unit.script.bindings) |binding| {
        if (!binding.template_visible) continue;
        if (!first) try json.append(allocator, ',');
        try json.append(allocator, '"');
        try json.appendSlice(allocator, binding.name);
        try json.append(allocator, '"');
        first = false;
    }
    try json.append(allocator, ']');
    return try json.toOwnedSlice(allocator);
}
