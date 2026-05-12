const std = @import("std");
const component = @import("../../pipeline/index.zig");
const browser_plan = @import("../../lower/browser_plan/index.zig");
const style = @import("scoped_css.zig");
const setup = @import("emit_sfc/setup.zig");
const helpers = @import("emit_sfc/helpers.zig");
const node_codegen = @import("emit_sfc/node_codegen.zig");

fn buildBindingsJson(model: *const component.ComponentModel, allocator: std.mem.Allocator) ![]u8 {
    var json = std.ArrayList(u8){};
    defer json.deinit(allocator);
    try json.append(allocator, '[');
    var first = true;
    for (model.script.bindings) |binding| {
        if (!binding.template_visible) continue;
        if (!first) try json.append(allocator, ',');
        try json.append(allocator, '"');
        try json.appendSlice(allocator, binding.name);
        try json.append(allocator, '"');
        first = false;
    }
    try json.append(allocator, ']');
    return try json.toOwnedSlice(allocator);
}

pub fn emitModule(model: *const component.ComponentModel, allocator: std.mem.Allocator) ![]u8 {
    var plan = try browser_plan.lower(&model.ir_document, allocator);
    defer plan.deinit(allocator);

    const setup_js = try setup.buildSetupCode(model, allocator);
    defer allocator.free(setup_js);
    const preserved_imports = try setup.buildPreservedImports(model, allocator);
    defer allocator.free(preserved_imports);
    const scope_id = try style.scopeIdForPath(model.source_path, allocator);
    defer allocator.free(scope_id);
    const css = try style.emitScopedCss(model, allocator);
    defer allocator.free(css);

    const bindings_json = try buildBindingsJson(model, allocator);
    defer allocator.free(bindings_json);

    var body = std.ArrayList(u8){};
    defer body.deinit(allocator);

    try helpers.emitConditionalHelpers(plan.nodes, scope_id, bindings_json, &body, allocator);
    try body.appendSlice(allocator, setup_js);
    try body.appendSlice(allocator, "\n");
    try body.writer(allocator).print("export const scopeId = \"{s}\";\n", .{scope_id});
    try body.appendSlice(allocator, "export const css = ");
    try @import("emit_sfc/common.zig").emitString(css, &body, allocator);
    try body.appendSlice(allocator, ";\n\n");

    try node_codegen.emitTrackedStateGraphMetadata(model, plan, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try node_codegen.emitCreateFunction(plan, scope_id, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try node_codegen.emitRegionUpdateFunctions(plan, bindings_json, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try node_codegen.emitUpdateFunction(plan, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try node_codegen.emitSelectiveUpdateFunction(model, plan, &body, allocator);
    try body.appendSlice(allocator, "\n");
    try node_codegen.emitDestroyFunction(plan, &body, allocator);
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

    const needs_evaluate = std.mem.indexOf(u8, body.items, "__weiv_evaluate(") != null;

    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);
    try out.appendSlice(allocator, preserved_imports);
    try helpers.emitPrelude(&out, allocator, needs_evaluate);
    try out.appendSlice(allocator, body.items);

    return try out.toOwnedSlice(allocator);
}
