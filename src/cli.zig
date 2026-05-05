const std = @import("std");
const component = @import("compiler/pipeline/index.zig");
const app_emit = @import("compiler/emit/browser/app_bundle.zig");
const emit_direct_js = @import("compiler/emit/browser/direct_component_js.zig");
const legacy_emit_js = @import("compiler/emit/browser/legacy/document_js.zig");
const legacy_emit_module_js = @import("compiler/emit/browser/legacy/component_module_js.zig");
const legacy_runtime_js = @import("compiler/emit/browser/legacy/shared_runtime_js.zig");
const style = @import("compiler/emit/browser/scoped_css.zig");
const browser_plan = @import("compiler/lower/browser_plan/index.zig");
const invalidation_graph = @import("compiler/lower/invalidation_graph/index.zig");
const sfc = @import("compiler/parse/sfc.zig");
const template = @import("compiler/parse/template/index.zig");
const parser_backend = @import("ffi/parser_backend.zig");

const LoadedComponent = struct {
    source: []u8,
    model: component.ComponentModel,

    fn deinit(self: *LoadedComponent, allocator: std.mem.Allocator) void {
        self.model.deinit(allocator);
        allocator.free(self.source);
    }
};

pub const CliReportedError = error{Reported};

pub fn run(allocator: std.mem.Allocator) !void {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    const command = args.next() orelse {
        try printUsage();
        return;
    };

    if (std.mem.eql(u8, command, "analyze-script")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
        defer allocator.free(source);

        const analysis_json = try parser_backend.analyzeScriptRaw(source, path, allocator);
        defer allocator.free(analysis_json);

        try std.fs.File.stdout().writeAll(analysis_json);
        try std.fs.File.stdout().writeAll("\n");
        return;
    }

    if (std.mem.eql(u8, command, "analyze-component")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        var loaded = try loadComponent(path, allocator);
        defer loaded.deinit(allocator);

        try printComponentAnalysis(loaded.model);
        return;
    }

    if (std.mem.eql(u8, command, "dump-ir")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        var loaded = try loadComponent(path, allocator);
        defer loaded.deinit(allocator);

        try printIrDocument(loaded.model.ir_document);
        return;
    }

    if (std.mem.eql(u8, command, "dump-browser-plan")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        var loaded = try loadComponent(path, allocator);
        defer loaded.deinit(allocator);

        var plan = try browser_plan.lower(&loaded.model.ir_document, allocator);
        defer plan.deinit(allocator);

        const formatted = try browser_plan.debug.formatDocument(&plan, allocator);
        defer allocator.free(formatted);
        try std.fs.File.stdout().writeAll(formatted);
        return;
    }

    if (std.mem.eql(u8, command, "dump-invalidation-graph") or std.mem.eql(u8, command, "dump-state-plan")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        var loaded = try loadComponent(path, allocator);
        defer loaded.deinit(allocator);

        var plan = try browser_plan.lower(&loaded.model.ir_document, allocator);
        defer plan.deinit(allocator);

        const formatted = try invalidation_graph.formatDocument(&loaded.model, &plan, allocator);
        defer allocator.free(formatted);
        try std.fs.File.stdout().writeAll(formatted);
        return;
    }

    if (std.mem.eql(u8, command, "emit-js")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        var loaded = try loadComponent(path, allocator);
        defer loaded.deinit(allocator);

        const js = try legacy_emit_js.emitDocument(&loaded.model.ir_document, allocator);
        defer allocator.free(js);
        try std.fs.File.stdout().writeAll(js);
        return;
    }

    if (std.mem.eql(u8, command, "emit-render-js")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        var loaded = try loadComponent(path, allocator);
        defer loaded.deinit(allocator);

        const js = try legacy_emit_module_js.emitModule(&loaded.model, allocator);
        defer allocator.free(js);
        try std.fs.File.stdout().writeAll(js);
        return;
    }

    if (std.mem.eql(u8, command, "emit-browser-direct-js")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        var loaded = try loadComponent(path, allocator);
        defer loaded.deinit(allocator);

        const js = try emit_direct_js.emitModule(&loaded.model, allocator);
        defer allocator.free(js);
        try std.fs.File.stdout().writeAll(js);
        return;
    }

    if (std.mem.eql(u8, command, "emit-css")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        var loaded = try loadComponent(path, allocator);
        defer loaded.deinit(allocator);

        const css = try style.emitScopedCss(&loaded.model, allocator);
        defer allocator.free(css);
        try std.fs.File.stdout().writeAll(css);
        return;
    }

    if (std.mem.eql(u8, command, "emit-runtime-js")) {
        const js = try legacy_runtime_js.emitSharedRuntime(allocator);
        defer allocator.free(js);
        try std.fs.File.stdout().writeAll(js);
        return;
    }

    if (std.mem.eql(u8, command, "emit-app")) {
        const root_path = args.next() orelse {
            try printUsage();
            return;
        };
        const out_dir = args.next() orelse {
            try printUsage();
            return;
        };
        try app_emit.emitApp(root_path, out_dir, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "emit-app-legacy")) {
        const root_path = args.next() orelse {
            try printUsage();
            return;
        };
        const out_dir = args.next() orelse {
            try printUsage();
            return;
        };
        try app_emit.emitAppLegacy(root_path, out_dir, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "dev")) {
        const root_path = args.next() orelse {
            try printUsage();
            return;
        };
        const out_dir = args.next() orelse ".zig-cache/weiv-dev-direct";
        try app_emit.emitApp(root_path, out_dir, allocator);
        try runDevServer(root_path, out_dir, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "dev-legacy")) {
        const root_path = args.next() orelse {
            try printUsage();
            return;
        };
        const out_dir = args.next() orelse ".zig-cache/weiv-dev-legacy";
        try app_emit.emitAppLegacy(root_path, out_dir, allocator);
        try runDevServer(root_path, out_dir, allocator);
        return;
    }

    try printUsage();
}

