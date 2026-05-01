const std = @import("std");
const component = @import("../../pipeline.zig");
const emit_js = @import("document_js.zig");
const ir = @import("../../lower/ir.zig");
const style = @import("scoped_css.zig");

pub fn emitModule(model: *const component.ComponentModel, allocator: std.mem.Allocator) ![]u8 {
    return emitModuleWithRuntimeImport(model, "./weiv-runtime.mjs", allocator);
}

pub fn emitModuleWithRuntimeImport(
    model: *const component.ComponentModel,
    runtime_import_path: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    const template_js = try emit_js.emitDocument(&model.ir_document, allocator);
    defer allocator.free(template_js);
    const preserved_imports = try buildPreservedImports(model, allocator);
    defer allocator.free(preserved_imports);
    const setup_js = try buildSetupCode(model, allocator);
    defer allocator.free(setup_js);
    const scope_id = try style.scopeIdForPath(model.source_path, allocator);
    defer allocator.free(scope_id);
    const css = try style.emitScopedCss(model, allocator);
    defer allocator.free(css);

    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);

    try out.appendSlice(allocator, preserved_imports);
    try out.writer(allocator).print("import {{ renderNodes, mountNodes, createBoundary, replaceBoundary }} from \"{s}\";\n\n", .{runtime_import_path});
    try out.appendSlice(allocator, setup_js);
    try out.appendSlice(allocator, "\n");
    try out.writer(allocator).print("export const scopeId = \"{s}\";\n", .{scope_id});
    try out.appendSlice(allocator, "export const css = ");
    try emit_js.emitString(css, &out, allocator);
    try out.appendSlice(allocator, ";\n\n");
    try out.appendSlice(allocator, template_js);
    try out.appendSlice(allocator,
        \\
        \\export function createInstance(props = {}, eventHandlers = {}) {
        \\  const emit = (name, payload) => {
        \\    if (typeof eventHandlers[name] === "function") {
        \\      return eventHandlers[name](payload);
        \\    }
        \\    return undefined;
        \\  };
        \\  return setup(props, emit);
        \\}
        \\
        \\export function renderToString(props = {}, components = {}) {
        \\  const instance = createInstance(props);
        \\  return renderNodes(template, instance.refresh(), components, scopeId);
        \\}
        \\
        \\export function renderToDomFragment(props = {}, components = {}, rerenderRoot = () => {}, eventHandlers = {}) {
        \\  const boundary = createBoundary("weiv:component");
        \\  mountIntoBoundary(boundary.start, boundary.end, props, components, eventHandlers);
        \\  return boundary.fragment;
        \\}
        \\
        \\export function mountIntoBoundary(start, end, props = {}, components = {}, eventHandlers = {}) {
        \\  const instance = createInstance(props, eventHandlers);
        \\  const rerender = () => {
        \\    replaceBoundary(
        \\      start,
        \\      end,
        \\      mountNodes(template, instance.refresh(), components, scopeId, rerender, eventHandlers, instance)
        \\    );
        \\  };
        \\  rerender();
        \\  return { instance, rerender };
        \\}
        \\
        \\export function mount(target, props = {}, components = {}, eventHandlers = {}) {
        \\  const boundary = createBoundary("weiv:root");
        \\  target.replaceChildren(boundary.fragment);
        \\  return mountIntoBoundary(boundary.start, boundary.end, props, components, eventHandlers);
        \\}
        \\
    );

    return try out.toOwnedSlice(allocator);
}

fn buildPreservedImports(model: *const component.ComponentModel, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);

    var remaining_named = std.ArrayList(usize){};
    defer remaining_named.deinit(allocator);
    for (model.script.imports, 0..) |record, idx| {
        if (!shouldPreserveImport(record, &model.script)) continue;
        if (std.mem.eql(u8, record.kind, "named")) {
            try remaining_named.append(allocator, idx);
            continue;
        }
        try emitSingleImport(record, &out, allocator);
    }

    var emitted_named = try allocator.alloc(bool, model.script.imports.len);
    defer allocator.free(emitted_named);
    @memset(emitted_named, false);

    for (remaining_named.items) |idx| {
        if (emitted_named[idx]) continue;
        const record = model.script.imports[idx];
        emitted_named[idx] = true;
        const record_source = try emittedImportSpecifier(record.source, allocator);
        defer allocator.free(record_source);

        var named_locals = std.ArrayList([]const u8){};
        var named_imported = std.ArrayList([]const u8){};
        defer {
            named_locals.deinit(allocator);
            named_imported.deinit(allocator);
        }

        try named_locals.append(allocator, record.local_name);
        try named_imported.append(allocator, record.imported_name orelse record.local_name);

        for (remaining_named.items) |other_idx| {
            if (other_idx == idx or emitted_named[other_idx]) continue;
            const other = model.script.imports[other_idx];
            if (!std.mem.eql(u8, other.source, record.source)) continue;
            emitted_named[other_idx] = true;
            try named_locals.append(allocator, other.local_name);
            try named_imported.append(allocator, other.imported_name orelse other.local_name);
        }

        try out.appendSlice(allocator, "import { ");
        for (named_locals.items, named_imported.items, 0..) |local_name, imported_name, named_idx| {
            if (std.mem.eql(u8, local_name, imported_name)) {
                try out.appendSlice(allocator, imported_name);
            } else {
                try out.writer(allocator).print("{s} as {s}", .{ imported_name, local_name });
            }
            if (named_idx + 1 < named_locals.items.len) {
                try out.appendSlice(allocator, ", ");
            }
        }
        try out.writer(allocator).print(" }} from \"{s}\";\n", .{record_source});
    }

    if (out.items.len > 0) try out.appendSlice(allocator, "\n");
    return try out.toOwnedSlice(allocator);
}

