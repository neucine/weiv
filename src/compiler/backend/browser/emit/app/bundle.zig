const std = @import("std");
const compiler_diagnostics = @import("../../../../diagnostics.zig");
const bundle_graph = @import("graph.zig");
const bundle_outputs = @import("bundle_outputs.zig");

pub const AppValidationReport = struct {
    diagnostics: []compiler_diagnostics.Diagnostic,

    pub fn deinit(self: *AppValidationReport, allocator: std.mem.Allocator) void {
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(self.diagnostics);
        self.* = undefined;
    }
};

pub fn emitApp(root_component_path: []const u8, out_dir_path: []const u8, allocator: std.mem.Allocator) !void {
    const root_abs_path = try std.Io.Dir.cwd().realPathFileAlloc(std.Io.Threaded.global_single_threaded.io(), root_component_path, allocator);
    defer allocator.free(root_abs_path);

    const root_dir = std.fs.path.dirname(root_abs_path) orelse return error.InvalidRootPath;
    var graph = bundle_graph.BundleGraph.init(root_dir, allocator);
    defer graph.deinit();

    const root_index = try graph.collect(root_abs_path);
    try graph.validateRuntimeImports();

    var out_dir = try std.Io.Dir.cwd().createDirPathOpen(std.Io.Threaded.global_single_threaded.io(), out_dir_path, .{});
    defer out_dir.close(std.Io.Threaded.global_single_threaded.io());

    const styles_css = try graph.emitStylesheet(allocator);
    defer allocator.free(styles_css);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "styles.css", .data = styles_css });

    try graph.writeComponentModulesDirect(out_dir, allocator);

    const entry_source = try bundle_outputs.emitDirectEntry(&graph, root_index, allocator);
    defer allocator.free(entry_source);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "bundle.mjs", .data = entry_source });

    const browser_entry_source = try bundle_outputs.emitBrowserEntry(allocator);
    defer allocator.free(browser_entry_source);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "main.mjs", .data = browser_entry_source });

    const props_source = try bundle_outputs.emitPropsModule(&graph, root_index, allocator);
    defer allocator.free(props_source);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "props.mjs", .data = props_source });

    const html_source = try bundle_outputs.emitIndexHtml(&graph, root_index, allocator);
    defer allocator.free(html_source);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "index.html", .data = html_source });

    try graph.writeRuntimeImports(out_dir, allocator);

    const package_json = try bundle_outputs.emitPackageJson(allocator);
    defer allocator.free(package_json);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "package.json", .data = package_json });

    const dev_server = try bundle_outputs.emitDevServer(allocator);
    defer allocator.free(dev_server);
    try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = "server.ts", .data = dev_server });
}

pub fn validateApp(root_component_path: []const u8, allocator: std.mem.Allocator) !AppValidationReport {
    const root_abs_path = try std.Io.Dir.cwd().realPathFileAlloc(std.Io.Threaded.global_single_threaded.io(), root_component_path, allocator);
    defer allocator.free(root_abs_path);

    const root_dir = std.fs.path.dirname(root_abs_path) orelse return error.InvalidRootPath;
    var graph = bundle_graph.BundleGraph.init(root_dir, allocator);
    defer graph.deinit();

    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);

    try graph.collectValidated(root_abs_path, &bag);
    if (!bag.hasFatal()) {
        const graph_diagnostics = try graph.collectValidationDiagnostics(allocator);
        defer {
            for (graph_diagnostics) |*diagnostic| diagnostic.deinit(allocator);
            allocator.free(graph_diagnostics);
        }
        for (graph_diagnostics) |diagnostic| {
            try bag.appendOwned(
                allocator,
                diagnostic.code,
                diagnostic.severity,
                diagnostic.message,
                diagnostic.stage,
                diagnostic.source_path,
                diagnostic.span,
                diagnostic.location,
                diagnostic.fatal,
            );
        }
    }

    const diagnostics = try bag.toOwnedSlice(allocator);
    return .{
        .diagnostics = diagnostics,
    };
}