fn loadComponent(path: []const u8, allocator: std.mem.Allocator) !LoadedComponent {
    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| {
        try printCommandError("read component", path, err, null, allocator);
        return error.Reported;
    };
    errdefer allocator.free(source);

    var model = component.build(source, path, allocator) catch |err| {
        try printCommandError("build component", path, err, source, allocator);
        return error.Reported;
    };
    errdefer model.deinit(allocator);

    return .{
        .source = source,
        .model = model,
    };
}

fn printUsage() !void {
    try std.fs.File.stderr().writeAll(
        \\Usage:
        \\  weiv analyze-script <path>
        \\  weiv analyze-component <path>
        \\  weiv dump-ir <path>
        \\  weiv dump-browser-plan <path>
        \\  weiv dump-invalidation-graph <path>
        \\  weiv emit-js <path>
        \\  weiv emit-browser-direct-js <path>
        \\  weiv emit-css <path>
        \\  weiv emit-app <root.weiv> <out-dir>
        \\  weiv dev <root.weiv> [out-dir]
        \\
        \\Compatibility / internal:
        \\  weiv dump-state-plan <path>
        \\  weiv emit-render-js <path>
        \\  weiv emit-runtime-js
        \\  weiv emit-app-legacy <root.weiv> <out-dir>
        \\  weiv dev-legacy <root.weiv> [out-dir]
        \\
    );
}

fn printCommandError(
    action: []const u8,
    path: []const u8,
    err: anyerror,
    source: ?[]const u8,
    allocator: std.mem.Allocator,
) !void {
    var stderr = std.fs.File.stderr();
    var buffer: [2048]u8 = undefined;
    var writer = stderr.writer(&buffer);

    try writer.interface.print("weiv {s} failed for {s}\n", .{ action, path });
    try writer.interface.print("  error: {s}\n", .{friendlyErrorName(err)});

    if (source) |source_text| {
        if (try printSourceLocatedCompilerError(err, source_text, &writer, allocator)) {
            try writer.interface.flush();
            return;
        }
    }

    if (std.mem.eql(u8, friendlyErrorName(err), "InvalidSlotPlacement")) {
        try writer.interface.writeAll("  hint: `slot:name` may only be used on direct children of a component usage.\n");
    } else if (std.mem.eql(u8, friendlyErrorName(err), "InvalidSlotTemplatePlacement")) {
        try writer.interface.writeAll("  hint: `<template>` grouping is only valid inside a component usage when paired with `slot:name`.\n");
    } else if (std.mem.eql(u8, friendlyErrorName(err), "UnexpectedElse")) {
        try writer.interface.writeAll("  hint: `else` must immediately follow a sibling element with `if`.\n");
    } else if (std.mem.eql(u8, friendlyErrorName(err), "InvalidSlotOutlet")) {
        try writer.interface.writeAll("  hint: `<slot>` only supports an optional `name=\"...\"` attribute and no directives.\n");
    } else if (std.mem.eql(u8, friendlyErrorName(err), "UnexpectedCloseTag")) {
        try writer.interface.writeAll("  hint: a closing tag appeared without a matching open tag in the current template scope.\n");
    } else if (std.mem.eql(u8, friendlyErrorName(err), "MismatchedCloseTag")) {
        try writer.interface.writeAll("  hint: a closing tag did not match the currently open element.\n");
    } else if (std.mem.eql(u8, friendlyErrorName(err), "UnsupportedRuntimeImport")) {
        try writer.interface.writeAll("  hint: runtime imports must be relative/local modules, not unsupported bare package imports.\n");
    }

    try writer.interface.flush();
}

