const std = @import("std");
const component = @import("../../component_unit.zig");
const sir = @import("../../sema/sir.zig");

pub const Kind = enum {
    imported_tracked,
    prop_tracked,
    local_tracked,

    pub fn label(self: Kind) []const u8 {
        return switch (self) {
            .imported_tracked => "imported-tracked",
            .prop_tracked => "prop-tracked",
            .local_tracked => "local-tracked",
        };
    }
};

pub fn kindByName(model: *const component.ComponentUnit, name: []const u8) ?Kind {
    if (isImportedBinding(model, name)) return .imported_tracked;
    if (isPropsBinding(model, name)) return .prop_tracked;
    if (isLocalTrackedBinding(model, name)) return .local_tracked;
    return null;
}

pub fn isImportedBinding(model: *const component.ComponentUnit, name: []const u8) bool {
    for (model.script.imports) |import_record| {
        if (std.mem.eql(u8, import_record.local_name, name)) return true;
    }
    return false;
}

pub fn isPropsBinding(model: *const component.ComponentUnit, name: []const u8) bool {
    if (model.script.props) |props_record| {
        if (props_record.props_binding_name) |binding_name| {
            return std.mem.eql(u8, binding_name, name);
        }
    }
    return false;
}

pub fn isLocalTrackedBinding(model: *const component.ComponentUnit, name: []const u8) bool {
    const binding = findVisibleBinding(model, name) orelse return false;
    if (!std.mem.eql(u8, binding.kind, "mutable") and !std.mem.eql(u8, binding.kind, "immutable")) return false;
    if (binding.callable) return false;
    if (isImportedBinding(model, name)) return false;
    if (isPropsBinding(model, name)) return false;

    for (model.script.state_facts.aliases) |alias| {
        if (std.mem.eql(u8, alias.target, name)) return false;
    }

    for (model.script.state_facts.mutations) |mutation| {
        if (!std.mem.eql(u8, mutation.binding, name)) continue;
        if (mutation.member_path == null) return false;
    }

    return true;
}

pub fn findVisibleBinding(model: *const component.ComponentUnit, name: []const u8) ?sir.ScriptBinding {
    for (model.script.bindings) |binding| {
        if (binding.template_visible and std.mem.eql(u8, binding.name, name)) return binding;
    }
    return null;
}
