const std = @import("std");
const app_emit = @import("compiler/emit/browser/app_bundle.zig");
const component = @import("compiler/pipeline.zig");
const emit_js = @import("compiler/emit/browser/document_js.zig");
const emit_module_js = @import("compiler/emit/browser/component_module_js.zig");
const style = @import("compiler/emit/browser/scoped_css.zig");

test "classic todo app components build through current pipeline" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "examples/classic-todo/App.weiv"),
        "examples/classic-todo/App.weiv",
        1,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "examples/classic-todo/TodoList.weiv"),
        "examples/classic-todo/TodoList.weiv",
        1,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "examples/classic-todo/TodoItem.weiv"),
        "examples/classic-todo/TodoItem.weiv",
        0,
        0,
    );
}

test "todomvc verification app components build through current pipeline" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "examples/todomvc/App.weiv"),
        "examples/todomvc/App.weiv",
        3,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "examples/todomvc/TodoHeader.weiv"),
        "examples/todomvc/TodoHeader.weiv",
        1,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "examples/todomvc/TodoFooter.weiv"),
        "examples/todomvc/TodoFooter.weiv",
        0,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "examples/todomvc/TodoList.weiv"),
        "examples/todomvc/TodoList.weiv",
        1,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "examples/todomvc/TodoItem.weiv"),
        "examples/todomvc/TodoItem.weiv",
        1,
        0,
    );
    try expectComponentBuild(
        allocator,
        try readFixture(allocator, "examples/todomvc/TodoTextInput.weiv"),
        "examples/todomvc/TodoTextInput.weiv",
        0,
        0,
    );
}

test "classic todo app app component lowers to expected IR shape" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/classic-todo/App.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/classic-todo/App.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.ir_document.nodes.len);

    switch (model.ir_document.nodes[0]) {
        .element => |root| {
            try std.testing.expect(std.mem.eql(u8, root.tag_name, "main"));
            try std.testing.expectEqual(@as(usize, 1), root.children.len);

            switch (root.children[0]) {
                .element => |shell| {
                    try std.testing.expect(std.mem.eql(u8, shell.tag_name, "div"));
                    try std.testing.expectEqual(@as(usize, 2), shell.children.len);

                    switch (shell.children[1]) {
                        .element => |panel| {
                            try std.testing.expect(std.mem.eql(u8, panel.tag_name, "section"));
                            try std.testing.expectEqual(@as(usize, 2), panel.children.len);

                            switch (panel.children[1]) {
                                .component => |child| {
                                    try std.testing.expect(std.mem.eql(u8, child.tag_name, "TodoList"));
                                    try std.testing.expectEqual(@as(usize, 3), child.effects.len);
                                },
                                else => return error.UnexpectedIrShape,
                            }
                        },
                        else => return error.UnexpectedIrShape,
                    }
                },
                else => return error.UnexpectedIrShape,
            }
        },
        else => return error.UnexpectedIrShape,
    }
}

test "classic todo list component emits expected structural JS markers" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/classic-todo/TodoList.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/classic-todo/TodoList.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emit_js.emitDocument(&model.ir_document, allocator);
    defer allocator.free(js);

    const expected = try readFixture(allocator, "tools/fixtures/expected/classic-todo-list.emit.js");
    defer allocator.free(expected);
    try std.testing.expectEqualStrings(expected, js);
}

test "classic todo app component emits expected JS snapshot" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/classic-todo/App.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/classic-todo/App.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emit_js.emitDocument(&model.ir_document, allocator);
    defer allocator.free(js);

    const expected = try readFixture(allocator, "tools/fixtures/expected/classic-todo-app.emit.js");
    defer allocator.free(expected);
    try std.testing.expectEqualStrings(expected, js);
}

test "basic counter render module exposes renderToString contract" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/basic-counter.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/basic-counter.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emit_module_js.emitModule(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "export function renderToString") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function setup(__weiv_props, __weiv_emit = () => {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "import { renderNodes, mountNodes, createBoundary, replaceBoundary } from \"./weiv-runtime.mjs\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "export const scopeId = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "export const css = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "export function mount(target, props = {}, components = {}, eventHandlers = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "export function mountIntoBoundary(start, end, props = {}, components = {}, eventHandlers = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "kind: \"interpolation\"") != null);
}

