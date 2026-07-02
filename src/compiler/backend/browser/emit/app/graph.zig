const std = @import("std");
const compiler_compile = @import("../../../../compile.zig");
const compiler_diagnostics = @import("../../../../diagnostics.zig");
const component = @import("../../../../component_unit.zig");
const browser_component = @import("../../component.zig");
const js_module = @import("../js_module.zig");
const parser_backend = @import("../../../../../ffi/parser_backend.zig");
const sir = @import("../../../../sema/sir.zig");
const style = @import("../scoped_css.zig");

const weiv_runtime_legacy_package_specifier = "@weiv/runtime";
const weiv_virtual_observable_specifier = "weiv:observable";
const weiv_virtual_router_specifier = "weiv:router";
const weiv_runtime_output_entry = "__weiv_runtime/index.js";
const weiv_runtime_observable_output_entry = "__weiv_runtime/observable.js";
const weiv_runtime_router_output_entry = "__weiv_runtime/router.js";

pub const Graph = struct {
    root_dir: []const u8,
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node),
    index_by_abs_path: std.StringHashMap(usize),
    validation_seen_paths: std.StringHashMap(void),
    component_registry: std.StringHashMap(usize),
    copied_runtime_paths: std.StringHashMap(void),
    bare_imports: std.StringHashMap(void),

    pub fn init(root_dir: []const u8, allocator: std.mem.Allocator) Graph {
        return .{
            .root_dir = root_dir,
            .allocator = allocator,
            .nodes = std.ArrayList(Node).empty,
            .index_by_abs_path = std.StringHashMap(usize).init(allocator),
            .validation_seen_paths = std.StringHashMap(void).init(allocator),
            .component_registry = std.StringHashMap(usize).init(allocator),
            .copied_runtime_paths = std.StringHashMap(void).init(allocator),
            .bare_imports = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Graph) void {
        for (self.nodes.items) |*node| node.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.index_by_abs_path.deinit();
        var validation_iter = self.validation_seen_paths.iterator();
        while (validation_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.validation_seen_paths.deinit();
        var component_iter = self.component_registry.iterator();
        while (component_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.component_registry.deinit();
        var copied_iter = self.copied_runtime_paths.iterator();
        while (copied_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.copied_runtime_paths.deinit();
        var bare_iter = self.bare_imports.iterator();
        while (bare_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.bare_imports.deinit();
    }

    pub fn collect(self: *Graph, abs_path: []const u8) !usize {
        if (self.index_by_abs_path.get(abs_path)) |existing| return existing;

        const source = try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), abs_path, self.allocator, .limited(1024 * 1024));
        errdefer self.allocator.free(source);

        const rel_source_path = try std.fs.path.relative(self.allocator, ".", null, self.root_dir, abs_path);
        errdefer self.allocator.free(rel_source_path);
        const module_rel_path = try replaceExtension(rel_source_path, ".mjs", self.allocator);
        errdefer self.allocator.free(module_rel_path);

        var model = try compiler_compile.compile(source, abs_path, self.allocator);
        errdefer model.deinit(self.allocator);

        const node_index = self.nodes.items.len;
        try self.nodes.append(self.allocator, .{
            .abs_path = try self.allocator.dupe(u8, abs_path),
            .source = source,
            .rel_source_path = rel_source_path,
            .module_rel_path = module_rel_path,
            .model = model,
        });
        try self.index_by_abs_path.put(self.nodes.items[node_index].abs_path, node_index);

        const component_dir = std.fs.path.dirname(abs_path) orelse return error.InvalidComponentPath;
        for (self.nodes.items[node_index].model.script.imports) |import_record| {
            if (!std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
            if (import_record.local_name.len == 0) continue;

            const joined = try std.fs.path.resolve(self.allocator, &.{ component_dir, import_record.source });
            defer self.allocator.free(joined);

            const child_index = try self.collect(joined);
            try self.registerComponent(import_record.local_name, child_index);
        }

        return node_index;
    }

    pub fn collectValidated(
        self: *Graph,
        abs_path: []const u8,
        bag: *compiler_diagnostics.DiagnosticBag,
    ) !void {
        if (self.index_by_abs_path.get(abs_path) != null) return;
        if (self.validation_seen_paths.contains(abs_path)) return;
        try self.validation_seen_paths.put(try self.allocator.dupe(u8, abs_path), {});

        const source = try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), abs_path, self.allocator, .limited(1024 * 1024));
        errdefer self.allocator.free(source);

        var report = try compiler_compile.compileReport(source, abs_path, self.allocator);
        defer report.deinit(self.allocator);

        try appendDiagnosticsFromSlice(bag, report.diagnostics, self.allocator);
        if (compiler_diagnostics.hasFatalDiagnostics(report.diagnostics)) {
            self.allocator.free(source);
            return;
        }

        const rel_source_path = try std.fs.path.relative(self.allocator, ".", null, self.root_dir, abs_path);
        errdefer self.allocator.free(rel_source_path);
        const module_rel_path = try replaceExtension(rel_source_path, ".mjs", self.allocator);
        errdefer self.allocator.free(module_rel_path);

        var model = try report.intoComponentUnit();
        errdefer model.deinit(self.allocator);
        consumeComponentCompileReport(&report);

        const node_index = self.nodes.items.len;
        try self.nodes.append(self.allocator, .{
            .abs_path = try self.allocator.dupe(u8, abs_path),
            .source = source,
            .rel_source_path = rel_source_path,
            .module_rel_path = module_rel_path,
            .model = model,
        });
        try self.index_by_abs_path.put(self.nodes.items[node_index].abs_path, node_index);

        const component_dir = std.fs.path.dirname(abs_path) orelse return error.InvalidComponentPath;
        for (self.nodes.items[node_index].model.script.imports) |import_record| {
            if (!std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
            if (import_record.local_name.len == 0) continue;

            const joined = try std.fs.path.resolve(self.allocator, &.{ component_dir, import_record.source });
            defer self.allocator.free(joined);

            try self.collectValidated(joined, bag);
            if (self.index_by_abs_path.get(joined)) |child_index| {
                try self.registerComponentValidated(
                    bag,
                    &self.nodes.items[node_index],
                    import_record.local_name,
                    import_record.span_start,
                    import_record.span_end,
                    child_index,
                );
            }
        }
    }

    pub fn emitStylesheet(self: *Graph, allocator: std.mem.Allocator) ![]u8 {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);

        for (self.nodes.items, 0..) |*node, idx| {
            const css = try style.emitScopedCss(&node.model, allocator);
            defer allocator.free(css);
            if (css.len == 0) continue;
            if (out.items.len > 0 and idx > 0) {
                try out.appendSlice(allocator, "\n\n");
            }
            try out.appendSlice(allocator, css);
        }

        return try out.toOwnedSlice(allocator);
    }

    pub fn writeComponentModulesDirect(self: *Graph, out_dir: std.Io.Dir, allocator: std.mem.Allocator) !void {
        for (self.nodes.items) |*node| {
            var browser_component_model = try browser_component.build(&node.model, allocator);
            defer browser_component_model.deinit(allocator);

            const js = try js_module.emitModule(&browser_component_model, allocator);
            defer allocator.free(js);
            const rewritten_js = try rewriteRuntimeImportSpecifiers(js, node.module_rel_path, allocator);
            defer allocator.free(rewritten_js);
            if (std.fs.path.dirname(node.module_rel_path)) |output_dirname| {
                if (!std.mem.eql(u8, output_dirname, ".") and output_dirname.len > 0) {
                    try out_dir.createDirPath(std.Io.Threaded.global_single_threaded.io(), output_dirname);
                }
            }
            try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = node.module_rel_path, .data = rewritten_js });
        }
    }

    pub fn writeRuntimeImports(self: *Graph, out_dir: std.Io.Dir, allocator: std.mem.Allocator) !void {
        for (self.nodes.items) |*node| {
            const component_dir = std.fs.path.dirname(node.abs_path) orelse continue;
            for (node.model.script.imports) |import_record| {
                if (!shouldCopyRuntimeImport(import_record, &node.model.script)) continue;
                try self.copyRuntimeImport(out_dir, component_dir, import_record.source, allocator);
            }
        }
    }

    pub fn validateRuntimeImports(self: *Graph) !void {
        for (self.nodes.items) |*node| {
            for (node.model.script.imports) |import_record| {
                if (!shouldPreserveRuntimeImport(import_record, &node.model.script)) continue;
                try validateRuntimeImportSpecifier(self, node.abs_path, import_record.source);
            }
        }
    }

    pub fn collectValidationDiagnostics(self: *Graph, allocator: std.mem.Allocator) ![]compiler_diagnostics.Diagnostic {
        var bag = compiler_diagnostics.DiagnosticBag.init();
        defer bag.deinit(allocator);

        for (self.nodes.items) |*node| {
            for (node.model.script.imports) |import_record| {
                if (!shouldPreserveRuntimeImport(import_record, &node.model.script)) continue;

                const problem = classifyRuntimeImportProblem(import_record.source) orelse continue;
                const span = compiler_diagnostics.Span{
                    .start = node.model.sfc_document.script.content_span.start + import_record.span_start,
                    .end = node.model.sfc_document.script.content_span.start + import_record.span_end,
                };

                try bag.appendOwned(
                    allocator,
                    problem.code,
                    .@"error",
                    problem.message,
                    .bundle,
                    node.abs_path,
                    span,
                    compiler_diagnostics.computeLocation(node.source, span),
                    true,
                );
            }

            try style.appendEmitDiagnostics(&bag, &node.model, node.source, allocator);
        }

        return bag.toOwnedSlice(allocator);
    }

    pub fn emitBrowserEntry(self: *Graph, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        return try std.fmt.allocPrint(allocator,
            \\import * as WeivApp from "./bundle.mjs";
            \\import {{ props as previewProps }} from "./props.mjs";
            \\
            \\const target = document.getElementById("app");
            \\const props = globalThis.__WEIV_PROPS__ ?? previewProps;
            \\
            \\if (target) {{
            \\  WeivApp.mount(target, props);
            \\}}
            \\
            \\export * from "./bundle.mjs";
            \\export default WeivApp;
            \\
        , .{});
    }

    pub fn emitDirectEntry(self: *Graph, root_index: usize, allocator: std.mem.Allocator) ![]u8 {
        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);

        const root_import_path = try ensureRelativeSpecifier(self.nodes.items[root_index].module_rel_path, allocator);
        defer allocator.free(root_import_path);
        try out.print(allocator, "import * as Root from \"{s}\";\n", .{root_import_path});

        var sorted = std.ArrayList(ComponentImport).empty;
        defer sorted.deinit(allocator);

        var iter = self.component_registry.iterator();
        while (iter.next()) |entry| {
            try sorted.append(allocator, .{
                .tag_name = entry.key_ptr.*,
                .node_index = entry.value_ptr.*,
            });
        }

        std.mem.sort(ComponentImport, sorted.items, {}, compareComponentImport);

        for (sorted.items, 0..) |entry, idx| {
            const import_alias = try std.fmt.allocPrint(allocator, "Component_{d}", .{idx});
            defer allocator.free(import_alias);
            const import_path = try ensureRelativeSpecifier(self.nodes.items[entry.node_index].module_rel_path, allocator);
            defer allocator.free(import_path);
            try out.print(allocator, "import * as {s} from \"{s}\";\n", .{ import_alias, import_path });
        }

        try out.appendSlice(allocator,
            \\
            \\export const components = {
            \\
        );
        for (sorted.items, 0..) |entry, idx| {
            try out.print(allocator, "  \"{s}\": Component_{d}", .{ entry.tag_name, idx });
            if (idx + 1 < sorted.items.len) {
                try out.appendSlice(allocator, ",\n");
            } else {
                try out.appendSlice(allocator, "\n");
            }
        }
        try out.appendSlice(allocator,
            \\};
            \\
            \\export const root = Root;
            \\export const cssPath = "./styles.css";
            \\
            \\export function mount(target, props = {}) {
            \\  return Root.mount(target, props);
            \\}
            \\
        );

        return try out.toOwnedSlice(allocator);
    }

    pub fn emitPropsModule(self: *Graph, root_index: usize, allocator: std.mem.Allocator) ![]u8 {
        const props_literal = try self.inferPreviewPropsLiteral(root_index, allocator);
        defer allocator.free(props_literal);

        return try std.fmt.allocPrint(allocator,
            \\export const props = {s};
            \\
        , .{props_literal});
    }

    pub fn emitIndexHtml(self: *Graph, root_index: usize, allocator: std.mem.Allocator) ![]u8 {
        const root_basename = std.fs.path.basename(self.nodes.items[root_index].abs_path);
        const page_title = if (std.mem.endsWith(u8, root_basename, ".weiv"))
            root_basename[0 .. root_basename.len - ".weiv".len]
        else
            root_basename;

        const import_map = try self.emitImportMap(allocator);
        defer allocator.free(import_map);

        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);

        try out.appendSlice(allocator, "<!doctype html>\n<html lang=\"en\">\n  <head>\n");
        try out.appendSlice(allocator, "    <meta charset=\"utf-8\" />\n");
        try out.appendSlice(allocator, "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n");
        try out.print(allocator, "    <title>{s}</title>\n", .{page_title});
        try out.appendSlice(allocator, "    <link rel=\"stylesheet\" href=\"/styles.css\" />\n");
        if (import_map.len > 0) {
            try out.appendSlice(allocator, import_map);
        }
        try out.appendSlice(allocator, "  </head>\n  <body>\n");
        try out.appendSlice(allocator, "    <div id=\"app\"></div>\n");
        try out.appendSlice(allocator, "    <script type=\"module\" src=\"/main.mjs\"></script>\n");
        try out.appendSlice(allocator, "  </body>\n</html>\n");

        return try out.toOwnedSlice(allocator);
    }

    fn emitImportMap(self: *Graph, allocator: std.mem.Allocator) ![]u8 {
        if (self.bare_imports.count() == 0) return try allocator.dupe(u8, "");

        var specifiers = std.ArrayList([]const u8).empty;
        defer specifiers.deinit(allocator);

        var iter = self.bare_imports.keyIterator();
        while (iter.next()) |key| {
            try specifiers.append(allocator, key.*);
        }

        std.mem.sort([]const u8, specifiers.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        var out = std.ArrayList(u8).empty;
        defer out.deinit(allocator);

        try out.appendSlice(allocator, "    <script type=\"importmap\">\n");
        try out.appendSlice(allocator, "    {\n      \"imports\": {\n");

        for (specifiers.items, 0..) |specifier, i| {
            try out.appendSlice(allocator, "        \"");
            try out.appendSlice(allocator, specifier);
            try out.appendSlice(allocator, "\": \"/node_modules/");
            try out.appendSlice(allocator, specifier);
            try out.appendSlice(allocator, "\"");
            if (i + 1 < specifiers.items.len) {
                try out.appendSlice(allocator, ",");
            }
            try out.appendSlice(allocator, "\n");
        }

        try out.appendSlice(allocator, "      }\n    }\n    </script>\n");

        return try out.toOwnedSlice(allocator);
    }

    pub fn emitPackageJson(self: *Graph, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        return try std.fmt.allocPrint(allocator,
            \\{{
            \\  "name": "weiv-preview",
            \\  "private": true,
            \\  "type": "module",
            \\  "scripts": {{
            \\    "dev": "bun --hot server.ts",
            \\    "start": "bun server.ts"
            \\  }}
            \\}}
            \\
        , .{});
    }

    pub fn emitDevServer(self: *Graph, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        return try std.fmt.allocPrint(allocator,
            \\const host = Bun.env.HOST ?? "0.0.0.0";
            \\const port = Number(Bun.env.PORT ?? 3000);
            \\
            \\const server = Bun.serve({{
            \\  hostname: host,
            \\  port,
            \\  async fetch(req) {{
            \\    const url = new URL(req.url);
            \\    const pathname = url.pathname === "/" ? "/index.html" : url.pathname;
            \\    const staticFile = Bun.file(new URL(`.${{pathname}}`, import.meta.url));
            \\
            \\    if (await staticFile.exists()) {{
            \\      return new Response(staticFile);
            \\    }}
            \\
            \\    const fallbackFile = Bun.file(new URL("./index.html", import.meta.url));
            \\    if (await fallbackFile.exists()) {{
            \\      return new Response(fallbackFile);
            \\    }}
            \\
            \\    return new Response("Not Found", {{ status: 404 }});
            \\  }},
            \\}});
            \\
            \\console.log(`weiv preview server running at http://${{host}}:${{server.port}}`);
            \\
        , .{});
    }

    fn registerComponent(self: *Graph, tag_name: []const u8, node_index: usize) !void {
        if (self.component_registry.get(tag_name)) |existing| {
            if (existing != node_index) return error.ComponentTagConflict;
            return;
        }
        const owned_tag_name = try self.allocator.dupe(u8, tag_name);
        errdefer self.allocator.free(owned_tag_name);
        try self.component_registry.put(owned_tag_name, node_index);
    }

    fn registerComponentValidated(
        self: *Graph,
        bag: *compiler_diagnostics.DiagnosticBag,
        importer_node: *const Node,
        tag_name: []const u8,
        span_start: usize,
        span_end: usize,
        node_index: usize,
    ) !void {
        if (self.component_registry.get(tag_name)) |existing| {
            if (existing == node_index) return;

            const span = compiler_diagnostics.Span{
                .start = importer_node.model.sfc_document.script.content_span.start + span_start,
                .end = importer_node.model.sfc_document.script.content_span.start + span_end,
            };
            const message = try std.fmt.allocPrint(
                self.allocator,
                "Component tag `{s}` resolves to multiple .weiv files in the same app emit",
                .{tag_name},
            );
            defer self.allocator.free(message);

            try bag.appendOwned(
                self.allocator,
                "bundle.component_tag_conflict",
                .@"error",
                message,
                .bundle,
                importer_node.abs_path,
                span,
                compiler_diagnostics.computeLocation(importer_node.source, span),
                true,
            );
            return;
        }

        const owned_tag_name = try self.allocator.dupe(u8, tag_name);
        errdefer self.allocator.free(owned_tag_name);
        try self.component_registry.put(owned_tag_name, node_index);
    }

    fn copyRuntimeImport(
        self: *Graph,
        out_dir: std.Io.Dir,
        importer_dir: []const u8,
        source_specifier: []const u8,
        allocator: std.mem.Allocator,
    ) !void {
        if (isWeivRuntimeSpecifier(source_specifier)) {
            try self.copyWeivRuntimeModule(out_dir, allocator);
            return;
        }
        if (std.fs.path.isAbsolute(source_specifier)) return;
        if (!std.mem.startsWith(u8, source_specifier, "./") and
            !std.mem.startsWith(u8, source_specifier, "../"))
        {
            return;
        }

        const abs_source = try std.fs.path.resolve(allocator, &.{ importer_dir, source_specifier });
        defer allocator.free(abs_source);
        const rel_source = try std.fs.path.relative(allocator, ".", null, self.root_dir, abs_source);
        defer allocator.free(rel_source);
        const output_rel_source = try emittedRuntimeImportPath(rel_source, allocator);
        defer allocator.free(output_rel_source);
        if (std.mem.startsWith(u8, output_rel_source, "..")) return error.ExternalRuntimeImportUnsupported;
        if (self.copied_runtime_paths.contains(output_rel_source)) return;

        const file_data = try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), abs_source, allocator, .limited(1024 * 1024));
        defer allocator.free(file_data);
        const module_output = try emitRuntimeImportOutput(file_data, abs_source, output_rel_source, allocator);
        defer allocator.free(module_output);
        if (std.fs.path.dirname(output_rel_source)) |output_dirname| {
            if (!std.mem.eql(u8, output_dirname, ".") and output_dirname.len > 0) {
                try out_dir.createDirPath(std.Io.Threaded.global_single_threaded.io(), output_dirname);
            }
        }
        try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = output_rel_source, .data = module_output });
        try self.copied_runtime_paths.put(try self.allocator.dupe(u8, output_rel_source), {});

        if (!isJavaScriptModule(output_rel_source)) return;

        const dependency_dir = std.fs.path.dirname(abs_source) orelse return;
        const import_scan_source = if (isTranspilableTypeScriptModule(abs_source)) file_data else module_output;
        const nested_imports = try parseJsModuleImports(import_scan_source, allocator);
        defer {
            for (nested_imports) |item| allocator.free(item);
            allocator.free(nested_imports);
        }

        for (nested_imports) |nested_specifier| {
            if (!isWeivRuntimeSpecifier(nested_specifier) and
                !isBrowserLoadableImport(nested_specifier) and
                !isTranspilableTypeScriptModule(nested_specifier)) continue;
            try self.copyRuntimeImport(out_dir, dependency_dir, nested_specifier, allocator);
        }
    }

    fn copyWeivRuntimeModule(self: *Graph, out_dir: std.Io.Dir, allocator: std.mem.Allocator) !void {
        const runtime_source = try std.fs.path.join(allocator, &.{ "packages", "weiv", "src", "runtime", "index.ts" });
        defer allocator.free(runtime_source);
        const runtime_abs_source = try std.Io.Dir.cwd().realPathFileAlloc(std.Io.Threaded.global_single_threaded.io(), runtime_source, allocator);
        defer allocator.free(runtime_abs_source);

        try self.copyWeivRuntimeDependency(out_dir, runtime_abs_source, weiv_runtime_output_entry, allocator);
    }

    fn copyWeivRuntimeDependency(
        self: *Graph,
        out_dir: std.Io.Dir,
        abs_source: []const u8,
        output_rel_source: []const u8,
        allocator: std.mem.Allocator,
    ) !void {
        if (self.copied_runtime_paths.contains(output_rel_source)) return;

        const file_data = try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), abs_source, allocator, .limited(1024 * 1024));
        defer allocator.free(file_data);

        const module_output = try emitRuntimeImportOutput(file_data, abs_source, output_rel_source, allocator);
        defer allocator.free(module_output);
        if (std.fs.path.dirname(output_rel_source)) |output_dirname| {
            if (!std.mem.eql(u8, output_dirname, ".") and output_dirname.len > 0) {
                try out_dir.createDirPath(std.Io.Threaded.global_single_threaded.io(), output_dirname);
            }
        }
        try out_dir.writeFile(std.Io.Threaded.global_single_threaded.io(), .{ .sub_path = output_rel_source, .data = module_output });
        try self.copied_runtime_paths.put(try self.allocator.dupe(u8, output_rel_source), {});

        const dependency_dir = std.fs.path.dirname(abs_source) orelse return;
        const nested_imports = try parseJsModuleImports(file_data, allocator);
        defer {
            for (nested_imports) |item| allocator.free(item);
            allocator.free(nested_imports);
        }

        for (nested_imports) |nested_specifier| {
            if (!isBrowserLoadableImport(nested_specifier) and !isTranspilableTypeScriptModule(nested_specifier)) continue;
            const nested_abs_source = try std.fs.path.resolve(allocator, &.{ dependency_dir, nested_specifier });
            defer allocator.free(nested_abs_source);

            const nested_rewritten = try emittedRuntimeImportPath(nested_specifier, allocator);
            defer allocator.free(nested_rewritten);

            const output_dir = std.fs.path.dirname(output_rel_source) orelse ".";
            const nested_output_rel_source = try std.fs.path.resolvePosix(allocator, &.{ output_dir, nested_rewritten });
            defer allocator.free(nested_output_rel_source);

            try self.copyWeivRuntimeDependency(out_dir, nested_abs_source, nested_output_rel_source, allocator);
        }
    }

    fn inferPreviewPropsLiteral(self: *Graph, root_index: usize, allocator: std.mem.Allocator) ![]u8 {
        const model = &self.nodes.items[root_index].model;
        const props_record = model.script.props orelse return allocator.dupe(u8, "{}");
        const type_name = props_record.props_type_name orelse return allocator.dupe(u8, "{}");

        const script_source = model.sfc_document.script.content;
        const body = findInterfaceBody(script_source, type_name) orelse return allocator.dupe(u8, "{}");
        return try buildPreviewPropsObject(body, allocator);
    }
};

