const std = @import("std");
const component = @import("compiler/pipeline.zig");
const app_emit = @import("compiler/emit/browser/app_bundle.zig");
const emit_direct_js = @import("compiler/emit/browser/direct_component_js.zig");
const legacy_emit_js = @import("compiler/emit/browser/legacy/document_js.zig");
const legacy_emit_module_js = @import("compiler/emit/browser/legacy/component_module_js.zig");
const legacy_runtime_js = @import("compiler/emit/browser/legacy/shared_runtime_js.zig");
const style = @import("compiler/emit/browser/scoped_css.zig");
const sfc = @import("compiler/parse/sfc.zig");
const parser_backend = @import("ffi/parser_backend.zig");

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
        const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
        defer allocator.free(source);

        var model = try component.build(source, path, allocator);
        defer model.deinit(allocator);

        try printComponentAnalysis(model);
        return;
    }

    if (std.mem.eql(u8, command, "dump-ir")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
        defer allocator.free(source);

        var model = try component.build(source, path, allocator);
        defer model.deinit(allocator);

        try printIrDocument(model.ir_document);
        return;
    }

    if (std.mem.eql(u8, command, "emit-js")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
        defer allocator.free(source);

        var model = try component.build(source, path, allocator);
        defer model.deinit(allocator);

        const js = try legacy_emit_js.emitDocument(&model.ir_document, allocator);
        defer allocator.free(js);
        try std.fs.File.stdout().writeAll(js);
        return;
    }

    if (std.mem.eql(u8, command, "emit-render-js")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
        defer allocator.free(source);

        var model = try component.build(source, path, allocator);
        defer model.deinit(allocator);

        const js = try legacy_emit_module_js.emitModule(&model, allocator);
        defer allocator.free(js);
        try std.fs.File.stdout().writeAll(js);
        return;
    }

    if (std.mem.eql(u8, command, "emit-browser-direct-js")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
        defer allocator.free(source);

        var model = try component.build(source, path, allocator);
        defer model.deinit(allocator);

        const js = try emit_direct_js.emitModule(&model, allocator);
        defer allocator.free(js);
        try std.fs.File.stdout().writeAll(js);
        return;
    }

    if (std.mem.eql(u8, command, "emit-css")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
        defer allocator.free(source);

        var model = try component.build(source, path, allocator);
        defer model.deinit(allocator);

        const css = try style.emitScopedCss(&model, allocator);
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

fn printUsage() !void {
    try std.fs.File.stderr().writeAll(
        \\Usage:
        \\  weiv analyze-script <path>
        \\  weiv analyze-component <path>
        \\  weiv dump-ir <path>
        \\  weiv emit-js <path>
        \\  weiv emit-browser-direct-js <path>
        \\  weiv emit-css <path>
        \\  weiv emit-app <root.weiv> <out-dir>
        \\  weiv dev <root.weiv> [out-dir]
        \\
        \\Compatibility / internal:
        \\  weiv emit-render-js <path>
        \\  weiv emit-runtime-js
        \\  weiv emit-app-legacy <root.weiv> <out-dir>
        \\  weiv dev-legacy <root.weiv> [out-dir]
        \\
    );
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

fn printNormalizedNodes(nodes: []const @import("compiler/parse/template.zig").NormalizedNode, indent: usize, writer: anytype) !void {
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