test "imported helper render module preserves runtime JS imports" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/imported-helper/App.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/imported-helper/App.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emit_module_js.emitModule(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "import { formatTitle } from \"./format.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "return formatTitle(props.title);") != null);
}

test "imported TS helper render module rewrites runtime imports to JS" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/imported-ts-helper/App.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/imported-ts-helper/App.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emit_module_js.emitModule(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "import { formatTitle } from \"./format.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "return formatTitle(props.title);") != null);
}

test "basic counter emits scoped CSS" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/basic-counter.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/basic-counter.weiv", allocator);
    defer model.deinit(allocator);

    const scope_id = try style.scopeIdForPath(model.source_path, allocator);
    defer allocator.free(scope_id);
    const css = try style.emitScopedCss(&model, allocator);
    defer allocator.free(css);

    const expected_prefix = try std.fmt.allocPrint(allocator, "[data-weiv-scope=\"{s}\"] .counter-card", .{scope_id});
    defer allocator.free(expected_prefix);

    try std.testing.expect(std.mem.indexOf(u8, css, expected_prefix) != null);
    try std.testing.expect(std.mem.indexOf(u8, css, "border-radius: 16px;") != null);
}

test "classic todo app emits multi-file app bundle" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitApp("examples/classic-todo/App.weiv", out_dir, allocator);

    const app_js = try tmp_dir.dir.readFileAlloc(allocator, "bundle/bundle.mjs", 1024 * 1024);
    defer allocator.free(app_js);
    const browser_entry_js = try tmp_dir.dir.readFileAlloc(allocator, "bundle/main.mjs", 1024 * 1024);
    defer allocator.free(browser_entry_js);
    const props_js = try tmp_dir.dir.readFileAlloc(allocator, "bundle/props.mjs", 1024 * 1024);
    defer allocator.free(props_js);
    const index_html = try tmp_dir.dir.readFileAlloc(allocator, "bundle/index.html", 1024 * 1024);
    defer allocator.free(index_html);
    const package_json = try tmp_dir.dir.readFileAlloc(allocator, "bundle/package.json", 1024 * 1024);
    defer allocator.free(package_json);
    const dev_server_ts = try tmp_dir.dir.readFileAlloc(allocator, "bundle/server.ts", 1024 * 1024);
    defer allocator.free(dev_server_ts);
    const root_module_js = try tmp_dir.dir.readFileAlloc(allocator, "bundle/App.mjs", 1024 * 1024);
    defer allocator.free(root_module_js);
    const list_module_js = try tmp_dir.dir.readFileAlloc(allocator, "bundle/TodoList.mjs", 1024 * 1024);
    defer allocator.free(list_module_js);
    const styles_css = try tmp_dir.dir.readFileAlloc(allocator, "bundle/styles.css", 1024 * 1024);
    defer allocator.free(styles_css);

    try std.testing.expect(std.mem.indexOf(u8, app_js, "export function renderToString") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "\"TodoList\": Component_") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "\"TodoItem\": Component_") != null);
    try std.testing.expect(std.mem.indexOf(u8, browser_entry_js, "import { props as previewProps } from \"./props.mjs\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, browser_entry_js, "const props = globalThis.__WEIV_PROPS__ ?? previewProps;") != null);
    try std.testing.expect(std.mem.indexOf(u8, browser_entry_js, "AppBundle.mount(target, props);") != null);
    try std.testing.expect(std.mem.indexOf(u8, browser_entry_js, "globalThis.__WEIV_BUNDLE__ = AppBundle;") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "export const props = { title: \"Preview\" };") != null);
    try std.testing.expect(std.mem.indexOf(u8, index_html, "<link rel=\"stylesheet\" href=\"./styles.css\" />") != null);
    try std.testing.expect(std.mem.indexOf(u8, index_html, "<script type=\"module\" src=\"./main.mjs\"></script>") != null);
    try std.testing.expect(std.mem.indexOf(u8, package_json, "\"dev\": \"bun --hot server.ts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, package_json, "\"start\": \"bun server.ts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, dev_server_ts, "const server = Bun.serve({") != null);
    try std.testing.expect(std.mem.indexOf(u8, dev_server_ts, "pathname === \"/\" ? \"/index.html\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, root_module_js, "export const scopeId = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, app_js, "export function mount(target, props = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, list_module_js, "export const css = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, "[data-weiv-scope=") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".todo-app") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".todo-list") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".todo-item") != null);
}

test "todomvc verification app emits multi-file app bundle" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "todomvc-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitApp("examples/todomvc/App.weiv", out_dir, allocator);

    const app_js = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/bundle.mjs", 1024 * 1024);
    defer allocator.free(app_js);
    const expected_app_js = try readFixture(allocator, "tools/fixtures/expected/todomvc-app/bundle.mjs");
    defer allocator.free(expected_app_js);
    const props_js = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/props.mjs", 1024 * 1024);
    defer allocator.free(props_js);
    const expected_props_js = try readFixture(allocator, "tools/fixtures/expected/todomvc-app/props.mjs");
    defer allocator.free(expected_props_js);
    const browser_entry_js = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/main.mjs", 1024 * 1024);
    defer allocator.free(browser_entry_js);
    const expected_browser_entry_js = try readFixture(allocator, "tools/fixtures/expected/todomvc-app/main.mjs");
    defer allocator.free(expected_browser_entry_js);
    const index_html = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/index.html", 1024 * 1024);
    defer allocator.free(index_html);
    const expected_index_html = try readFixture(allocator, "tools/fixtures/expected/todomvc-app/index.html");
    defer allocator.free(expected_index_html);
    const package_json = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/package.json", 1024 * 1024);
    defer allocator.free(package_json);
    const expected_package_json = try readFixture(allocator, "tools/fixtures/expected/todomvc-app/package.json");
    defer allocator.free(expected_package_json);
    const dev_server_ts = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/server.ts", 1024 * 1024);
    defer allocator.free(dev_server_ts);
    const expected_dev_server_ts = try readFixture(allocator, "tools/fixtures/expected/todomvc-app/server.ts");
    defer allocator.free(expected_dev_server_ts);
    const root_module_js = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/App.mjs", 1024 * 1024);
    defer allocator.free(root_module_js);
    const header_module_js = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/TodoHeader.mjs", 1024 * 1024);
    defer allocator.free(header_module_js);
    const footer_module_js = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/TodoFooter.mjs", 1024 * 1024);
    defer allocator.free(footer_module_js);
    const list_module_js = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/TodoList.mjs", 1024 * 1024);
    defer allocator.free(list_module_js);
    const item_module_js = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/TodoItem.mjs", 1024 * 1024);
    defer allocator.free(item_module_js);
    const text_input_module_js = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/TodoTextInput.mjs", 1024 * 1024);
    defer allocator.free(text_input_module_js);
    const styles_css = try tmp_dir.dir.readFileAlloc(allocator, "todomvc-bundle/styles.css", 1024 * 1024);
    defer allocator.free(styles_css);

    try std.testing.expectEqualStrings(expected_app_js, app_js);
    try std.testing.expectEqualStrings(expected_browser_entry_js, browser_entry_js);
    try std.testing.expectEqualStrings(expected_props_js, props_js);
    try std.testing.expectEqualStrings(expected_index_html, index_html);
    try std.testing.expectEqualStrings(expected_package_json, package_json);
    try std.testing.expectEqualStrings(expected_dev_server_ts, dev_server_ts);
    try std.testing.expect(std.mem.indexOf(u8, root_module_js, "toggle-all") != null);
    try std.testing.expect(std.mem.indexOf(u8, header_module_js, "What needs to be done?") != null);
    try std.testing.expect(std.mem.indexOf(u8, footer_module_js, "Clear completed") != null);
    try std.testing.expect(std.mem.indexOf(u8, list_module_js, "todo-list") != null);
    try std.testing.expect(std.mem.indexOf(u8, item_module_js, "destroy") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_input_module_js, "emit(\"submit\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".todo-header") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".todo-footer") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".toggle-all") != null);
    try std.testing.expect(std.mem.indexOf(u8, styles_css, ".newtodo") != null);
}

test "basic counter app bundle emits inferred preview props" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "counter-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitApp("examples/basic-counter.weiv", out_dir, allocator);

    const props_js = try tmp_dir.dir.readFileAlloc(allocator, "counter-bundle/props.mjs", 1024 * 1024);
    defer allocator.free(props_js);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "title: \"Preview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "initialCount: 0") != null);
}