const Node = struct {
    abs_path: []const u8,
    source: []const u8,
    rel_source_path: []const u8,
    module_rel_path: []const u8,
    model: component.ComponentUnit,

    fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        allocator.free(self.abs_path);
        allocator.free(self.source);
        allocator.free(self.rel_source_path);
        allocator.free(self.module_rel_path);
        self.model.deinit(allocator);
    }
};

const ComponentImport = struct {
    tag_name: []const u8,
    node_index: usize,
};

fn compareComponentImport(_: void, a: ComponentImport, b: ComponentImport) bool {
    return std.mem.lessThan(u8, a.tag_name, b.tag_name);
}

fn appendDiagnosticsFromSlice(
    bag: *compiler_diagnostics.DiagnosticBag,
    diagnostics: []const compiler_diagnostics.Diagnostic,
    allocator: std.mem.Allocator,
) !void {
    for (diagnostics) |diagnostic| {
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

fn consumeComponentCompileReport(report: *component.ComponentCompileReport) void {
    report.diagnostics = &.{};
    report.source_path = &.{};
    report.sfc_document = null;
    report.template_document = null;
    report.normalized_template = null;
    report.script = null;
    report.template_bindings = null;
    report.lir_document = null;
    report.halted_after = null;
}

fn replaceExtension(path: []const u8, new_extension: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.endsWith(u8, path, ".weiv")) {
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ path[0 .. path.len - ".weiv".len], new_extension });
    }
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ path, new_extension });
}

