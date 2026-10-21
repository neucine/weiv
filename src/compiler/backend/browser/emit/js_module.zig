const std = @import("std");
const browser_component = @import("../component.zig");
const runtime_prelude = @import("js_module/runtime_prelude.zig");
const structural_codegen = @import("js_module/structural_codegen.zig");
const dom_create = @import("js_module/dom_create.zig");
const dom_update = @import("js_module/dom_update.zig");
const dom_destroy = @import("js_module/dom_destroy.zig");
const tracked_metadata = @import("js_module/tracked_metadata.zig");
const region_graph = @import("../region_graph.zig");
const setup = @import("js_module/setup.zig");
const scoped_css = @import("scoped_css.zig");

pub fn emitModule(component: *const browser_component.BrowserComponent, allocator: std.mem.Allocator) ![]u8 {
    const model = component.unit;
    const render_tree = component.render_tree;
    const scope_id = try scoped_css.scopeIdForPath(model.source_path, allocator);
    defer allocator.free(scope_id);
    const css = try scoped_css.emitScopedCss(model, allocator);
    defer allocator.free(css);
    const setup_js = try setup.buildSetupCode(model, allocator);
    defer allocator.free(setup_js);
    const preserved_imports = try setup.buildPreservedImports(model, allocator);
    defer allocator.free(preserved_imports);
    const template_bindings_json = try setup.buildTemplateBindingsJson(model, allocator);
    defer allocator.free(template_bindings_json);
    var body = std.ArrayList(u8).empty;
    defer body.deinit(allocator);

    try structural_codegen.emitStructuralHelpers(render_tree.nodes, scope_id, template_bindings_json, &body, allocator);
    try body.appendSlice(allocator, setup_js);
    try body.appendSlice(allocator, "\n");
    try body.print(allocator, "export const scopeId = \"{s}\";\n", .{scope_id});
    try body.appendSlice(allocator, "export const css = ");
    try @import("js_module/common.zig").emitString(css, &body, allocator);
    try body.appendSlice(allocator, ";\n\n");

    var runtime_graph = try region_graph.build(model, &render_tree, allocator);
    defer runtime_graph.deinit();
    try tracked_metadata.emitTrackedStateGraphMetadata(&runtime_graph, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try dom_create.emitCreateFunction(render_tree, scope_id, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try dom_update.emitRegionUpdateFunctions(render_tree, template_bindings_json, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try dom_update.emitUpdateFunction(render_tree, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try dom_update.emitSelectiveUpdateFunction(&runtime_graph, render_tree, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try dom_destroy.emitDestroyFunction(render_tree, &body, allocator);
    try body.appendSlice(allocator,
        \\
        \\export function createInstance(props = {}, eventHandlers = {}, slots = {}) {
        \\  const base = setup(props, eventHandlers);
        \\  const instance = {
        \\    scope: base.scope,
        \\    refresh: base.refresh,
        \\    setProps: base.setProps,
        \\    setEventHandlers: base.setEventHandlers,
        \\    setBoundaryRunner: base.setBoundaryRunner,
        \\    subscribeImportedObservables: base.subscribeImportedObservables,
        \\    slots,
        \\    setSlots: (nextSlots = {}) => { instance.slots = nextSlots; },
        \\    refs: [],
        \\    destroyed: false,
        \\    update: () => {},
        \\    updateDirty: () => {},
        \\    destroy: () => {},
        \\  };
        \\  instance.setBoundaryRunner((callback) => runOwnedBoundary(instance, callback));
        \\  __weiv_registerTrackedSubscriber(instance);
        \\  return instance;
        \\}
        \\
        \\export function mountIntoBoundary(start, end, props = {}, eventHandlers = {}, slots = {}) {
        \\  const instance = createInstance(props, eventHandlers, slots);
        \\  instance.setSlots = (nextSlots = {}) => { instance.slots = nextSlots; };
        \\  const fragment = createDom(instance);
        \\  replaceBetween(start, end, fragment);
        \\  instance.update = () => updateDom(instance);
        \\  instance.updateDirty = (dirtyBindings, scope) => updateDirtyRegions(instance, dirtyBindings, scope);
        \\  const __weiv_unsubscribeImportedObservables = typeof instance.subscribeImportedObservables === "function"
        \\    ? instance.subscribeImportedObservables(instance)
        \\    : null;
        \\  instance.destroy = () => { if (typeof __weiv_unsubscribeImportedObservables === "function") __weiv_unsubscribeImportedObservables(); __weiv_unregisterTrackedSubscriber(instance); instance.destroyed = true; destroyDom(instance); replaceBetween(start, end, document.createDocumentFragment()); };
        \\  instance.update();
        \\  return {
        \\    instance,
        \\    update: instance.update,
        \\    destroy: instance.destroy,
        \\    setProps: instance.setProps,
        \\    setEventHandlers: instance.setEventHandlers,
        \\    setSlots: instance.setSlots,
        \\    start,
        \\    end,
        \\  };
        \\}
        \\
        \\export function mount(target, props = {}, eventHandlers = {}, slots = {}) {
        \\  const start = document.createComment("root:start");
        \\  const end = document.createComment("root:end");
        \\  target.replaceChildren(start, end);
        \\  return mountIntoBoundary(start, end, props, eventHandlers, slots);
        \\}
        \\
    );

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, preserved_imports);
    try runtime_prelude.emitPrelude(&out, allocator);
    try out.appendSlice(allocator, body.items);

    return try out.toOwnedSlice(allocator);
}
