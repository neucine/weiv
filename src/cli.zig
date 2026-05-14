const std = @import("std");
const component = @import("compiler/pipeline/index.zig");
const compiler_diagnostics = @import("compiler/diagnostics.zig");
const app_emit = @import("compiler/emit/browser/emit_app.zig");
const emit_direct_js = @import("compiler/emit/browser/emit_sfc.zig");
const style = @import("compiler/emit/browser/scoped_css.zig");
const browser_plan = @import("compiler/lower/browser_plan/index.zig");
const invalidation_graph = @import("compiler/lower/invalidation_graph/index.zig");
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
var json_diagnostics_mode: bool = false;

pub const CliReportedError = error{Reported};

pub fn run(allocator: std.mem.Allocator) !void {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    const first = args.next() orelse {
        try printUsage();
        return;
    };
    const command = if (std.mem.eql(u8, first, "--json-diagnostics")) blk: {
        json_diagnostics_mode = true;
        break :blk args.next() orelse {
            try printUsage();
            return;
        };
    } else first;

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
        if (std.mem.eql(u8, subcommand, "invalidation-graph")) {
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
                const json_flag = args.next();
                try runAnalyzeComponent(path, allocator, json_flag != null and std.mem.eql(u8, json_flag.?, "--json"));
                return;
            }
            try printUsage();
            return;
        }

        if (std.mem.eql(u8, maybe_subcommand, "validate")) {
            const phase = args.next() orelse {
                try printUsage();
                return;
            };
            if (std.mem.eql(u8, phase, "app")) {
                const root_path = args.next() orelse {
                    try printUsage();
                    return;
                };
                const json_flag = args.next();
                try runValidateApp(root_path, allocator, json_flag != null and std.mem.eql(u8, json_flag.?, "--json"));
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
            if (std.mem.eql(u8, phase, "css")) {
                const path = args.next() orelse {
                    try printUsage();
                    return;
                };
                try runEmitCss(path, allocator);
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
                try runEmitApp(root_path, out_dir, allocator);
                return;
            }
            try printUsage();
            return;
        }

        const root_path = maybe_subcommand;
        const out_dir = args.next() orelse ".zig-cache/weiv-compile-out";
        try runEmitApp(root_path, out_dir, allocator);
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
        const json_flag = args.next();
        try runAnalyzeComponent(path, allocator, json_flag != null and std.mem.eql(u8, json_flag.?, "--json"));
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
        std.mem.eql(u8, command, "dump-invalidation-graph"))
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

    if (std.mem.eql(u8, command, "emit-css")) {
        const path = args.next() orelse {
            try printUsage();
            return;
        };
        try runEmitCss(path, allocator);
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
        try runEmitApp(root_path, out_dir, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "validate-app")) {
        const root_path = args.next() orelse {
            try printUsage();
            return;
        };
        const json_flag = args.next();
        try runValidateApp(root_path, allocator, json_flag != null and std.mem.eql(u8, json_flag.?, "--json"));
        return;
    }

    if (std.mem.eql(u8, command, "dev")) {
        const root_path = args.next() orelse {
            try printUsage();
            return;
        };
        const out_dir = args.next() orelse ".zig-cache/weiv-dev-direct";
        try runEmitApp(root_path, out_dir, allocator);
        try runDevServer(root_path, out_dir, allocator);
        return;
    }

    try printUsage();
}