fn ensureRelativeSpecifier(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.startsWith(u8, path, "./") or std.mem.startsWith(u8, path, "../")) {
        return try allocator.dupe(u8, path);
    }
    return try std.fmt.allocPrint(allocator, "./{s}", .{path});
}

fn findInterfaceBody(script_source: []const u8, type_name: []const u8) ?[]const u8 {
    var needle_buffer: [256]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buffer, "interface {s}", .{type_name}) catch return null;
    const interface_start = std.mem.indexOf(u8, script_source, needle) orelse return null;
    const body_start = std.mem.indexOfScalarPos(u8, script_source, interface_start, '{') orelse return null;

    var depth: usize = 0;
    var i = body_start;
    while (i < script_source.len) : (i += 1) {
        switch (script_source[i]) {
            '{' => depth += 1,
            '}' => {
                if (depth == 0) return null;
                depth -= 1;
                if (depth == 0) {
                    return script_source[body_start + 1 .. i];
                }
            },
            else => {},
        }
    }
    return null;
}

fn buildPreviewPropsObject(body: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var properties = std.ArrayList(PropertyDefault).empty;
    defer {
        for (properties.items) |property| allocator.free(property.name);
        properties.deinit(allocator);
    }

    var parts = std.mem.splitAny(u8, body, ";\n");
    while (parts.next()) |part_raw| {
        const part = std.mem.trim(u8, part_raw, &std.ascii.whitespace);
        if (part.len == 0) continue;
        if (std.mem.indexOfScalar(u8, part, '(') != null) continue;

        const colon_index = std.mem.indexOfScalar(u8, part, ':') orelse continue;
        const name_raw = std.mem.trim(u8, part[0..colon_index], &std.ascii.whitespace);
        const type_raw = std.mem.trim(u8, part[colon_index + 1 ..], &std.ascii.whitespace);
        const name = std.mem.trimEnd(u8, name_raw, "?");
        if (name.len == 0 or type_raw.len == 0) continue;

        const default_value = inferPreviewLiteralForType(type_raw);
        if (default_value == null) continue;

        try properties.append(allocator, .{
            .name = try allocator.dupe(u8, name),
            .value = default_value.?,
        });
    }

    if (properties.items.len == 0) {
        return allocator.dupe(u8, "{}");
    }

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, "{ ");
    for (properties.items, 0..) |property, idx| {
        try out.print(allocator, "{s}: {s}", .{ property.name, property.value });
        if (idx + 1 < properties.items.len) {
            try out.appendSlice(allocator, ", ");
        }
    }
    try out.appendSlice(allocator, " }");

    return try out.toOwnedSlice(allocator);
}

