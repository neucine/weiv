const std = @import("std");
const app_emit = @import("compiler/emit/browser/app_bundle.zig");
const component = @import("compiler/pipeline.zig");
const emit_direct_js = @import("compiler/emit/browser/direct_component_js.zig");
const emit_js = @import("compiler/emit/browser/document_js.zig");
const emit_module_js = @import("compiler/emit/browser/component_module_js.zig");
const style = @import("compiler/emit/browser/scoped_css.zig");
const directives = @import("compiler/parse/template/directives.zig");
const ast = @import("compiler/parse/template/ast.zig");
const sfc = @import("compiler/parse/sfc.zig");

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
    try std.testing.expect(std.mem.indexOf(u8, js, "export function mount(target, props = {}, components = {}, eventHandlers = {}, slots = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "export function mountIntoBoundary(start, end, props = {}, components = {}, eventHandlers = {}, slots = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "kind: \"interpolation\"") != null);
}

test "basic counter direct browser module emits create/update DOM contract" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/basic-counter.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/basic-counter.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emit_direct_js.emitModule(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "function createDom(instance)") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "function updateDom(instance)") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "document.createElement(\"section\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "addEventListener(\"click\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "refs[") != null);
}

test "conditional toggle direct browser module emits conditional boundary helpers" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/conditional-toggle.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/conditional-toggle.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emit_direct_js.emitModule(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "createConditionalFragment_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "updateConditional_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "document.createComment(\"if:start\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "replaceBetween(") != null);
}

test "todo list direct browser module emits loop boundary helpers" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/todo-list.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/todo-list.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emit_direct_js.emitModule(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "createForEntry_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "updateForLoop_") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "document.createComment(\"for:start\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "const loopScope = { ...nextScope, [\"item\"]: currentItem };") != null);
}

test "slot outlet and default projection survive through normalized template and IR" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <Panel>
        \\    <p>{{ props.message }}</p>
        \\  </Panel>
        \\</template>
        \\
        \\<script lang="ts">
        \\  import Panel from "./Panel.weiv";
        \\
        \\  export interface Props {
        \\    message: string;
        \\  }
        \\
        \\  export let props: Props;
        \\</script>
    ;

    var model = try component.build(source, "examples/slots/PanelUsage.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.normalized_template.nodes.len);
    switch (model.normalized_template.nodes[0]) {
        .element => |element| {
            try std.testing.expect(std.mem.eql(u8, element.tag_name, "Panel"));
            try std.testing.expectEqual(@as(usize, 1), element.children.len);
        },
        else => return error.UnexpectedNormalizedShape,
    }

    try std.testing.expectEqual(@as(usize, 1), model.ir_document.nodes.len);
    switch (model.ir_document.nodes[0]) {
        .component => |component_node| {
            try std.testing.expect(std.mem.eql(u8, component_node.tag_name, "Panel"));
            try std.testing.expectEqual(@as(usize, 1), component_node.slot_provisions.len);
            try std.testing.expect(component_node.slot_provisions[0].name == null);
            try std.testing.expectEqual(@as(usize, 1), component_node.slot_provisions[0].children.len);
            switch (component_node.slot_provisions[0].children[0]) {
                .element => |child| try std.testing.expect(std.mem.eql(u8, child.tag_name, "p")),
                else => return error.UnexpectedIrShape,
            }
        },
        else => return error.UnexpectedIrShape,
    }
}

test "slot outlet parses and lowers fallback content" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\<template>
        \\  <section>
        \\    <slot>
        \\      <p>Fallback</p>
        \\    </slot>
        \\  </section>
        \\</template>
        \\
        \\<script lang="ts">
        \\  export interface Props {}
        \\  export let props: Props;
        \\</script>
    ;

    var model = try component.build(source, "examples/slots/Panel.weiv", allocator);
    defer model.deinit(allocator);

    switch (model.normalized_template.nodes[0]) {
        .element => |root| {
            try std.testing.expectEqual(@as(usize, 1), root.children.len);
            switch (root.children[0]) {
                .slot_outlet => |slot_outlet| {
                    try std.testing.expect(slot_outlet.name == null);
                    try std.testing.expectEqual(@as(usize, 1), slot_outlet.fallback_children.len);
                },
                else => return error.UnexpectedNormalizedShape,
            }
        },
        else => return error.UnexpectedNormalizedShape,
    }

    switch (model.ir_document.nodes[0]) {
        .element => |root| {
            try std.testing.expectEqual(@as(usize, 1), root.children.len);
            switch (root.children[0]) {
                .slot_outlet => |slot_outlet| {
                    try std.testing.expect(slot_outlet.name == null);
                    try std.testing.expectEqual(@as(usize, 1), slot_outlet.fallback_children.len);
                },
                else => return error.UnexpectedIrShape,
            }
        },
        else => return error.UnexpectedIrShape,
    }
}

test "legacy render module supports default slot projection and fallback" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const panel_source = try readFixture(allocator, "examples/slots/Panel.weiv");
    defer allocator.free(panel_source);
    var panel_model = try component.build(panel_source, "examples/slots/Panel.weiv", allocator);
    defer panel_model.deinit(allocator);

    const panel_usage_source = try readFixture(allocator, "examples/slots/PanelUsage.weiv");
    defer allocator.free(panel_usage_source);
    var usage_model = try component.build(panel_usage_source, "examples/slots/PanelUsage.weiv", allocator);
    defer usage_model.deinit(allocator);

    const panel_js = try emit_module_js.emitModule(&panel_model, allocator);
    defer allocator.free(panel_js);
    const usage_js = try emit_module_js.emitModule(&usage_model, allocator);
    defer allocator.free(usage_js);

    try std.testing.expect(std.mem.indexOf(u8, panel_js, "renderToString(props = {}, components = {}, slots = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, "slots: {\"default\": { nodes: [") != null);
}

test "direct browser modules expose default slot projection contract" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const panel_source = try readFixture(allocator, "examples/slots/Panel.weiv");
    defer allocator.free(panel_source);
    var panel_model = try component.build(panel_source, "examples/slots/Panel.weiv", allocator);
    defer panel_model.deinit(allocator);

    const panel_usage_source = try readFixture(allocator, "examples/slots/PanelUsage.weiv");
    defer allocator.free(panel_usage_source);
    var usage_model = try component.build(panel_usage_source, "examples/slots/PanelUsage.weiv", allocator);
    defer usage_model.deinit(allocator);

    const panel_js = try emit_direct_js.emitModule(&panel_model, allocator);
    defer allocator.free(panel_js);
    const usage_js = try emit_direct_js.emitModule(&usage_model, allocator);
    defer allocator.free(usage_js);

    try std.testing.expect(std.mem.indexOf(u8, panel_js, " = instance.slots?.default;") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "const __slot_") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "export function mountIntoBoundary(start, end, props = {}, eventHandlers = {}, slots = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, panel_js, "setSlots: instance.setSlots") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, "mountProjectedSlot_") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, ".mountIntoBoundary(") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, "default: { mountIntoBoundary: (start, end) => mountProjectedSlot_") != null);
}

test "named slot grouping lowers into explicit slot provisions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/slots/CardUsage.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/slots/CardUsage.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.ir_document.nodes.len);
    switch (model.ir_document.nodes[0]) {
        .component => |component_node| {
            try std.testing.expect(std.mem.eql(u8, component_node.tag_name, "Card"));
            try std.testing.expectEqual(@as(usize, 2), component_node.slot_provisions.len);
            try std.testing.expect(std.mem.eql(u8, component_node.slot_provisions[0].name.?, "header"));
            try std.testing.expectEqual(@as(usize, 2), component_node.slot_provisions[0].children.len);
            try std.testing.expect(component_node.slot_provisions[1].name == null);
            try std.testing.expectEqual(@as(usize, 1), component_node.slot_provisions[1].children.len);
        },
        else => return error.UnexpectedIrShape,
    }
}

test "named slot browser modules expose slot map contract" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const card_source = try readFixture(allocator, "examples/slots/Card.weiv");
    defer allocator.free(card_source);
    var card_model = try component.build(card_source, "examples/slots/Card.weiv", allocator);
    defer card_model.deinit(allocator);

    const card_usage_source = try readFixture(allocator, "examples/slots/CardUsage.weiv");
    defer allocator.free(card_usage_source);
    var usage_model = try component.build(card_usage_source, "examples/slots/CardUsage.weiv", allocator);
    defer usage_model.deinit(allocator);

    const card_js = try emit_direct_js.emitModule(&card_model, allocator);
    defer allocator.free(card_js);
    const usage_js = try emit_direct_js.emitModule(&usage_model, allocator);
    defer allocator.free(usage_js);

    try std.testing.expect(std.mem.indexOf(u8, card_js, " = instance.slots?.[\"header\"];") != null);
    try std.testing.expect(std.mem.indexOf(u8, card_js, "const __slot_") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, "mountProjectedSlot_") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, "\"header\": { mountIntoBoundary: (start, end) => mountProjectedSlot_") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_js, "default: { mountIntoBoundary: (start, end) => mountProjectedSlot_") != null);
}

