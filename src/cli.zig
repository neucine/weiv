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

const WatchState = struct {
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

const DevWatcherContext = struct {
    root_path: []const u8,
    out_dir: []const u8,
    watch_root_dir: []const u8,
    ignore_dir: ?[]const u8,
    state: *WatchState,
};

const dev_watch_poll_ms: u64 = 200;
const dev_rebuild_debounce_ms: u64 = 300;

pub const CliReportedError = error{Reported};

pub fn run(allocator: std.mem.Allocator) !void {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    const command = args.next() orelse {
        try printUsage();
        return;
    };

    if (std.mem.eql(u8, command, "inspect")) {
        const subcommand = args.next() orelse {
            try printUsage();
            return;
        };
        if (std.mem.eql(u8, subcommand, "ir")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            try runInspectIr(path, allocator);
            return;
        }
        if (std.mem.eql(u8, subcommand, "browser-plan")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            try runInspectBrowserPlan(path, allocator);
            return;
        }
        if (std.mem.eql(u8, subcommand, "invalidation-graph") or std.mem.eql(u8, subcommand, "state-plan")) {
            const path = args.next() orelse {
                try printUsage();
                return;
            };
            try runInspectInvalidationGraph(path, allocator);
            return;
        }
        try printUsage();
        return;
    }

    if (std.mem.eql(u8, command, "compile")) {
        const maybe_subcommand = args.next() orelse {
            try printUsage();
            return;
        };

        if (std.mem.eql(u8, maybe_subcommand, "analyze")) {
            const phase = args.next() orelse {
                try printUsage();
                return;
            };
            if (std.mem.eql(u8, phase, "script")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                try runAnalyzeScript(path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "component")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                try runAnalyzeComponent(path, allocator);
                return;
            }
            try printUsage();
            return;
        }

        if (std.mem.eql(u8, maybe_subcommand, "emit")) {
            const phase = args.next() orelse {
                try printUsage();
                return;
            };
            if (std.mem.eql(u8, phase, "js")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                try runEmitJs(path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "render-js")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                try runEmitRenderJs(path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "browser-direct-js")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                try runEmitBrowserDirectJs(path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "css")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                try runEmitCss(path, allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "runtime-js")) {
                try runEmitRuntimeJs(allocator);
                return;
            }
            if (std.mem.eql(u8, phase, "app")) {
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
            if (std.mem.eql(u8, phase, "app-legacy")) {
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
            try printUsage();
            return;
        }

        if (std.mem.eql(u8, maybe_subcommand, "legacy")) {
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

        const root_path = maybe_subcommand;
        const out_dir = args.next() orelse ".zig-cache/weiv-compile-out";
        try app_emit.emitApp(root_path, out_dir, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "analyze-script")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runAnalyzeScript(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "analyze-component")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runAnalyzeComponent(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "inspect-ir") or std.mem.eql(u8, command, "dump-ir")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runInspectIr(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "inspect-browser-plan") or std.mem.eql(u8, command, "dump-browser-plan")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runInspectBrowserPlan(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "inspect-invalidation-graph") or
        std.mem.eql(u8, command, "inspect-state-plan") or
        std.mem.eql(u8, command, "dump-invalidation-graph") or
        std.mem.eql(u8, command, "dump-state-plan"))
    {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runInspectInvalidationGraph(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "emit-js")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runEmitJs(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "emit-render-js")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runEmitRenderJs(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "emit-browser-direct-js")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runEmitBrowserDirectJs(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "emit-css")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runEmitCss(path, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "emit-runtime-js")) {
        try runEmitRuntimeJs(allocator);
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

fn runAnalyzeScript(path: []const u8, allocator: std.mem.Allocator) !void {
    const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(source);

    const analysis_json = try parser_backend.analyzeScriptRaw(source, path, allocator);
    defer allocator.free(analysis_json);

    try std.fs.File.stdout().writeAll(analysis_json);
    try std.fs.File.stdout().writeAll("\n");
}

fn runAnalyzeComponent(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);
    try printComponentAnalysis(loaded.model);
}

fn runInspectIr(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);
    try printIrDocument(loaded.model.ir_document);
}

fn runInspectBrowserPlan(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    var plan = try browser_plan.lower(&loaded.model.ir_document, allocator);
    defer plan.deinit(allocator);

    const formatted = try browser_plan.debug.formatDocument(&plan, allocator);
    defer allocator.free(formatted);
    try std.fs.File.stdout().writeAll(formatted);
}

fn runInspectInvalidationGraph(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    var plan = try browser_plan.lower(&loaded.model.ir_document, allocator);
    defer plan.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(&loaded.model, &plan, allocator);
    defer allocator.free(formatted);
    try std.fs.File.stdout().writeAll(formatted);
}

fn runEmitJs(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    const js = try legacy_emit_js.emitDocument(&loaded.model.ir_document, allocator);
    defer allocator.free(js);
    try std.fs.File.stdout().writeAll(js);
}

fn runEmitRenderJs(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    const js = try legacy_emit_module_js.emitModule(&loaded.model, allocator);
    defer allocator.free(js);
    try std.fs.File.stdout().writeAll(js);
}

fn runEmitBrowserDirectJs(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    const js = try emit_direct_js.emitModule(&loaded.model, allocator);
    defer allocator.free(js);
    try std.fs.File.stdout().writeAll(js);
}

fn runEmitCss(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    const css = try style.emitScopedCss(&loaded.model, allocator);
    defer allocator.free(css);
    try std.fs.File.stdout().writeAll(css);
}

fn runEmitRuntimeJs(allocator: std.mem.Allocator) !void {
    const js = try legacy_runtime_js.emitSharedRuntime(allocator);
    defer allocator.free(js);
    try std.fs.File.stdout().writeAll(js);
}

fn printUsage() !void {
    try std.fs.File.stderr().writeAll(
        \\Usage:
        \\  weiv inspect ir <path>
        \\  weiv inspect browser-plan <path>
        \\  weiv inspect invalidation-graph <path>
        \\  weiv compile <root.weiv> [out-dir]
        \\  weiv compile analyze script <path>
        \\  weiv compile analyze component <path>
        \\  weiv compile emit js <path>
        \\  weiv compile emit browser-direct-js <path>
        \\  weiv compile emit css <path>
        \\  weiv compile emit app <root.weiv> <out-dir>
        \\  weiv dev <root.weiv> [out-dir]
        \\
        \\Compatibility / internal:
        \\  weiv inspect-state-plan <path>
        \\  weiv analyze-script <path>
        \\  weiv analyze-component <path>
        \\  weiv inspect-ir <path>
        \\  weiv inspect-browser-plan <path>
        \\  weiv inspect-invalidation-graph <path>
        \\  weiv emit-js <path>
        \\  weiv emit-browser-direct-js <path>
        \\  weiv emit-css <path>
        \\  weiv emit-app <root.weiv> <out-dir>
        \\  weiv dump-state-plan <path>
        \\  weiv dump-ir <path>
        \\  weiv dump-browser-plan <path>
        \\  weiv dump-invalidation-graph <path>
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
    std.debug.print("  starting watch/rebuild loop...\n", .{});

    const root_abs_path = try std.fs.cwd().realpathAlloc(allocator, root_path);
    defer allocator.free(root_abs_path);
    const watch_root_dir = std.fs.path.dirname(root_abs_path) orelse return error.InvalidRootPath;

    const out_abs_path = try std.fs.cwd().realpathAlloc(allocator, out_dir);
    defer allocator.free(out_abs_path);

    const ignore_dir = if (std.mem.startsWith(u8, out_abs_path, watch_root_dir) and
        (out_abs_path.len == watch_root_dir.len or out_abs_path[watch_root_dir.len] == std.fs.path.sep))
        try allocator.dupe(u8, out_abs_path)
    else
        null;
    defer if (ignore_dir) |value| allocator.free(value);

    var watch_state = WatchState{};
    var watcher_context = DevWatcherContext{
        .root_path = root_path,
        .out_dir = out_dir,
        .watch_root_dir = watch_root_dir,
        .ignore_dir = ignore_dir,
        .state = &watch_state,
    };
    var watcher_thread = try std.Thread.spawn(.{}, devWatchLoop, .{&watcher_context});
    defer {
        watch_state.stop.store(true, .release);
        watcher_thread.join();
    }

    std.debug.print("  starting Bun preview server...\n", .{});

    var child = std.process.Child.init(&.{ "bun", "--hot", "server.ts" }, allocator);
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    if (env_map.get("PORT")) |port| {
        std.debug.print("  port: {s} (from PORT)\n", .{port});
    } else {
        try env_map.put("PORT", "0");
        std.debug.print("  port: auto (ephemeral)\n", .{});
    }

    child.env_map = &env_map;
    child.cwd = out_dir;
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code == 130 or code == 143) {
                std.debug.print("  Bun preview server stopped gracefully\n", .{});
                return;
            }
            if (code != 0) {
                std.debug.print("weiv dev server exited with code {d}\n", .{code});
                return error.ChildProcessFailed;
            }
        },
        .Signal => |sig| {
            if (sig == std.posix.SIG.INT or sig == std.posix.SIG.TERM) {
                std.debug.print("  Bun preview server stopped gracefully\n", .{});
                return;
            }
            std.debug.print("weiv dev server exited from signal {d}\n", .{sig});
            return error.ChildProcessFailed;
        },
        .Stopped => |sig| {
            if (sig == std.posix.SIG.INT or sig == std.posix.SIG.TERM) {
                std.debug.print("  Bun preview server stopped gracefully\n", .{});
                return;
            }
            std.debug.print("weiv dev server stopped by signal {d}\n", .{sig});
            return error.ChildProcessFailed;
        },
        .Unknown => |status| {
            std.debug.print("weiv dev server exited with unknown status {d}\n", .{status});
            return error.ChildProcessFailed;
        },
    }
}

fn devWatchLoop(context: *DevWatcherContext) void {
    const allocator = std.heap.page_allocator;
    var last_handled_fingerprint = computeWatchFingerprint(context.watch_root_dir, context.ignore_dir, allocator) catch |err| {
        std.debug.print("weiv dev watch failed to initialize fingerprint\n  error: {s}\n", .{@errorName(err)});
        return;
    };
    var pending_fingerprint: ?u64 = null;
    var pending_since_ns: i128 = 0;

    while (!context.state.stop.load(.acquire)) {
        std.Thread.sleep(dev_watch_poll_ms * std.time.ns_per_ms);
        const next_fingerprint = computeWatchFingerprint(context.watch_root_dir, context.ignore_dir, allocator) catch |err| {
            std.debug.print("weiv dev watch scan failed\n  error: {s}\n", .{@errorName(err)});
            continue;
        };

        if (pending_fingerprint) |expected| {
            if (next_fingerprint == last_handled_fingerprint) {
                pending_fingerprint = null;
                continue;
            }
            if (next_fingerprint != expected) {
                pending_fingerprint = next_fingerprint;
                pending_since_ns = std.time.nanoTimestamp();
                continue;
            }
            if (std.time.nanoTimestamp() - pending_since_ns < dev_rebuild_debounce_ms * std.time.ns_per_ms) {
                continue;
            }
        } else {
            if (next_fingerprint == last_handled_fingerprint) continue;
            pending_fingerprint = next_fingerprint;
            pending_since_ns = std.time.nanoTimestamp();
            std.debug.print("  change detected, waiting for files to settle...\n", .{});
            continue;
        }

        std.debug.print("  rebuilding...\n", .{});
        app_emit.emitApp(context.root_path, context.out_dir, allocator) catch |err| {
            std.debug.print("  rebuild failed\n  error: {s}\n", .{@errorName(err)});
            last_handled_fingerprint = next_fingerprint;
            pending_fingerprint = null;
            continue;
        };
        std.debug.print("  rebuild complete\n", .{});
        last_handled_fingerprint = next_fingerprint;
        pending_fingerprint = null;
    }
}

fn computeWatchFingerprint(
    root_dir_path: []const u8,
    ignore_dir: ?[]const u8,
    allocator: std.mem.Allocator,
) !u64 {
    var dir = try std.fs.openDirAbsolute(root_dir_path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var hasher = std.hash.Wyhash.init(0);
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (shouldIgnoreWatchedPath(root_dir_path, entry.path, ignore_dir, allocator)) continue;

        const stat = try dir.statFile(entry.path);
        hasher.update(entry.path);
        hasher.update(std.mem.asBytes(&stat.size));
        hasher.update(std.mem.asBytes(&stat.mtime));
    }
    return hasher.final();
}

fn shouldIgnoreWatchedPath(
    root_dir_path: []const u8,
    relative_path: []const u8,
    ignore_dir: ?[]const u8,
    allocator: std.mem.Allocator,
) bool {
    if (std.mem.indexOf(u8, relative_path, "node_modules") != null) return true;
    if (std.mem.indexOf(u8, relative_path, ".git") != null) return true;

    const ignored = ignore_dir orelse return false;
    const abs_path = std.fs.path.join(allocator, &.{ root_dir_path, relative_path }) catch return false;
    defer allocator.free(abs_path);
    return std.mem.startsWith(u8, abs_path, ignored) and
        (abs_path.len == ignored.len or abs_path[ignored.len] == std.fs.path.sep);
}

pub fn formatComponentAnalysisReport(model: component.ComponentModel, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.print("SFC sections\n", .{});
    try writer.print("  template: {d}..{d}\n", .{ model.sfc_document.template.content_span.start, model.sfc_document.template.content_span.end });
    try writer.print("  script:   {d}..{d}\n", .{ model.sfc_document.script.content_span.start, model.sfc_document.script.content_span.end });
    if (model.sfc_document.style) |style_section| {
        try writer.print("  style:    {d}..{d}\n", .{ style_section.content_span.start, style_section.content_span.end });
    } else {
        try writer.writeAll("  style:    <none>\n");
    }

    try writer.print("Template AST\n  root nodes: {d}\n", .{model.template_document.nodes.len});
    try writer.print("Normalized template\n", .{});
    try printNormalizedNodes(model.normalized_template.nodes, 1, &writer);
    try writer.print("Script analysis\n  ok: {any}\n", .{model.script.ok});
    if (model.script.props) |props| {
        try writer.print("  props export: {any}\n", .{props.has_props_export});
        if (props.props_type_name) |type_name| {
            try writer.print("  props type: {s}\n", .{type_name});
        }
    }
    try writer.print("  imports: {d}\n", .{model.script.imports.len});
    try writer.print("  bindings: {d}\n", .{model.script.bindings.len});
    for (model.script.bindings) |binding| {
        try writer.print("    - {s} [{s}]\n", .{ binding.name, binding.kind });
    }
    try writer.print("  diagnostics: {d}\n", .{model.script.diagnostics.len});
    for (model.script.diagnostics) |diagnostic| {
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
    try writer.print("Binding phase\n  component refs: {d}\n", .{model.binding_result.component_refs.len});
    for (model.binding_result.component_refs) |component_ref| {
        try writer.print("    - {s} resolved={any}\n", .{ component_ref.tag_name, component_ref.resolved });
    }
    try writer.print("  binding diagnostics: {d}\n", .{model.binding_result.diagnostics.len});
    for (model.binding_result.diagnostics) |diagnostic| {
        try writer.print("    - {s} {s}: {s} — {s} [{d}..{d}]\n", .{
            diagnostic.severity,
            diagnostic.kind,
            diagnostic.name,
            diagnostic.message,
            diagnostic.span.start,
            diagnostic.span.end,
        });
    }
    try appendProxyStateSummary(&model, &writer, allocator);

    return out.toOwnedSlice(allocator);
}

fn appendProxyStateSummary(
    model: *const component.ComponentModel,
    writer: anytype,
    allocator: std.mem.Allocator,
) !void {
    var plan = try browser_plan.lower(&model.ir_document, allocator);
    defer plan.deinit(allocator);

    const formatted = try invalidation_graph.formatDocument(model, &plan, allocator);
    defer allocator.free(formatted);

    var tracked_root_lines = std.ArrayList([]const u8){};
    defer tracked_root_lines.deinit(allocator);
    var escape_warning_lines = std.ArrayList([]const u8){};
    defer escape_warning_lines.deinit(allocator);
    var imported_root_count: usize = 0;
    var prop_root_count: usize = 0;
    var local_root_count: usize = 0;

    const Section = enum {
        none,
        tracked_roots,
        diagnostics,
    };

    var section: Section = .none;
    var lines = std.mem.tokenizeScalar(u8, formatted, '\n');
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "tracked-roots")) {
            section = .tracked_roots;
            continue;
        }
        if (std.mem.eql(u8, line, "diagnostics")) {
            section = .diagnostics;
            continue;
        }
        if (isInvalidationGraphTopLevelSection(line)) {
            section = .none;
            continue;
        }

        switch (section) {
            .tracked_roots => {
                if (std.mem.startsWith(u8, line, "  root ")) {
                    try tracked_root_lines.append(allocator, line["  ".len..]);
                    if (std.mem.indexOf(u8, line, "kind=imported-tracked") != null) imported_root_count += 1;
                    if (std.mem.indexOf(u8, line, "kind=prop-tracked") != null) prop_root_count += 1;
                    if (std.mem.indexOf(u8, line, "kind=local-tracked") != null) local_root_count += 1;
                }
            },
            .diagnostics => {
                if (std.mem.startsWith(u8, line, "  warning escape-warning ")) {
                    try escape_warning_lines.append(allocator, line["  ".len..]);
                }
            },
            .none => {},
        }
    }

    try writer.print("Proxy state graph\n", .{});
    try writer.print("  tracked roots: {d}\n", .{tracked_root_lines.items.len});
    try writer.print("  root kinds: imported={d} props={d} local={d}\n", .{
        imported_root_count,
        prop_root_count,
        local_root_count,
    });
    for (tracked_root_lines.items) |line| {
        try writer.print("    - {s}\n", .{line});
    }
    try writer.print("  escape warnings: {d}\n", .{escape_warning_lines.items.len});
    for (escape_warning_lines.items) |line| {
        try writer.print("    - {s}\n", .{line});
        try writer.print("      rewrite: {s}\n", .{escapeWarningGuidance(line)});
    }
}