fn inferPreviewLiteralForType(type_raw: []const u8) ?[]const u8 {
    const type_name = std.mem.trim(u8, type_raw, &std.ascii.whitespace);

    if (std.mem.indexOf(u8, type_name, "[]") != null or std.mem.indexOf(u8, type_name, "Array<") != null) {
        return "[]";
    }
    if (std.mem.indexOf(u8, type_name, "string") != null) {
        return "\"Preview\"";
    }
    if (std.mem.indexOf(u8, type_name, "number") != null or std.mem.indexOf(u8, type_name, "bigint") != null) {
        return "0";
    }
    if (std.mem.indexOf(u8, type_name, "boolean") != null) {
        return "false";
    }
    if (std.mem.startsWith(u8, type_name, "{")) {
        return "{}";
    }
    return null;
}

const PropertyDefault = struct {
    name: []const u8,
    value: []const u8,
};

fn shouldCopyRuntimeImport(
    record: sir.ScriptImport,
    script: *const sir.ScriptFacts,
) bool {
    if (!shouldPreserveRuntimeImport(record, script)) return false;
    if (isWeivRuntimeSpecifier(record.source)) return true;
    return isBrowserLoadableImport(record.source) or isTranspilableTypeScriptModule(record.source);
}

fn shouldPreserveRuntimeImport(
    record: sir.ScriptImport,
    script: *const sir.ScriptFacts,
) bool {
    if (std.mem.endsWith(u8, record.source, ".weiv")) return false;
    if (std.mem.eql(u8, record.kind, "side_effect")) return true;

    for (script.bindings) |binding| {
        if (!std.mem.eql(u8, binding.name, record.local_name)) continue;
        return !std.mem.eql(u8, binding.kind, "type_only");
    }
    return true;
}

