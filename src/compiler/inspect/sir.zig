const std = @import("std");
const component_unit = @import("../component_unit.zig");
const sema = @import("../sema/index.zig");

pub fn formatComponent(component: *const component_unit.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    return formatData(component.source_path, &component.script, &component.template_bindings, allocator);
}

pub fn formatData(
    source_path: []const u8,
    script: *const sema.ScriptFacts,
    template_bindings: *const sema.TemplateBindings,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.print("SIR source={s}\n", .{source_path});
    try writer.print("script\n", .{});
    try writer.print("  ok: {any}\n", .{script.ok});
    if (script.props) |props| {
        try writer.print("  props export: {any}\n", .{props.has_props_export});
        if (props.props_type_name) |type_name| {
            try writer.print("  props type: {s}\n", .{type_name});
        }
        if (props.props_binding_name) |binding_name| {
            try writer.print("  props binding: {s}\n", .{binding_name});
        }
    }
    try writer.print("  imports: {d}\n", .{script.imports.len});
    for (script.imports) |import_record| {
        try writer.print("    - local={s} source={s}\n", .{ import_record.local_name, import_record.source });
    }
    try writer.print("  bindings: {d}\n", .{script.bindings.len});
    for (script.bindings) |binding_record| {
        try writer.print("    - {s} kind={s} visible={any} callable={any}\n", .{
            binding_record.name,
            binding_record.kind,
            binding_record.template_visible,
            binding_record.callable,
        });
    }
    try writer.print("  diagnostics: {d}\n", .{script.diagnostics.len});
    for (script.diagnostics) |diagnostic| {
        if (diagnostic.code) |code| {
            try writer.print("    - {s} {s}: {s} [{d}:{d}] [{d}..{d}]\n", .{
                diagnostic.severity,
                code,
                diagnostic.message,
                diagnostic.line,
                diagnostic.column,
                diagnostic.span_start,
                diagnostic.span_end,
            });
        } else {
            try writer.print("    - {s}: {s} [{d}:{d}] [{d}..{d}]\n", .{
                diagnostic.severity,
                diagnostic.message,
                diagnostic.line,
                diagnostic.column,
                diagnostic.span_start,
                diagnostic.span_end,
            });
        }
    }

    try writer.print("binding\n", .{});
    try writer.print("  component refs: {d}\n", .{template_bindings.component_refs.len});
    for (template_bindings.component_refs) |component_ref| {
        try writer.print("    - {s} resolved={any} [{d}..{d}]\n", .{
            component_ref.tag_name,
            component_ref.resolved,
            component_ref.span.start,
            component_ref.span.end,
        });
    }
    try writer.print("  diagnostics: {d}\n", .{template_bindings.diagnostics.len});
    for (template_bindings.diagnostics) |diagnostic| {
        try writer.print("    - {s} {s}: {s} - {s} [{d}..{d}]\n", .{
            diagnostic.severity,
            diagnostic.kind,
            diagnostic.name,
            diagnostic.message,
            diagnostic.span.start,
            diagnostic.span.end,
        });
    }
    return out.toOwnedSlice();
}