test "imported helper app bundle copies runtime JS dependencies" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "imported-helper-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitApp("examples/imported-helper/App.weiv", out_dir, allocator);

    const app_js = try tmp_dir.dir.readFileAlloc(allocator, "imported-helper-bundle/App.mjs", 1024 * 1024);
    defer allocator.free(app_js);
    const helper_js = try tmp_dir.dir.readFileAlloc(allocator, "imported-helper-bundle/format.js", 1024 * 1024);
    defer allocator.free(helper_js);
    const punctuation_js = try tmp_dir.dir.readFileAlloc(allocator, "imported-helper-bundle/punctuation.js", 1024 * 1024);
    defer allocator.free(punctuation_js);
    const props_js = try tmp_dir.dir.readFileAlloc(allocator, "imported-helper-bundle/props.mjs", 1024 * 1024);
    defer allocator.free(props_js);

    try std.testing.expect(std.mem.indexOf(u8, app_js, "import { formatTitle } from \"./format.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, helper_js, "import { suffix } from \"./punctuation.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, helper_js, "export function formatTitle") != null);
    try std.testing.expect(std.mem.indexOf(u8, punctuation_js, "export const suffix = \"!\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "title: \"Preview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "count: 0") != null);
}

test "imported TS helper app bundle transpiles and copies TS dependencies" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "imported-ts-helper-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitApp("examples/imported-ts-helper/App.weiv", out_dir, allocator);

    const app_js = try tmp_dir.dir.readFileAlloc(allocator, "imported-ts-helper-bundle/App.mjs", 1024 * 1024);
    defer allocator.free(app_js);
    const format_js = try tmp_dir.dir.readFileAlloc(allocator, "imported-ts-helper-bundle/format.js", 1024 * 1024);
    defer allocator.free(format_js);
    const punctuation_js = try tmp_dir.dir.readFileAlloc(allocator, "imported-ts-helper-bundle/punctuation.js", 1024 * 1024);
    defer allocator.free(punctuation_js);
    const props_js = try tmp_dir.dir.readFileAlloc(allocator, "imported-ts-helper-bundle/props.mjs", 1024 * 1024);
    defer allocator.free(props_js);

    try std.testing.expect(std.mem.indexOf(u8, app_js, "import { formatTitle } from \"./format.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, format_js, "import { suffix } from \"./punctuation.js\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, format_js, "export function formatTitle(value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, punctuation_js, "export const suffix = \"!\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "title: \"Preview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, props_js, "count: 0") != null);
}

test "emit app rejects unsupported bare runtime imports" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "unsupported-import-bundle" });
    defer allocator.free(out_dir);

    try std.testing.expectError(
        error.UnsupportedRuntimeImport,
        app_emit.emitApp("examples/unsupported-import/App.weiv", out_dir, allocator),
    );
}

fn expectComponentBuild(
    allocator: std.mem.Allocator,
    source: []const u8,
    path: []const u8,
    expected_component_refs: usize,
    expected_binding_diagnostics: usize,
) !void {
    defer allocator.free(source);
    var model = try component.build(source, path, allocator);
    defer model.deinit(allocator);

    try std.testing.expect(model.script.ok);
    try std.testing.expectEqual(@as(usize, 0), model.script.diagnostics.len);
    try std.testing.expectEqual(expected_component_refs, model.binding_result.component_refs.len);
    try std.testing.expectEqual(expected_binding_diagnostics, model.binding_result.diagnostics.len);
}

fn readFixture(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
}