fn isBrowserLoadableImport(source: []const u8) bool {
    return std.mem.endsWith(u8, source, ".js") or
        std.mem.endsWith(u8, source, ".mjs") or
        std.mem.endsWith(u8, source, ".json") or
        std.mem.endsWith(u8, source, ".css");
}

fn isTranspilableTypeScriptModule(source: []const u8) bool {
    return std.mem.endsWith(u8, source, ".ts") or std.mem.endsWith(u8, source, ".mts");
}

fn isJavaScriptModule(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".js") or std.mem.endsWith(u8, path, ".mjs");
}

fn parseJsModuleImports(source: []const u8, allocator: std.mem.Allocator) ![][]u8 {
    var imports = std.ArrayList([]u8).empty;
    defer imports.deinit(allocator);

    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, &std.ascii.whitespace);
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "//")) continue;

        if (extractModuleSpecifier(line, "import ")) |specifier| {
            try imports.append(allocator, try allocator.dupe(u8, specifier));
            continue;
        }
        if (extractModuleSpecifier(line, "export ")) |specifier| {
            try imports.append(allocator, try allocator.dupe(u8, specifier));
            continue;
        }
    }

    return try imports.toOwnedSlice(allocator);
}

fn validateRuntimeImportSpecifier(graph: *Graph, importer_path: []const u8, source_specifier: []const u8) !void {
    _ = importer_path;
    if (std.fs.path.isAbsolute(source_specifier)) {
        return error.UnsupportedRuntimeImport;
    }

    if (isWeivRuntimeSpecifier(source_specifier)) {
        return;
    }

    const is_relative = std.mem.startsWith(u8, source_specifier, "./") or
        std.mem.startsWith(u8, source_specifier, "../");
    if (!is_relative) {
        if (!graph.bare_imports.contains(source_specifier)) {
            const duped = try graph.allocator.dupe(u8, source_specifier);
            try graph.bare_imports.put(duped, {});
        }
        return;
    }

    if (!isBrowserLoadableImport(source_specifier) and !isTranspilableTypeScriptModule(source_specifier)) {
        return error.UnsupportedRuntimeImport;
    }
}