fn loadComponent(path: []const u8, allocator: std.mem.Allocator) !LoadedComponent {
    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| {
        try printCliStageError("read component", path, .sfc_parse, "cli.read_failed", err, allocator);
        return error.Reported;
    };
    errdefer allocator.free(source);

    var report = component.buildReport(source, path, allocator) catch |err| {
        try printCliStageError("build component", path, .lowering, "component.build_failed", err, allocator);
        return error.Reported;
    };
    defer report.deinit(allocator);

    if (hasFatalDiagnostics(report.diagnostics)) {
        try printComponentBuildFailure("build component", path, report);
        return error.Reported;
    }

    var model = report.intoComponentModel() catch |err| {
        try printCliStageError("build component", path, .lowering, "component.model_conversion_failed", err, allocator);
        return error.Reported;
    };
    errdefer model.deinit(allocator);

    for (report.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
    if (report.diagnostics.len != 0) allocator.free(report.diagnostics);
    report.diagnostics = &.{};
    report.source_path = &.{};
    report.sfc_document = null;
    report.template_document = null;
    report.normalized_template = null;
    report.script = null;
    report.binding_result = null;
    report.ir_document = null;
    report.halted_after = null;

    return .{
        .source = source,
        .model = model,
    };
}

fn runAnalyzeScript(path: []const u8, allocator: std.mem.Allocator) !void {
    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| {
        try printCliStageError("analyze script", path, .script_analysis, "cli.read_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(source);

    const analysis_json = parser_backend.analyzeScriptRaw(source, path, allocator) catch |err| {
        try printCliStageError("analyze script", path, .script_analysis, "script.backend_failure", err, allocator);
        return error.Reported;
    };
    defer allocator.free(analysis_json);

    try std.fs.File.stdout().writeAll(analysis_json);
    try std.fs.File.stdout().writeAll("\n");
}

fn runAnalyzeComponent(path: []const u8, allocator: std.mem.Allocator, json: bool) !void {
    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| {
        try printCliStageError("read component", path, .sfc_parse, "cli.read_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(source);

    var report = component.buildReport(source, path, allocator) catch |err| {
        try printCliStageError("analyze component", path, .lowering, "component.build_failed", err, allocator);
        return error.Reported;
    };
    defer report.deinit(allocator);
    if (json) {
        try printComponentAnalysisJson(report);
    } else {
        try printComponentAnalysisReport(report);
    }
}

fn runInspectIr(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);
    try printIrDocument(loaded.model.ir_document);
}

fn runInspectBrowserPlan(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    var plan = browser_plan.lower(&loaded.model.ir_document, allocator) catch |err| {
        try printCliStageError("inspect browser-plan", path, .browser_plan, "browser_plan.lower_failed", err, allocator);
        return error.Reported;
    };
    defer plan.deinit(allocator);

    const formatted = try browser_plan.debug.formatDocument(&plan, allocator);
    defer allocator.free(formatted);
    try std.fs.File.stdout().writeAll(formatted);
}

fn runInspectInvalidationGraph(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    var plan = browser_plan.lower(&loaded.model.ir_document, allocator) catch |err| {
        try printCliStageError("inspect invalidation-graph", path, .browser_plan, "browser_plan.lower_failed", err, allocator);
        return error.Reported;
    };
    defer plan.deinit(allocator);

    const formatted = invalidation_graph.formatDocument(&loaded.model, &plan, allocator) catch |err| {
        try printCliStageError("inspect invalidation-graph", path, .lowering, "invalidation_graph.format_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(formatted);
    try std.fs.File.stdout().writeAll(formatted);
}

fn runEmitJs(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    if (try printStyleEmitDiagnostics("emit js", path, &loaded, allocator)) {
        return error.Reported;
    }

    const js = emit_direct_js.emitModule(&loaded.model, allocator) catch |err| {
        try printCliStageError("emit js", path, .emit, "emit.js_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(js);
    try std.fs.File.stdout().writeAll(js);
}

fn runEmitCss(path: []const u8, allocator: std.mem.Allocator) !void {
    var loaded = try loadComponent(path, allocator);
    defer loaded.deinit(allocator);

    if (try printStyleEmitDiagnostics("emit css", path, &loaded, allocator)) {
        return error.Reported;
    }

    const css = style.emitScopedCss(&loaded.model, allocator) catch |err| {
        try printCliStageError("emit css", path, .emit, "emit.css_failed", err, allocator);
        return error.Reported;
    };
    defer allocator.free(css);
    try std.fs.File.stdout().writeAll(css);
}

fn runEmitApp(root_path: []const u8, out_dir: []const u8, allocator: std.mem.Allocator) !void {
    var validation = app_emit.validateApp(root_path, allocator) catch |err| {
        try printCliStageError("validate app", root_path, .bundle, "app.validate_failed", err, allocator);
        return error.Reported;
    };
    defer validation.deinit(allocator);

    if (hasFatalDiagnostics(validation.diagnostics)) {
        try printAppValidationDiagnostics(root_path, validation.diagnostics);
        return error.Reported;
    }

    app_emit.emitApp(root_path, out_dir, allocator) catch |err| {
        try printCliStageError("emit app", root_path, .bundle, "app.emit_failed", err, allocator);
        return error.Reported;
    };
}

fn runValidateApp(root_path: []const u8, allocator: std.mem.Allocator, json: bool) !void {
    var validation = app_emit.validateApp(root_path, allocator) catch |err| {
        try printCliStageError("validate app", root_path, .bundle, "app.validate_failed", err, allocator);
        return error.Reported;
    };
    defer validation.deinit(allocator);

    if (json) {
        const formatted = try formatAppValidationDiagnosticsJson(root_path, validation.diagnostics, allocator);
        defer allocator.free(formatted);
        try std.fs.File.stdout().writeAll(formatted);
    } else if (validation.diagnostics.len == 0) {
        try std.fs.File.stdout().writeAll("app validation ok\n");
    } else {
        try printAppValidationDiagnostics(root_path, validation.diagnostics);
    }

    if (hasFatalDiagnostics(validation.diagnostics)) {
        return error.Reported;
    }
}

fn printUsage() !void {
    try std.fs.File.stderr().writeAll(
        \\Usage:
        \\  weiv --json-diagnostics <command...>
        \\  weiv inspect ir <path>
        \\  weiv inspect browser-plan <path>
        \\  weiv inspect invalidation-graph <path>
        \\  weiv compile <root.weiv> [out-dir]
        \\  weiv compile analyze script <path>
        \\  weiv compile analyze component <path>
        \\  weiv compile validate app <root.weiv> [--json]
        \\  weiv compile emit js <path>
        \\  weiv compile emit css <path>
        \\  weiv compile emit app <root.weiv> <out-dir>
        \\  weiv dev <root.weiv> [out-dir]
        \\
        \\Compatibility / internal:
        \\  weiv analyze-script <path>
        \\  weiv analyze-component <path>
        \\  weiv inspect-ir <path>
        \\  weiv inspect-browser-plan <path>
        \\  weiv inspect-invalidation-graph <path>
        \\  weiv emit-js <path>
        \\  weiv emit-css <path>
        \\  weiv emit-app <root.weiv> <out-dir>
        \\  weiv validate-app <root.weiv> [--json]
        \\  weiv dump-ir <path>
        \\  weiv dump-browser-plan <path>
        \\  weiv dump-invalidation-graph <path>
        \\
    );
}

fn friendlyErrorName(err: anyerror) []const u8 {
    return @errorName(err);
}

pub fn printUnhandledError(err: anyerror) !void {
    try printCliStageError("run", "<process>", .bundle, "cli.unhandled_error", err, std.heap.page_allocator);
}

fn printCliStageError(
    action: []const u8,
    source_path: []const u8,
    stage: compiler_diagnostics.Stage,
    code: []const u8,
    err: anyerror,
    allocator: std.mem.Allocator,
) !void {
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);

    const message = try std.fmt.allocPrint(allocator, "{s} ({s})", .{ action, friendlyErrorName(err) });
    defer allocator.free(message);

    try bag.appendOwned(
        allocator,
        code,
        .@"error",
        message,
        stage,
        source_path,
        null,
        null,
        true,
    );

    const diagnostics = try bag.toOwnedSlice(allocator);
    defer {
        for (diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(diagnostics);
    }
    try printComponentDiagnosticsFailure(action, source_path, diagnostics);
}

fn printComponentBuildFailure(action: []const u8, path: []const u8, report: component.ComponentBuildReport) !void {
    if (json_diagnostics_mode) {
        var stderr = std.fs.File.stderr();
        const formatted = try formatComponentBuildReportJson(report, std.heap.page_allocator);
        defer std.heap.page_allocator.free(formatted);
        try stderr.writeAll(formatted);
        return;
    }

    var stderr = std.fs.File.stderr();
    var buffer: [1024]u8 = undefined;
    var writer = stderr.writer(&buffer);
    const formatted = try formatComponentBuildReport(report, std.heap.page_allocator);
    defer std.heap.page_allocator.free(formatted);
    try writer.interface.print("weiv {s} failed for {s}\n", .{ action, path });
    try writer.interface.flush();
    try stderr.writeAll(formatted);
}

fn printComponentDiagnosticsFailure(
    action: []const u8,
    path: []const u8,
    diagnostics: []const compiler_diagnostics.Diagnostic,
) !void {
    if (json_diagnostics_mode) {
        var stderr = std.fs.File.stderr();
        const formatted = try formatFailureDiagnosticsJson(action, path, diagnostics, std.heap.page_allocator);
        defer std.heap.page_allocator.free(formatted);
        try stderr.writeAll(formatted);
        return;
    }

    var stderr = std.fs.File.stderr();
    var buffer: [1024]u8 = undefined;
    var writer = stderr.writer(&buffer);
    try writer.interface.print("weiv {s} failed for {s}\n", .{ action, path });
    try writer.interface.flush();

    var out = std.ArrayList(u8){};
    defer out.deinit(std.heap.page_allocator);
    const out_writer = out.writer(std.heap.page_allocator);
    try compiler_diagnostics.writeTextDiagnostics(out_writer, diagnostics, "  ");
    const formatted = try out.toOwnedSlice(std.heap.page_allocator);
    defer std.heap.page_allocator.free(formatted);
    try stderr.writeAll(formatted);
}

fn printStyleEmitDiagnostics(
    action: []const u8,
    path: []const u8,
    loaded: *const LoadedComponent,
    allocator: std.mem.Allocator,
) !bool {
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);
    try style.appendEmitDiagnostics(&bag, &loaded.model, loaded.source, allocator);
    if (!bag.hasFatal()) return false;
    const diagnostics = try bag.toOwnedSlice(allocator);
    defer {
        for (diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(diagnostics);
    }
    try printComponentDiagnosticsFailure(action, path, diagnostics);
    return true;
}

fn hasFatalDiagnostics(diagnostics: []const compiler_diagnostics.Diagnostic) bool {
    return compiler_diagnostics.hasFatalDiagnostics(diagnostics);
}

pub fn formatAppValidationDiagnostics(
    root_path: []const u8,
    diagnostics: []const compiler_diagnostics.Diagnostic,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.print("weiv validate app failed for {s}\n", .{root_path});
    try compiler_diagnostics.writeTextDiagnostics(writer, diagnostics, "  ");

    return out.toOwnedSlice(allocator);
}

pub fn formatAppValidationDiagnosticsJson(
    root_path: []const u8,
    diagnostics: []const compiler_diagnostics.Diagnostic,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.writeAll("{\n");
    try writer.print("  \"rootPath\": {f},\n", .{std.json.fmt(root_path, .{})});
    try writer.print("  \"ok\": {any},\n", .{!hasFatalDiagnostics(diagnostics)});
    try writer.writeAll("  \"diagnostics\": [\n");
    try compiler_diagnostics.writeJsonDiagnostics(writer, diagnostics, "    ");
    try writer.writeAll("  ]\n");
    try writer.writeAll("}\n");
    return out.toOwnedSlice(allocator);
}

fn printAppValidationDiagnostics(root_path: []const u8, diagnostics: []const compiler_diagnostics.Diagnostic) !void {
    if (json_diagnostics_mode) {
        var stderr = std.fs.File.stderr();
        const formatted = try formatAppValidationDiagnosticsJson(root_path, diagnostics, std.heap.page_allocator);
        defer std.heap.page_allocator.free(formatted);
        try stderr.writeAll(formatted);
        return;
    }

    var stderr = std.fs.File.stderr();
    const formatted = try formatAppValidationDiagnostics(root_path, diagnostics, std.heap.page_allocator);
    defer std.heap.page_allocator.free(formatted);
    try stderr.writeAll(formatted);
}

fn formatFailureDiagnosticsJson(
    action: []const u8,
    source_path: []const u8,
    diagnostics: []const compiler_diagnostics.Diagnostic,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.writeAll("{\n");
    try writer.print("  \"action\": {f},\n", .{std.json.fmt(action, .{})});
    try writer.print("  \"sourcePath\": {f},\n", .{std.json.fmt(source_path, .{})});
    try writer.print("  \"ok\": {any},\n", .{!hasFatalDiagnostics(diagnostics)});
    try writer.writeAll("  \"diagnostics\": [\n");
    try compiler_diagnostics.writeJsonDiagnostics(writer, diagnostics, "    ");
    try writer.writeAll("  ]\n");
    try writer.writeAll("}\n");
    return out.toOwnedSlice(allocator);
}

pub fn formatCliFailureDiagnosticsJson(
    action: []const u8,
    source_path: []const u8,
    diagnostics: []const compiler_diagnostics.Diagnostic,
    allocator: std.mem.Allocator,
) ![]u8 {
    return formatFailureDiagnosticsJson(action, source_path, diagnostics, allocator);
}

fn runDevServer(root_path: []const u8, out_dir: []const u8, allocator: std.mem.Allocator) !void {
    printDevInfo("session.start", "root={s} out={s}", .{ root_path, out_dir });
    printDevInfo("watch.starting", "starting watch/rebuild loop", .{});

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

    printDevInfo("server.starting", "starting Bun preview server", .{});

    var child = std.process.Child.init(&.{ "bun", "--hot", "server.ts" }, allocator);
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    if (env_map.get("PORT")) |port| {
        printDevInfo("server.port", "port={s} source=env", .{port});
    } else {
        try env_map.put("PORT", "0");
        printDevInfo("server.port", "port=auto source=ephemeral", .{});
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
                printDevInfo("server.stop", "preview server stopped gracefully", .{});
                return;
            }
            if (code != 0) {
                const err_name = std.fmt.allocPrint(allocator, "ChildExitCode({d})", .{code}) catch "ChildExitCode(alloc-failed)";
                defer if (!std.mem.eql(u8, err_name, "ChildExitCode(alloc-failed)")) allocator.free(err_name);
                printCliDevMessage("dev server", root_path, .bundle, "dev.server_exit_code", err_name) catch {};
                return error.ChildProcessFailed;
            }
        },
        .Signal => |sig| {
            if (sig == std.posix.SIG.INT or sig == std.posix.SIG.TERM) {
                printDevInfo("server.stop", "preview server stopped gracefully", .{});
                return;
            }
            const sig_msg = std.fmt.allocPrint(allocator, "ChildSignal({d})", .{sig}) catch "ChildSignal(alloc-failed)";
            defer if (!std.mem.eql(u8, sig_msg, "ChildSignal(alloc-failed)")) allocator.free(sig_msg);
            printCliDevMessage("dev server", root_path, .bundle, "dev.server_signal", sig_msg) catch {};
            return error.ChildProcessFailed;
        },
        .Stopped => |sig| {
            if (sig == std.posix.SIG.INT or sig == std.posix.SIG.TERM) {
                printDevInfo("server.stop", "preview server stopped gracefully", .{});
                return;
            }
            const sig_msg = std.fmt.allocPrint(allocator, "ChildStoppedSignal({d})", .{sig}) catch "ChildStoppedSignal(alloc-failed)";
            defer if (!std.mem.eql(u8, sig_msg, "ChildStoppedSignal(alloc-failed)")) allocator.free(sig_msg);
            printCliDevMessage("dev server", root_path, .bundle, "dev.server_stopped_signal", sig_msg) catch {};
            return error.ChildProcessFailed;
        },
        .Unknown => |status| {
            const status_msg = std.fmt.allocPrint(allocator, "ChildUnknownStatus({d})", .{status}) catch "ChildUnknownStatus(alloc-failed)";
            defer if (!std.mem.eql(u8, status_msg, "ChildUnknownStatus(alloc-failed)")) allocator.free(status_msg);
            printCliDevMessage("dev server", root_path, .bundle, "dev.server_unknown_status", status_msg) catch {};
            return error.ChildProcessFailed;
        },
    }
}

fn devWatchLoop(context: *DevWatcherContext) void {
    const allocator = std.heap.page_allocator;
    var last_handled_fingerprint = computeWatchFingerprint(context.watch_root_dir, context.ignore_dir, allocator) catch |err| {
        printCliStageError("dev watch initialize", context.root_path, .bundle, "dev.watch_init_failed", err, allocator) catch {};
        return;
    };
    var pending_fingerprint: ?u64 = null;
    var pending_since_ns: i128 = 0;

    while (!context.state.stop.load(.acquire)) {
        std.Thread.sleep(dev_watch_poll_ms * std.time.ns_per_ms);
        const next_fingerprint = computeWatchFingerprint(context.watch_root_dir, context.ignore_dir, allocator) catch |err| {
            printCliStageError("dev watch scan", context.root_path, .bundle, "dev.watch_scan_failed", err, allocator) catch {};
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
            printDevInfo("watch.change_detected", "waiting for files to settle", .{});
            continue;
        }

        printDevInfo("watch.rebuild", "rebuilding", .{});
        runEmitApp(context.root_path, context.out_dir, allocator) catch |err| {
            if (err == error.Reported) {
                printDevInfo("watch.rebuild_blocked", "rebuild blocked by diagnostics", .{});
            } else {
                printCliStageError("dev rebuild", context.root_path, .bundle, "dev.rebuild_failed", err, allocator) catch {};
            }
            printDevInfo("watch.resume", "watching for the next change", .{});
            last_handled_fingerprint = next_fingerprint;
            pending_fingerprint = null;
            continue;
        };
        printDevInfo("watch.rebuild_complete", "rebuild complete", .{});
        printDevInfo("watch.resume", "watching for the next change", .{});
        last_handled_fingerprint = next_fingerprint;
        pending_fingerprint = null;
    }
}

fn printDevInfo(comptime event: []const u8, comptime fmt: []const u8, args: anytype) void {
    std.debug.print("weiv dev info {s}: " ++ fmt ++ "\n", .{event} ++ args);
}

fn printCliDevMessage(
    action: []const u8,
    source_path: []const u8,
    stage: compiler_diagnostics.Stage,
    code: []const u8,
    detail: []const u8,
) !void {
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(std.heap.page_allocator);
    try bag.appendOwned(
        std.heap.page_allocator,
        code,
        .@"error",
        detail,
        stage,
        source_path,
        null,
        null,
        true,
    );
    const diagnostics = try bag.toOwnedSlice(std.heap.page_allocator);
    defer {
        for (diagnostics) |*diagnostic| diagnostic.deinit(std.heap.page_allocator);
        std.heap.page_allocator.free(diagnostics);
    }
    try printComponentDiagnosticsFailure(action, source_path, diagnostics);
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

pub fn formatComponentBuildReport(report: component.ComponentBuildReport, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    if (report.sfc_document) |sfc_document| {
        try writer.print("SFC sections\n", .{});
        try writer.print("  template: {d}..{d}\n", .{ sfc_document.template.content_span.start, sfc_document.template.content_span.end });
        try writer.print("  script:   {d}..{d}\n", .{ sfc_document.script.content_span.start, sfc_document.script.content_span.end });
        if (sfc_document.style) |style_section| {
            try writer.print("  style:    {d}..{d}\n", .{ style_section.content_span.start, style_section.content_span.end });
        } else {
            try writer.writeAll("  style:    <none>\n");
        }
    }

    if (report.template_document) |template_document| {
        try writer.print("Template AST\n  root nodes: {d}\n", .{template_document.nodes.len});
    }

    if (report.normalized_template) |normalized_template| {
        try writer.print("Normalized template\n", .{});
        try printNormalizedNodes(normalized_template.nodes, 1, &writer);
    }

    if (report.script) |script| {
        try writer.print("Script analysis\n  ok: {any}\n", .{script.ok});
        if (script.props) |props| {
            try writer.print("  props export: {any}\n", .{props.has_props_export});
            if (props.props_type_name) |type_name| {
                try writer.print("  props type: {s}\n", .{type_name});
            }
        }
        try writer.print("  imports: {d}\n", .{script.imports.len});
        try writer.print("  bindings: {d}\n", .{script.bindings.len});
        for (script.bindings) |binding_record| {
            try writer.print("    - {s} [{s}]\n", .{ binding_record.name, binding_record.kind });
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
    }

    if (report.binding_result) |binding_result| {
        try writer.print("Binding phase\n  component refs: {d}\n", .{binding_result.component_refs.len});
        for (binding_result.component_refs) |component_ref| {
            try writer.print("    - {s} resolved={any}\n", .{ component_ref.tag_name, component_ref.resolved });
        }
        try writer.print("  binding diagnostics: {d}\n", .{binding_result.diagnostics.len});
        for (binding_result.diagnostics) |diagnostic| {
            try writer.print("    - {s} {s}: {s} — {s} [{d}..{d}]\n", .{
                diagnostic.severity,
                diagnostic.kind,
                diagnostic.name,
                diagnostic.message,
                diagnostic.span.start,
                diagnostic.span.end,
            });
        }
    }

    try writer.print("Compiler diagnostics\n  total: {d}\n", .{report.diagnostics.len});
    try compiler_diagnostics.writeTextDiagnostics(writer, report.diagnostics, "    - ");

    if (report.ir_document != null and report.binding_result != null) {
        const success_model = component.ComponentModel{
            .source_path = report.source_path,
            .sfc_document = report.sfc_document.?,
            .template_document = report.template_document.?,
            .normalized_template = report.normalized_template.?,
            .script = report.script.?,
            .binding_result = report.binding_result.?,
            .ir_document = report.ir_document.?,
        };
        try appendProxyStateSummary(&success_model, &writer, allocator);
    } else if (report.halted_after) |halted_after| {
        try writer.print("Pipeline halt\n  halted after: {s}\n", .{compiler_diagnostics.stageLabel(halted_after)});
    }

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

fn printComponentAnalysisReport(report: component.ComponentBuildReport) !void {
    var stdout = std.fs.File.stdout();
    const formatted = try formatComponentBuildReport(report, std.heap.page_allocator);
    defer std.heap.page_allocator.free(formatted);
    try stdout.writeAll(formatted);
}

pub fn formatComponentBuildReportJson(report: component.ComponentBuildReport, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    try writer.writeAll("{\n");
    try writer.print("  \"sourcePath\": {f},\n", .{std.json.fmt(report.source_path, .{})});
    if (report.halted_after) |stage| {
        try writer.print("  \"haltedAfter\": {f},\n", .{std.json.fmt(compiler_diagnostics.stageLabel(stage), .{})});
    } else {
        try writer.writeAll("  \"haltedAfter\": null,\n");
    }
    try writer.writeAll("  \"stages\": {\n");
    try writer.print("    \"sfc\": {any},\n", .{report.sfc_document != null});
    try writer.print("    \"template\": {any},\n", .{report.template_document != null});
    try writer.print("    \"normalizedTemplate\": {any},\n", .{report.normalized_template != null});
    try writer.print("    \"script\": {any},\n", .{report.script != null});
    try writer.print("    \"binding\": {any},\n", .{report.binding_result != null});
    try writer.print("    \"ir\": {any}\n", .{report.ir_document != null});
    try writer.writeAll("  },\n");
    try writer.writeAll("  \"diagnostics\": [\n");
    try compiler_diagnostics.writeJsonDiagnostics(writer, report.diagnostics, "    ");
    try writer.writeAll("  ]\n");
    try writer.writeAll("}\n");
    return out.toOwnedSlice(allocator);
}

fn printComponentAnalysisJson(report: component.ComponentBuildReport) !void {
    var stdout = std.fs.File.stdout();
    const formatted = try formatComponentBuildReportJson(report, std.heap.page_allocator);
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