fn friendlyErrorName(err: anyerror) []const u8 {
    return @errorName(err);
}

const SourceLocation = struct {
    line_number: usize,
    column_number: usize,
    line_slice: []const u8,
    highlight_len: usize,
};

fn printSourceLocatedCompilerError(
    err: anyerror,
    source: []const u8,
    writer: anytype,
    allocator: std.mem.Allocator,
) !bool {
    const location = try findCompilerErrorLocation(source, err, allocator) orelse return false;

    try writer.interface.print("  location: {d}:{d}\n", .{ location.line_number, location.column_number });
    try writer.interface.print("  source:   {s}\n", .{location.line_slice});

    var caret_buffer = std.ArrayList(u8){};
    defer caret_buffer.deinit(allocator);
    for (0..location.column_number - 1) |_| {
        try caret_buffer.append(allocator, ' ');
    }
    for (0..location.highlight_len) |_| {
        try caret_buffer.append(allocator, '^');
    }
    try writer.interface.print("            {s}\n", .{caret_buffer.items});

    if (err == error.InvalidSlotPlacement) {
        try writer.interface.writeAll("  hint: `slot:name` may only be used on direct children of a component usage.\n");
    } else if (err == error.InvalidSlotTemplatePlacement) {
        try writer.interface.writeAll("  hint: `<template>` grouping is only valid inside a component usage when paired with `slot:name`.\n");
    } else if (err == error.UnexpectedElse) {
        try writer.interface.writeAll("  hint: `else` must immediately follow a sibling element with `if`.\n");
    }

    return true;
}

fn findCompilerErrorLocation(
    source: []const u8,
    err: anyerror,
    allocator: std.mem.Allocator,
) !?SourceLocation {
    if (err != error.InvalidSlotPlacement and err != error.InvalidSlotTemplatePlacement and err != error.UnexpectedElse) {
        return null;
    }

    const sfc_document = sfc.parse(source) catch return null;
    var template_document = template.parse(sfc_document.template.content, allocator) catch return null;
    defer template_document.deinit(allocator);

    const relative_span = if (err == error.UnexpectedElse)
        template.debug.findFirstInvalidNormalizeSpan(template_document.nodes, err) orelse return null
    else blk: {
        var normalized_document = template.normalize(&template_document, allocator) catch return null;
        defer normalized_document.deinit(allocator);
        break :blk template.debug.findFirstInvalidLoweringSpan(normalized_document.nodes, err) orelse return null;
    };
    const absolute_span = sfc.Span{
        .start = sfc_document.template.content_span.start + relative_span.start,
        .end = sfc_document.template.content_span.start + relative_span.end,
    };
    return computeSourceLocation(source, absolute_span);
}

fn computeSourceLocation(source: []const u8, span: sfc.Span) SourceLocation {
    var line_number: usize = 1;
    var line_start: usize = 0;
    var idx: usize = 0;
    while (idx < span.start and idx < source.len) : (idx += 1) {
        if (source[idx] == '\n') {
            line_number += 1;
            line_start = idx + 1;
        }
    }

    const line_end = std.mem.indexOfScalarPos(u8, source, line_start, '\n') orelse source.len;
    const line_slice = std.mem.trimRight(u8, source[line_start..line_end], "\r");
    const column_number = span.start - line_start + 1;
    const highlight_end = @min(span.end, line_end);
    const highlight_len = @max(@as(usize, 1), highlight_end - span.start);

    return .{
        .line_number = line_number,
        .column_number = column_number,
        .line_slice = line_slice,
        .highlight_len = highlight_len,
    };
}

pub fn printUnhandledError(err: anyerror) !void {
    var stderr = std.fs.File.stderr();
    var buffer: [512]u8 = undefined;
    var writer = stderr.writer(&buffer);
    try writer.interface.print("weiv failed\n  error: {s}\n", .{@errorName(err)});
    try writer.interface.flush();
}