const RuntimeImportProblem = struct {
    code: []const u8,
    message: []const u8,
};

fn classifyRuntimeImportProblem(source_specifier: []const u8) ?RuntimeImportProblem {
    if (std.fs.path.isAbsolute(source_specifier)) {
        return .{
            .code = "import.unsupported_absolute_runtime_import",
            .message = "Absolute runtime imports are not supported in app emits",
        };
    }

    if (isWeivRuntimeSpecifier(source_specifier)) {
        return null;
    }

    const is_relative = std.mem.startsWith(u8, source_specifier, "./") or
        std.mem.startsWith(u8, source_specifier, "../");
    if (!is_relative) {
        return null;
    }

    if (!isBrowserLoadableImport(source_specifier) and !isTranspilableTypeScriptModule(source_specifier)) {
        return .{
            .code = "import.unsupported_runtime_import_type",
            .message = "Relative runtime imports must be browser-loadable modules or transpilable TypeScript modules",
        };
    }

    return null;
}

fn emittedRuntimeImportPath(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.endsWith(u8, source, ".ts")) {
        return try std.fmt.allocPrint(allocator, "{s}.js", .{source[0 .. source.len - ".ts".len]});
    }
    if (std.mem.endsWith(u8, source, ".mts")) {
        return try std.fmt.allocPrint(allocator, "{s}.mjs", .{source[0 .. source.len - ".mts".len]});
    }
    return try allocator.dupe(u8, source);
}

