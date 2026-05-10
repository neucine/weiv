const std = @import("std");
const compiler_diagnostics = @import("../../diagnostics.zig");
const bundle_graph = @import("app_bundle/graph.zig");

pub const AppValidationReport = struct {
    diagnostics: []compiler_diagnostics.Diagnostic,

    pub fn deinit(self: *AppValidationReport, allocator: std.mem.Allocator) void {
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(self.diagnostics);
        self.* = undefined;
    }
};

pub fn emitApp(root_component_path: []const u8, out_dir_path: []const u8, allocator: std.mem.Allocator) !void {
    const root_abs_path = try std.fs.cwd().realpathAlloc(allocator, root_component_path);
    defer allocator.free(root_abs_path);

    const root_dir = std.fs.path.dirname(root_abs_path) orelse return error.InvalidRootPath;
    var graph = bundle_graph.Graph.init(root_dir, allocator);
    defer graph.deinit();

    const root_index = try graph.collect(root_abs_path);
    try graph.validateRuntimeImports();

    var out_dir = try std.fs.cwd().makeOpenPath(out_dir_path, .{});
    defer out_dir.close();

    const styles_css = try graph.emitStylesheet(allocator);
    defer allocator.free(styles_css);
    try out_dir.writeFile(.{ .sub_path = "styles.css", .data = styles_css });

    try graph.writeComponentModulesDirect(out_dir, allocator);

    const entry_source = try graph.emitDirectEntry(root_index, allocator);
    defer allocator.free(entry_source);
    try out_dir.writeFile(.{ .sub_path = "bundle.mjs", .data = entry_source });

    const browser_entry_source = try graph.emitBrowserEntry(allocator);
    defer allocator.free(browser_entry_source);
    try out_dir.writeFile(.{ .sub_path = "main.mjs", .data = browser_entry_source });

    const props_source = try graph.emitPropsModule(root_index, allocator);
    defer allocator.free(props_source);
    try out_dir.writeFile(.{ .sub_path = "props.mjs", .data = props_source });

    const html_source = try graph.emitIndexHtml(root_index, allocator);
    defer allocator.free(html_source);
    try out_dir.writeFile(.{ .sub_path = "index.html", .data = html_source });

    try graph.writeRuntimeImports(out_dir, allocator);

    const package_json = try graph.emitPackageJson(allocator);
    defer allocator.free(package_json);
    try out_dir.writeFile(.{ .sub_path = "package.json", .data = package_json });

    const dev_server = try graph.emitDevServer(allocator);
    defer allocator.free(dev_server);
    try out_dir.writeFile(.{ .sub_path = "server.ts", .data = dev_server });
}

pub fn validateApp(root_component_path: []const u8, allocator: std.mem.Allocator) !AppValidationReport {
    const root_abs_path = try std.fs.cwd().realpathAlloc(allocator, root_component_path);
    defer allocator.free(root_abs_path);

    const root_dir = std.fs.path.dirname(root_abs_path) orelse return error.InvalidRootPath;
    var graph = bundle_graph.Graph.init(root_dir, allocator);
    defer graph.deinit();

    _ = try graph.collect(root_abs_path);
    const diagnostics = try graph.collectRuntimeImportDiagnostics(allocator);
    return .{
        .diagnostics = diagnostics,
    };
}