fn runDevServer(root_path: []const u8, out_dir: []const u8, allocator: std.mem.Allocator) !void {
    std.debug.print("weiv dev\n", .{});
    std.debug.print("  root: {s}\n", .{root_path});
    std.debug.print("  out:  {s}\n", .{out_dir});
    std.debug.print("  starting Bun preview server...\n", .{});

    var child = std.process.Child.init(&.{ "bun", "--hot", "server.ts" }, allocator);
    child.cwd = out_dir;
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    _ = try child.wait();
}

fn printComponentAnalysis(model: component.ComponentModel) !void {
    var stdout = std.fs.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(&buffer);
    try stdout.writeAll("SFC sections\n");
    try writer.interface.print("  template: {d}..{d}\n", .{ model.sfc_document.template.content_span.start, model.sfc_document.template.content_span.end });
    try writer.interface.print("  script:   {d}..{d}\n", .{ model.sfc_document.script.content_span.start, model.sfc_document.script.content_span.end });
    if (model.sfc_document.style) |style_section| {
        try writer.interface.print("  style:    {d}..{d}\n", .{ style_section.content_span.start, style_section.content_span.end });
    } else {
        try stdout.writeAll("  style:    <none>\n");
    }

    try writer.interface.print("Template AST\n  root nodes: {d}\n", .{model.template_document.nodes.len});
    try writer.interface.print("Normalized template\n", .{});
    try printNormalizedNodes(model.normalized_template.nodes, 1, &writer);
    try writer.interface.print("Script analysis\n  ok: {any}\n", .{model.script.ok});
    if (model.script.props) |props| {
        try writer.interface.print("  props export: {any}\n", .{props.has_props_export});
        if (props.props_type_name) |type_name| {
            try writer.interface.print("  props type: {s}\n", .{type_name});
        }
    }
    try writer.interface.print("  imports: {d}\n", .{model.script.imports.len});
    try writer.interface.print("  bindings: {d}\n", .{model.script.bindings.len});
    for (model.script.bindings) |binding| {
        try writer.interface.print("    - {s} [{s}]\n", .{ binding.name, binding.kind });
    }
    try writer.interface.print("  diagnostics: {d}\n", .{model.script.diagnostics.len});
    try writer.interface.print("Binding phase\n  component refs: {d}\n", .{model.binding_result.component_refs.len});
    for (model.binding_result.component_refs) |component_ref| {
        try writer.interface.print("    - {s} resolved={any}\n", .{ component_ref.tag_name, component_ref.resolved });
    }
    try writer.interface.print("  binding diagnostics: {d}\n", .{model.binding_result.diagnostics.len});
    for (model.binding_result.diagnostics) |diagnostic| {
        try writer.interface.print("    - {s}: {s} [{d}..{d}]\n", .{ diagnostic.kind, diagnostic.name, diagnostic.span.start, diagnostic.span.end });
    }
    try writer.interface.flush();
}

fn printNormalizedNodes(nodes: []const @import("compiler/parse/template/index.zig").NormalizedNode, indent: usize, writer: anytype) !void {
    for (nodes) |node| {
        try printIndent(indent, writer);
        switch (node) {
            .text => |text| try writer.interface.print("text [{d}..{d}]\n", .{ text.span.start, text.span.end }),
            .interpolation => |interp| try writer.interface.print("interpolation `{s}` [{d}..{d}]\n", .{ interp.expression, interp.span.start, interp.span.end }),
            .slot_outlet => |slot_outlet| {
                if (slot_outlet.name) |name| {
                    try writer.interface.print("slot name=\"{s}\"\n", .{name});
                } else {
                    try writer.interface.print("slot <default>\n", .{});
                }
                try printNormalizedNodes(slot_outlet.fallback_children, indent + 1, writer);
            },
            .element => |element| {
                try writer.interface.print("element <{s}> children={d}\n", .{ element.tag_name, element.children.len });
                for (element.directives) |directive| {
                    try printIndent(indent + 1, writer);
                    switch (directive) {
                        .bind => |bind_dir| try writer.interface.print("directive bind:{s}=\"{s}\"\n", .{ bind_dir.target_name, bind_dir.expression }),
                        .event => |event_dir| try writer.interface.print("directive on:{s}=\"{s}\"\n", .{ event_dir.event_name, event_dir.expression }),
                        .slot_assign => |slot_assign| try writer.interface.print("directive slot:{s}\n", .{slot_assign.slot_name}),
                        .if_expr, .else_branch, .for_expr => unreachable,
                    }
                }
                try printNormalizedNodes(element.children, indent + 1, writer);
            },
            .conditional => |conditional| {
                try writer.interface.print("conditional if=\"{s}\"\n", .{conditional.condition});
                try printIndent(indent + 1, writer);
                try writer.interface.print("consequent\n", .{});
                try printNormalizedNodes(conditional.consequent, indent + 2, writer);
                if (conditional.alternate.len > 0) {
                    try printIndent(indent + 1, writer);
                    try writer.interface.print("alternate\n", .{});
                    try printNormalizedNodes(conditional.alternate, indent + 2, writer);
                }
            },
            .for_loop => |for_loop| {
                try writer.interface.print("for {s} in {s}\n", .{ for_loop.item_name, for_loop.iterable_expr });
                try printNormalizedNodes(for_loop.body, indent + 1, writer);
            },
        }
    }
}