fn emitRuntimeImportOutput(source: []const u8, source_path: []const u8, output_rel_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (isTranspilableTypeScriptModule(source_path)) {
        const transpiled = try parser_backend.transpileModule(source, source_path, allocator);
        defer allocator.free(transpiled);
        return try rewriteRuntimeImportSpecifiers(transpiled, output_rel_path, allocator);
    }

    if (isJavaScriptModule(source_path)) {
        return try rewriteRuntimeImportSpecifiers(source, output_rel_path, allocator);
    }

    return try allocator.dupe(u8, source);
}

fn rewriteRuntimeImportSpecifiers(source: []const u8, output_rel_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, source, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(allocator, '\n');
        first = false;
        const rewritten = try rewriteImportLine(line, output_rel_path, allocator);
        defer allocator.free(rewritten);
        try out.appendSlice(allocator, rewritten);
    }

    return try out.toOwnedSlice(allocator);
}

fn rewriteImportLine(line: []const u8, output_rel_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (extractQuotedSpecifier(line)) |specifier| {
        const is_import_export = std.mem.startsWith(u8, std.mem.trimStart(u8, line, &std.ascii.whitespace), "import ") or
            std.mem.startsWith(u8, std.mem.trimStart(u8, line, &std.ascii.whitespace), "export ");
        if (is_import_export and isWeivRuntimeSpecifier(specifier)) {
            const rewritten_specifier = try relativeRuntimePackageSpecifier(specifier, output_rel_path, allocator);
            defer allocator.free(rewritten_specifier);
            return try replaceFirstSpecifier(line, specifier, rewritten_specifier, allocator);
        }
        if (is_import_export and isTranspilableTypeScriptModule(specifier)) {
            const rewritten_specifier = try emittedRuntimeImportPath(specifier, allocator);
            defer allocator.free(rewritten_specifier);
            return try replaceFirstSpecifier(line, specifier, rewritten_specifier, allocator);
        }
    }
    return try allocator.dupe(u8, line);
}

