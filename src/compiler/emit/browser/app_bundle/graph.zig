const std = @import("std");
const component = @import("../../../pipeline/index.zig");
const emit_direct_js = @import("../direct_component_js.zig");
const parser_backend = @import("../../../../ffi/parser_backend.zig");
const style = @import("../scoped_css.zig");

pub const Graph = struct {
    root_dir: []const u8,
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node),
    index_by_abs_path: std.StringHashMap(usize),
    component_registry: std.StringHashMap(usize),
    copied_runtime_paths: std.StringHashMap(void),

    pub fn init(root_dir: []const u8, allocator: std.mem.Allocator) Graph {
        return .{
            .root_dir = root_dir,
            .allocator = allocator,
            .nodes = std.ArrayList(Node){},
            .index_by_abs_path = std.StringHashMap(usize).init(allocator),
            .component_registry = std.StringHashMap(usize).init(allocator),
            .copied_runtime_paths = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Graph) void {
        for (self.nodes.items) |*node| node.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.index_by_abs_path.deinit();
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
    }

    pub fn collect(self: *Graph, abs_path: []const u8) !usize {
        if (self.index_by_abs_path.get(abs_path)) |existing| return existing;

        const source = try std.fs.cwd().readFileAlloc(self.allocator, abs_path, 1024 * 1024);
        errdefer self.allocator.free(source);

        const rel_source_path = try std.fs.path.relative(self.allocator, self.root_dir, abs_path);
        errdefer self.allocator.free(rel_source_path);
        const module_rel_path = try replaceExtension(rel_source_path, ".mjs", self.allocator);
        errdefer self.allocator.free(module_rel_path);

        var model = try component.build(source, abs_path, self.allocator);
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

    pub fn emitStylesheet(self: *Graph, allocator: std.mem.Allocator) ![]u8 {
        var out = std.ArrayList(u8){};
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

    pub fn writeComponentModulesDirect(self: *Graph, out_dir: std.fs.Dir, allocator: std.mem.Allocator) !void {
        for (self.nodes.items) |*node| {
            const js = try emit_direct_js.emitModule(&node.model, allocator);
            defer allocator.free(js);
            try out_dir.writeFile(.{ .sub_path = node.module_rel_path, .data = js });
        }
    }

    pub fn writeRuntimeImports(self: *Graph, out_dir: std.fs.Dir, allocator: std.mem.Allocator) !void {
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
                try validateRuntimeImportSpecifier(node.abs_path, import_record.source);
            }
        }
    }

    pub fn emitBrowserEntry(self: *Graph, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        return try std.fmt.allocPrint(allocator,
            \\import * as AppBundle from "./bundle.mjs";
            \\import {{ props as previewProps }} from "./props.mjs";
            \\
            \\const target = document.getElementById("app");
            \\const props = globalThis.__WEIV_PROPS__ ?? previewProps;
            \\
            \\if (target) {{
            \\  AppBundle.mount(target, props);
            \\}}
            \\
            \\globalThis.__WEIV_BUNDLE__ = AppBundle;
            \\
            \\export * from "./bundle.mjs";
            \\export default AppBundle;
            \\
        , .{});
    }

    pub fn emitDirectEntry(self: *Graph, root_index: usize, allocator: std.mem.Allocator) ![]u8 {
        var out = std.ArrayList(u8){};
        defer out.deinit(allocator);

        const root_import_path = try ensureRelativeSpecifier(self.nodes.items[root_index].module_rel_path, allocator);
        defer allocator.free(root_import_path);
        try out.writer(allocator).print("import * as Root from \"{s}\";\n", .{root_import_path});

        var sorted = std.ArrayList(ComponentImport){};
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
            try out.writer(allocator).print("import * as {s} from \"{s}\";\n", .{ import_alias, import_path });
        }

        try out.appendSlice(allocator,
            \\
            \\export const components = {
            \\
        );
        for (sorted.items, 0..) |entry, idx| {
            try out.writer(allocator).print("  \"{s}\": Component_{d}", .{ entry.tag_name, idx });
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

        return try std.fmt.allocPrint(allocator,
            \\<!doctype html>
            \\<html lang="en">
            \\  <head>
            \\    <meta charset="utf-8" />
            \\    <meta name="viewport" content="width=device-width, initial-scale=1" />
            \\    <title>{s}</title>
            \\    <link rel="stylesheet" href="./styles.css" />
            \\  </head>
            \\  <body>
            \\    <div id="app"></div>
            \\    <script type="module" src="./main.mjs"></script>
            \\  </body>
            \\</html>
            \\
        , .{page_title});
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
            \\    const file = Bun.file(new URL(`.${{pathname}}`, import.meta.url));
            \\
            \\    if (!(await file.exists())) {{
            \\      return new Response("Not Found", {{ status: 404 }});
            \\    }}
            \\
            \\    return new Response(file);
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

    fn copyRuntimeImport(
        self: *Graph,
        out_dir: std.fs.Dir,
        importer_dir: []const u8,
        source_specifier: []const u8,
        allocator: std.mem.Allocator,
    ) !void {
        if (std.fs.path.isAbsolute(source_specifier)) return;
        if (!std.mem.startsWith(u8, source_specifier, "./") and
            !std.mem.startsWith(u8, source_specifier, "../"))
        {
            return;
        }

        const abs_source = try std.fs.path.resolve(allocator, &.{ importer_dir, source_specifier });
        defer allocator.free(abs_source);
        const rel_source = try std.fs.path.relative(allocator, self.root_dir, abs_source);
        defer allocator.free(rel_source);
        const output_rel_source = try emittedRuntimeImportPath(rel_source, allocator);
        defer allocator.free(output_rel_source);
        if (std.mem.startsWith(u8, output_rel_source, "..")) return error.ExternalRuntimeImportUnsupported;
        if (self.copied_runtime_paths.contains(output_rel_source)) return;

        const file_data = try std.fs.cwd().readFileAlloc(allocator, abs_source, 1024 * 1024);
        defer allocator.free(file_data);
        const module_output = try emitRuntimeImportOutput(file_data, abs_source, allocator);
        defer allocator.free(module_output);
        try out_dir.writeFile(.{ .sub_path = output_rel_source, .data = module_output });
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
            if (!isBrowserLoadableImport(nested_specifier) and !isTranspilableTypeScriptModule(nested_specifier)) continue;
            try self.copyRuntimeImport(out_dir, dependency_dir, nested_specifier, allocator);
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
    model: component.ComponentModel,

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
    var properties = std.ArrayList(PropertyDefault){};
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
        const name = std.mem.trimRight(u8, name_raw, "?");
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

    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);

    try out.appendSlice(allocator, "{ ");
    for (properties.items, 0..) |property, idx| {
        try out.writer(allocator).print("{s}: {s}", .{ property.name, property.value });
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
    record: @import("../../../analyze/ts/analysis.zig").ImportRecord,
    script: *const @import("../../../analyze/ts/analysis.zig").ScriptAnalysis,
) bool {
    if (!shouldPreserveRuntimeImport(record, script)) return false;
    return isBrowserLoadableImport(record.source) or isTranspilableTypeScriptModule(record.source);
}

fn shouldPreserveRuntimeImport(
    record: @import("../../../analyze/ts/analysis.zig").ImportRecord,
    script: *const @import("../../../analyze/ts/analysis.zig").ScriptAnalysis,
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
    var imports = std.ArrayList([]u8){};
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

fn validateRuntimeImportSpecifier(importer_path: []const u8, source_specifier: []const u8) !void {
    if (std.fs.path.isAbsolute(source_specifier)) {
        std.debug.print("error: unsupported absolute runtime import in {s}: {s}\n", .{ importer_path, source_specifier });
        return error.UnsupportedRuntimeImport;
    }

    const is_relative = std.mem.startsWith(u8, source_specifier, "./") or
        std.mem.startsWith(u8, source_specifier, "../");
    if (!is_relative) {
        std.debug.print("error: unsupported bare runtime import in {s}: {s}\n", .{ importer_path, source_specifier });
        return error.UnsupportedRuntimeImport;
    }

    if (!isBrowserLoadableImport(source_specifier) and !isTranspilableTypeScriptModule(source_specifier)) {
        std.debug.print("error: unsupported runtime import type in {s}: {s}\n", .{ importer_path, source_specifier });
        return error.UnsupportedRuntimeImport;
    }
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

fn emitRuntimeImportOutput(source: []const u8, source_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (isTranspilableTypeScriptModule(source_path)) {
        const transpiled = try parser_backend.transpileModule(source, source_path, allocator);
        defer allocator.free(transpiled);
        return try rewriteRuntimeImportSpecifiers(transpiled, allocator);
    }

    if (isJavaScriptModule(source_path)) {
        return try rewriteRuntimeImportSpecifiers(source, allocator);
    }

    return try allocator.dupe(u8, source);
}

fn rewriteRuntimeImportSpecifiers(source: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, source, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(allocator, '\n');
        first = false;
        const rewritten = try rewriteImportLine(line, allocator);
        defer allocator.free(rewritten);
        try out.appendSlice(allocator, rewritten);
    }

    return try out.toOwnedSlice(allocator);
}

fn rewriteImportLine(line: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (extractQuotedSpecifier(line)) |specifier| {
        const is_import_export = std.mem.startsWith(u8, std.mem.trimLeft(u8, line, &std.ascii.whitespace), "import ") or
            std.mem.startsWith(u8, std.mem.trimLeft(u8, line, &std.ascii.whitespace), "export ");
        if (is_import_export and isTranspilableTypeScriptModule(specifier)) {
            const rewritten_specifier = try emittedRuntimeImportPath(specifier, allocator);
            defer allocator.free(rewritten_specifier);
            return try replaceFirstSpecifier(line, specifier, rewritten_specifier, allocator);
        }
    }
    return try allocator.dupe(u8, line);
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