fn printIndent(indent: usize, writer: anytype) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.interface.writeAll("  ");
    }
}

fn printIrDocument(document: @import("compiler/lower/ir.zig").Document) !void {
    var stdout = std.fs.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(&buffer);
    try writer.interface.print("IR\n", .{});
    try printIrNodes(document.nodes, 1, &writer);
    try writer.interface.flush();
}

fn printIrNodes(nodes: []const @import("compiler/lower/ir.zig").Node, indent: usize, writer: anytype) !void {
    for (nodes) |node| {
        try printIndent(indent, writer);
        switch (node) {
            .text => |text| try writer.interface.print("text `{s}`\n", .{text.content}),
            .interpolation => |interp| try writer.interface.print("interpolation `{s}`\n", .{interp.expression}),
            .slot_outlet => |slot_outlet| {
                if (slot_outlet.name) |name| {
                    try writer.interface.print("slot name=\"{s}\"\n", .{name});
                } else {
                    try writer.interface.print("slot <default>\n", .{});
                }
                try printIrNodes(slot_outlet.fallback_children, indent + 1, writer);
            },
            .component => |component_node| {
                try writer.interface.print("component <{s}>\n", .{component_node.tag_name});
                try printIrEffects(component_node.effects, indent + 1, writer);
                for (component_node.slot_provisions) |slot_provision| {
                    try printIndent(indent + 1, writer);
                    if (slot_provision.name) |name| {
                        try writer.interface.print("slot provision {s}\n", .{name});
                    } else {
                        try writer.interface.print("slot provision <default>\n", .{});
                    }
                    try printIrNodes(slot_provision.children, indent + 2, writer);
                }
            },
            .element => |element| {
                try writer.interface.print("element <{s}>\n", .{element.tag_name});
                for (element.attributes) |attribute| {
                    try printIndent(indent + 1, writer);
                    if (attribute.value) |value| {
                        try writer.interface.print("attr {s}=\"{s}\"\n", .{ attribute.name, value });
                    } else {
                        try writer.interface.print("attr {s}\n", .{attribute.name});
                    }
                }
                try printIrEffects(element.effects, indent + 1, writer);
                try printIrNodes(element.children, indent + 1, writer);
            },
            .conditional => |conditional| {
                try writer.interface.print("conditional if=\"{s}\"\n", .{conditional.condition});
                try printIndent(indent + 1, writer);
                try writer.interface.print("consequent\n", .{});
                try printIrNodes(conditional.consequent, indent + 2, writer);
                if (conditional.alternate.len > 0) {
                    try printIndent(indent + 1, writer);
                    try writer.interface.print("alternate\n", .{});
                    try printIrNodes(conditional.alternate, indent + 2, writer);
                }
            },
            .for_loop => |for_loop| {
                try writer.interface.print("for {s} in {s}\n", .{ for_loop.item_name, for_loop.iterable_expr });
                try printIrNodes(for_loop.body, indent + 1, writer);
            },
        }
    }
}

fn printIrEffects(effects: []const @import("compiler/lower/ir.zig").DirectiveEffect, indent: usize, writer: anytype) !void {
    for (effects) |effect| {
        try printIndent(indent, writer);
        switch (effect) {
            .bind => |bind_dir| try writer.interface.print("bind {s} <- {s}\n", .{ bind_dir.target_name, bind_dir.expression }),
            .event => |event_dir| try writer.interface.print("event {s} -> {s}\n", .{ event_dir.event_name, event_dir.expression }),
        }
    }
}