fn relativeRuntimePackageSpecifier(source_specifier: []const u8, output_rel_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const output_dir = std.fs.path.dirname(output_rel_path) orelse ".";
    const runtime_output = runtimeOutputEntryForSpecifier(source_specifier);
    const relative = try relativeBundleSpecifier(output_dir, runtime_output, allocator);
    defer allocator.free(relative);
    if (std.mem.startsWith(u8, relative, "./") or std.mem.startsWith(u8, relative, "../")) {
        return try allocator.dupe(u8, relative);
    }
    return try std.fmt.allocPrint(allocator, "./{s}", .{relative});
}

fn relativeBundleSpecifier(from_dir: []const u8, to_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (from_dir.len == 0 or std.mem.eql(u8, from_dir, ".")) {
        return try allocator.dupe(u8, to_path);
    }

    var up_count: usize = 0;
    var components = std.mem.tokenizeScalar(u8, from_dir, '/');
    while (components.next()) |_| up_count += 1;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < up_count) : (i += 1) {
        try out.appendSlice(allocator, "../");
    }
    try out.appendSlice(allocator, to_path);
    return try out.toOwnedSlice(allocator);
}

fn isWeivRuntimeSpecifier(source_specifier: []const u8) bool {
    return std.mem.eql(u8, source_specifier, weiv_runtime_legacy_package_specifier) or
        std.mem.eql(u8, source_specifier, weiv_virtual_observable_specifier) or
        std.mem.eql(u8, source_specifier, weiv_virtual_router_specifier);
}

fn runtimeOutputEntryForSpecifier(source_specifier: []const u8) []const u8 {
    if (std.mem.eql(u8, source_specifier, weiv_virtual_observable_specifier)) {
        return weiv_runtime_observable_output_entry;
    }
    if (std.mem.eql(u8, source_specifier, weiv_virtual_router_specifier)) {
        return weiv_runtime_router_output_entry;
    }
    return weiv_runtime_output_entry;
}

fn replaceFirstSpecifier(line: []const u8, original: []const u8, replacement: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const start = std.mem.indexOf(u8, line, original) orelse return allocator.dupe(u8, line);
    return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        line[0..start],
        replacement,
        line[start + original.len ..],
    });
}

fn extractModuleSpecifier(line: []const u8, prefix: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, prefix)) return null;

    if (std.mem.indexOf(u8, line, " from ")) |from_index| {
        return extractQuotedSpecifier(line[from_index + " from ".len ..]);
    }

    if (std.mem.startsWith(u8, line, "import ")) {
        return extractQuotedSpecifier(line["import ".len..]);
    }

    return null;
}

fn extractQuotedSpecifier(segment: []const u8) ?[]const u8 {
    const first_quote_index = std.mem.indexOfAny(u8, segment, "\"'") orelse return null;
    const quote = segment[first_quote_index];
    const rest = segment[first_quote_index + 1 ..];
    const end_index = std.mem.indexOfScalar(u8, rest, quote) orelse return null;
    return rest[0..end_index];
}
