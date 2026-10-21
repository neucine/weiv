const std = @import("std");
const browser_component = @import("../component.zig");
const helpers = @import("js_module/helpers.zig");
const node_codegen = @import("js_module/node_codegen.zig");
const tracked_graph = @import("js_module/tracked_graph.zig");
const region_graph = @import("../region_graph.zig");

pub fn emitModule(component: *const browser_component.BrowserComponent, allocator: std.mem.Allocator) ![]u8 {
    const model = component.unit;
    const render_tree = component.render_tree;
    var body = std.ArrayList(u8).empty;
    defer body.deinit(allocator);

    try helpers.emitConditionalHelpers(render_tree.nodes, component.scope_id, component.template_bindings_json, &body, allocator);
    try body.appendSlice(allocator, component.setup_js);
    try body.appendSlice(allocator, "\n");
    try body.print(allocator, "export const scopeId = \"{s}\";\n", .{component.scope_id});
    try body.appendSlice(allocator, "export const css = ");
    try @import("js_module/common.zig").emitString(component.css, &body, allocator);
    try body.appendSlice(allocator, ";\n\n");

    var runtime_graph = try region_graph.build(model, &render_tree, allocator);
    defer runtime_graph.deinit();
    try tracked_graph.emitTrackedStateGraphMetadata(&runtime_graph, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try node_codegen.emitCreateFunction(render_tree, component.scope_id, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try node_codegen.emitRegionUpdateFunctions(render_tree, component.template_bindings_json, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try node_codegen.emitUpdateFunction(render_tree, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try node_codegen.emitSelectiveUpdateFunction(&runtime_graph, render_tree, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try node_codegen.emitDestroyFunction(render_tree, &body, allocator);
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
    try out.appendSlice(allocator, component.preserved_imports);
    try helpers.emitPrelude(&out, allocator);
    try out.appendSlice(allocator, body.items);

    return try out.toOwnedSlice(allocator);
}