fn isInvalidationGraphTopLevelSection(line: []const u8) bool {
    if (line.len == 0) return false;
    return line[0] != ' ' and
        !std.mem.startsWith(u8, line, "invalidation-graph source=");
}

fn escapeWarningGuidance(line: []const u8) []const u8 {
    if (std.mem.indexOf(u8, line, "reason=tracked-root-alias-escape") != null) {
        return "mutate through the tracked root directly instead of mutating through a local alias";
    }
    if (std.mem.indexOf(u8, line, "reason=tracked-root-unowned-callback") != null) {
        return "move the mutation into an owned boundary or route it through a Weiv-visible tracked update path";
    }
    return "keep tracked state on its canonical surface and avoid raw or escaping mutation paths";
}

fn printComponentAnalysis(model: component.ComponentModel) !void {
    var stdout = std.fs.File.stdout();
    const formatted = try formatComponentAnalysisReport(model, std.heap.page_allocator);
    defer std.heap.page_allocator.free(formatted);
    try stdout.writeAll(formatted);
}

fn printNormalizedNodes(nodes: []const @import("compiler/parse/template/index.zig").NormalizedNode, indent: usize, writer: anytype) !void {
    for (nodes) |node| {
        try printIndent(indent, writer);
        switch (node) {
            .text => |text| try writer.print("text [{d}..{d}]\n", .{ text.span.start, text.span.end }),
            .interpolation => |interp| try writer.print("interpolation `{s}` [{d}..{d}]\n", .{ interp.expression, interp.span.start, interp.span.end }),
            .slot_outlet => |slot_outlet| {
                if (slot_outlet.name) |name| {
                    try writer.print("slot name=\"{s}\"\n", .{name});
                } else {
                    try writer.print("slot <default>\n", .{});
                }
                try printNormalizedNodes(slot_outlet.fallback_children, indent + 1, writer);
            },
            .element => |element| {
                try writer.print("element <{s}> children={d}\n", .{ element.tag_name, element.children.len });
                for (element.directives) |directive| {
                    try printIndent(indent + 1, writer);
                    switch (directive) {
                        .bind => |bind_dir| try writer.print("directive bind:{s}=\"{s}\"\n", .{ bind_dir.target_name, bind_dir.expression }),
                        .event => |event_dir| try writer.print("directive on:{s}=\"{s}\"\n", .{ event_dir.event_name, event_dir.expression }),
                        .slot_assign => |slot_assign| try writer.print("directive slot:{s}\n", .{slot_assign.slot_name}),
                        .if_expr, .else_branch, .for_expr => unreachable,
                    }
                }
                try printNormalizedNodes(element.children, indent + 1, writer);
            },
            .conditional => |conditional| {
                try writer.print("conditional if=\"{s}\"\n", .{conditional.condition});
                try printIndent(indent + 1, writer);
                try writer.print("consequent\n", .{});
                try printNormalizedNodes(conditional.consequent, indent + 2, writer);
                if (conditional.alternate.len > 0) {
                    try printIndent(indent + 1, writer);
                    try writer.print("alternate\n", .{});
                    try printNormalizedNodes(conditional.alternate, indent + 2, writer);
                }
            },
            .for_loop => |for_loop| {
                try writer.print("for {s} in {s}\n", .{ for_loop.item_name, for_loop.iterable_expr });
                try printNormalizedNodes(for_loop.body, indent + 1, writer);
            },
        }
    }
}