test "todomvc app direct browser module preserves child component imports" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/todomvc/App.weiv");
    defer allocator.free(source);

    var model = try component.build(source, "examples/todomvc/App.weiv", allocator);
    defer model.deinit(allocator);

    const js = try emit_direct_js.emitModule(&model, allocator);
    defer allocator.free(js);

    try std.testing.expect(std.mem.indexOf(u8, js, "import * as TodoHeader from \"./TodoHeader.mjs\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "import * as TodoList from \"./TodoList.mjs\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, "import * as TodoFooter from \"./TodoFooter.mjs\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, ".mountIntoBoundary(") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, ".setProps(") != null);
    try std.testing.expect(std.mem.indexOf(u8, js, ".setEventHandlers(") != null);
}

test "todomvc direct app bundle emits browser-direct entry files" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_root = try std.fs.path.join(allocator, &.{ ".zig-cache", "tmp", tmp_dir.sub_path[0..] });
    defer allocator.free(tmp_root);
    const out_dir = try std.fs.path.join(allocator, &.{ tmp_root, "direct-bundle" });
    defer allocator.free(out_dir);

    try app_emit.emitAppDirect("examples/todomvc/App.weiv", out_dir, allocator);

    const bundle_js = try tmp_dir.dir.readFileAlloc(allocator, "direct-bundle/bundle.mjs", 1024 * 1024);
    defer allocator.free(bundle_js);
    const main_js = try tmp_dir.dir.readFileAlloc(allocator, "direct-bundle/main.mjs", 1024 * 1024);
    defer allocator.free(main_js);

    try std.testing.expect(std.mem.indexOf(u8, bundle_js, "export function mount(target, props = {})") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_js, "Root.mount(target, props)") != null);
    try std.testing.expect(std.mem.indexOf(u8, bundle_js, "export const components = {") != null);
    try std.testing.expect(std.mem.indexOf(u8, main_js, "AppBundle.mount(target, props);") != null);
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

    try app_emit.emitAppLegacy("examples/classic-todo/App.weiv", out_dir, allocator);

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

    try app_emit.emitAppLegacy("examples/todomvc/App.weiv", out_dir, allocator);

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

    try app_emit.emitAppLegacy("examples/basic-counter.weiv", out_dir, allocator);

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

    try app_emit.emitAppLegacy("examples/imported-helper/App.weiv", out_dir, allocator);

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

    try app_emit.emitAppLegacy("examples/imported-ts-helper/App.weiv", out_dir, allocator);

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
        app_emit.emitAppLegacy("examples/unsupported-import/App.weiv", out_dir, allocator),
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

test "Panel.weiv lowers to a single default slot outlet" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/slots/Panel.weiv");
    defer allocator.free(source);
    var model = try component.build(source, "examples/slots/Panel.weiv", allocator);
    defer model.deinit(allocator);

    // Top-level: <section><slot><p>...</p></slot></section>
    try std.testing.expectEqual(@as(usize, 1), model.ir_document.nodes.len);
    switch (model.ir_document.nodes[0]) {
        .element => |section| {
            try std.testing.expect(std.mem.eql(u8, section.tag_name, "section"));
            try std.testing.expectEqual(@as(usize, 1), section.children.len);
            switch (section.children[0]) {
                .slot_outlet => |so| {
                    try std.testing.expect(so.name == null);
                    // Panel.weiv fallback: <p class="panel__fallback">...</p>
                    try std.testing.expectEqual(@as(usize, 1), so.fallback_children.len);
                },
                else => return error.UnexpectedIrShape,
            }
        },
        else => return error.UnexpectedIrShape,
    }
}

test "Card.weiv lowers to header named slot and default slot with fallbacks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/slots/Card.weiv");
    defer allocator.free(source);
    var model = try component.build(source, "examples/slots/Card.weiv", allocator);
    defer model.deinit(allocator);

    // Top-level: <section><header><slot name="header">...</slot></header><div><slot>...</slot></div></section>
    try std.testing.expectEqual(@as(usize, 1), model.ir_document.nodes.len);
    switch (model.ir_document.nodes[0]) {
        .element => |root| {
            try std.testing.expect(std.mem.eql(u8, root.tag_name, "section"));
            try std.testing.expectEqual(@as(usize, 2), root.children.len);

            switch (root.children[0]) {
                .element => |header| {
                    try std.testing.expect(std.mem.eql(u8, header.tag_name, "header"));
                    try std.testing.expectEqual(@as(usize, 1), header.children.len);
                    switch (header.children[0]) {
                        .slot_outlet => |named_outlet| {
                            try std.testing.expect(std.mem.eql(u8, named_outlet.name.?, "header"));
                            // Fallback: <h2 class="card__fallback-title">Untitled</h2>
                            try std.testing.expectEqual(@as(usize, 1), named_outlet.fallback_children.len);
                        },
                        else => return error.UnexpectedIrShape,
                    }
                },
                else => return error.UnexpectedIrShape,
            }

            switch (root.children[1]) {
                .element => |body| {
                    try std.testing.expect(std.mem.eql(u8, body.tag_name, "div"));
                    try std.testing.expectEqual(@as(usize, 1), body.children.len);
                    switch (body.children[0]) {
                        .slot_outlet => |default_outlet| {
                            try std.testing.expect(default_outlet.name == null);
                            // Fallback: <p class="card__fallback-body">No body content.</p>
                            try std.testing.expectEqual(@as(usize, 1), default_outlet.fallback_children.len);
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

test "slot:name directive carries a non-empty source span" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Construct a hand-built attribute slice that represents `slot:header` at offset 42.
    const input_attrs = [_]ast.Attribute{
        .{
            .name = "slot:header",
            .value = null,
            .span = .{ .start = 42, .end = 53 },
        },
    };

    const result = try directives.split(&input_attrs, allocator);
    defer allocator.free(result.attributes);
    defer allocator.free(result.directives);

    try std.testing.expectEqual(@as(usize, 0), result.attributes.len);
    try std.testing.expectEqual(@as(usize, 1), result.directives.len);

    const slot_dir = result.directives[0].slot_assign;
    try std.testing.expectEqualStrings("header", slot_dir.slot_name);
    try std.testing.expectEqual(@as(usize, 42), slot_dir.span.start);
    try std.testing.expectEqual(@as(usize, 53), slot_dir.span.end);
    try std.testing.expect(slot_dir.span.end > slot_dir.span.start);
}

test "EmptyState.weiv lowers with named message slot and default slot, both with fallbacks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = try readFixture(allocator, "examples/slots/EmptyState.weiv");
    defer allocator.free(source);
    var model = try component.build(source, "examples/slots/EmptyState.weiv", allocator);
    defer model.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), model.ir_document.nodes.len);
    switch (model.ir_document.nodes[0]) {
        .element => |root| {
            try std.testing.expect(std.mem.eql(u8, root.tag_name, "section"));
            try std.testing.expectEqual(@as(usize, 2), root.children.len);

            switch (root.children[0]) {
                .element => |header| {
                    try std.testing.expect(std.mem.eql(u8, header.tag_name, "header"));
                    try std.testing.expectEqual(@as(usize, 1), header.children.len);
                    switch (header.children[0]) {
                        .slot_outlet => |out| {
                            try std.testing.expect(out.name != null);
                            try std.testing.expect(std.mem.eql(u8, out.name.?, "message"));
                            try std.testing.expectEqual(@as(usize, 1), out.fallback_children.len);
                        },
                        else => return error.UnexpectedIrShape,
                    }
                },
                else => return error.UnexpectedIrShape,
            }

            switch (root.children[1]) {
                .element => |body| {
                    try std.testing.expect(std.mem.eql(u8, body.tag_name, "div"));
                    try std.testing.expectEqual(@as(usize, 1), body.children.len);
                    switch (body.children[0]) {
                        .slot_outlet => |out| {
                            try std.testing.expect(out.name == null);
                            try std.testing.expectEqual(@as(usize, 1), out.fallback_children.len);
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