fn buildSetupCode(model: *const component.ComponentModel, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);

    try out.appendSlice(allocator,
        \\function setup(__weiv_props, __weiv_emit = () => {}) {
        \\  let props = __weiv_props;
        \\  const emit = __weiv_emit;
        \\
    );

    var lines = std.mem.tokenizeScalar(u8, model.script.transpiled_code, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, &std.ascii.whitespace);
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "import ")) continue;
        if (std.mem.startsWith(u8, line, "export let props")) continue;
        if (std.mem.startsWith(u8, line, "export ")) {
            try out.appendSlice(allocator, "  ");
            try out.appendSlice(allocator, line["export ".len..]);
            try out.appendSlice(allocator, "\n");
            continue;
        }
        try out.appendSlice(allocator, "  ");
        try out.appendSlice(allocator, line);
        try out.appendSlice(allocator, "\n");
    }

    try out.appendSlice(allocator, "  const __weiv_scope = {};\n");
    try out.appendSlice(allocator, "  function __weiv_refresh() {\n");
    try out.appendSlice(allocator, "    __weiv_scope.props = props;\n");
    try out.appendSlice(allocator, "    __weiv_scope.emit = emit;\n");
    for (model.script.bindings) |binding| {
        if (binding.template_visible and
            !std.mem.eql(u8, binding.kind, "import"))
        {
            try out.writer(allocator).print("    __weiv_scope.{s} = {s};\n", .{ binding.name, binding.name });
        }
    }
    try out.appendSlice(allocator, "    return __weiv_scope;\n");
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  return { scope: __weiv_scope, refresh: __weiv_refresh };\n}\n");

    return try out.toOwnedSlice(allocator);
}

fn emitSingleImport(
    record: @import("../../analyze/ts/analysis.zig").ImportRecord,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const record_source = try emittedImportSpecifier(record.source, allocator);
    defer allocator.free(record_source);
    if (std.mem.eql(u8, record.kind, "side_effect")) {
        try out.writer(allocator).print("import \"{s}\";\n", .{record_source});
        return;
    }
    if (std.mem.eql(u8, record.kind, "default")) {
        try out.writer(allocator).print("import {s} from \"{s}\";\n", .{ record.local_name, record_source });
        return;
    }
    if (std.mem.eql(u8, record.kind, "namespace")) {
        try out.writer(allocator).print("import * as {s} from \"{s}\";\n", .{ record.local_name, record_source });
        return;
    }
}

fn shouldPreserveImport(
    record: @import("../../analyze/ts/analysis.zig").ImportRecord,
    script: *const @import("../../analyze/ts/analysis.zig").ScriptAnalysis,
) bool {
    if (std.mem.endsWith(u8, record.source, ".weiv")) return false;
    if (std.mem.eql(u8, record.kind, "side_effect")) return true;

    for (script.bindings) |binding| {
        if (!std.mem.eql(u8, binding.name, record.local_name)) continue;
        return !std.mem.eql(u8, binding.kind, "type_only");
    }
    return true;
}

fn emittedImportSpecifier(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return rewriteModuleExtension(source, allocator);
}

fn rewriteModuleExtension(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.endsWith(u8, source, ".ts")) {
        return try std.fmt.allocPrint(allocator, "{s}.js", .{source[0 .. source.len - ".ts".len]});
    }
    if (std.mem.endsWith(u8, source, ".mts")) {
        return try std.fmt.allocPrint(allocator, "{s}.mjs", .{source[0 .. source.len - ".mts".len]});
    }
    return try allocator.dupe(u8, source);
}