fn printIndent(indent: usize, writer: anytype) !void {
    var i: usize = 0;
    while (i < indent) : (i += 1) {
        try writer.writeAll("  ");
    }
}

fn printIrDocument(document: @import("compiler/lower/ir.zig").Document) !void {
    var stdout = std.fs.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(&buffer);
    try writer.interface.print("IR\n", .{});
    try printIrNodes(document.nodes, 1, &writer.interface);
    try writer.interface.flush();
}

fn printIrNodes(nodes: []const @import("compiler/lower/ir.zig").Node, indent: usize, writer: anytype) !void {
    for (nodes) |node| {
        try printIndent(indent, writer);
        switch (node) {
            .text => |text| try writer.print("text `{s}`\n", .{text.content}),
            .interpolation => |interp| try writer.print("interpolation `{s}`\n", .{interp.expression}),
            .slot_outlet => |slot_outlet| {
                if (slot_outlet.name) |name| {
                    try writer.print("slot name=\"{s}\"\n", .{name});
                } else {
                    try writer.print("slot <default>\n", .{});
                }
                try printIrNodes(slot_outlet.fallback_children, indent + 1, writer);
            },
            .component => |component_node| {
                try writer.print("component <{s}>\n", .{component_node.tag_name});
                try printIrEffects(component_node.effects, indent + 1, writer);
                for (component_node.slot_provisions) |slot_provision| {
                    try printIndent(indent + 1, writer);
                    if (slot_provision.name) |name| {
                        try writer.print("slot provision {s}\n", .{name});
                    } else {
                        try writer.print("slot provision <default>\n", .{});
                    }
                    try printIrNodes(slot_provision.children, indent + 2, writer);
                }
            },
            .element => |element| {
                try writer.print("element <{s}>\n", .{element.tag_name});
                for (element.attributes) |attribute| {
                    try printIndent(indent + 1, writer);
                    if (attribute.value) |value| {
                        try writer.print("attr {s}=\"{s}\"\n", .{ attribute.name, value });
                    } else {
                        try writer.print("attr {s}\n", .{attribute.name});
                    }
                }
                try printIrEffects(element.effects, indent + 1, writer);
                try printIrNodes(element.children, indent + 1, writer);
            },
            .conditional => |conditional| {
                try writer.print("conditional if=\"{s}\"\n", .{conditional.condition});
                try printIndent(indent + 1, writer);
                try writer.print("consequent\n", .{});
                try printIrNodes(conditional.consequent, indent + 2, writer);
                if (conditional.alternate.len > 0) {
                    try printIndent(indent + 1, writer);
                    try writer.print("alternate\n", .{});
                    try printIrNodes(conditional.alternate, indent + 2, writer);
                }
            },
            .for_loop => |for_loop| {
                try writer.print("for {s} in {s}\n", .{ for_loop.item_name, for_loop.iterable_expr });
                try printIrNodes(for_loop.body, indent + 1, writer);
            },
        }
    }
}

fn printIrEffects(effects: []const @import("compiler/lower/ir.zig").DirectiveEffect, indent: usize, writer: anytype) !void {
    for (effects) |effect| {
        try printIndent(indent, writer);
        switch (effect) {
            .bind => |bind_dir| try writer.print("bind {s} <- {s}\n", .{ bind_dir.target_name, bind_dir.expression }),
            .event => |event_dir| try writer.print("event {s} -> {s}\n", .{ event_dir.event_name, event_dir.expression }),
        }
    }
}
