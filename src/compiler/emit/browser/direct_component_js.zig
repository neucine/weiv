const std = @import("std");
const component = @import("../../pipeline/index.zig");
const browser_plan = @import("../../lower/browser_plan/index.zig");
const style = @import("scoped_css.zig");
const setup = @import("direct_component_js/setup.zig");
const helpers = @import("direct_component_js/helpers.zig");
const node_codegen = @import("direct_component_js/node_codegen.zig");

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

    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);

    try out.appendSlice(allocator, preserved_imports);
    try helpers.emitPrelude(&out, allocator);
    try helpers.emitConditionalHelpers(plan.nodes, scope_id, &out, allocator);
    try out.appendSlice(allocator, setup_js);
    try out.appendSlice(allocator, "\n");
    try out.writer(allocator).print("export const scopeId = \"{s}\";\n", .{scope_id});
    try out.appendSlice(allocator, "export const css = ");
    try @import("direct_component_js/common.zig").emitString(css, &out, allocator);
    try out.appendSlice(allocator, ";\n\n");
    try node_codegen.emitCreateFunction(plan, scope_id, &out, allocator);
    try out.appendSlice(allocator, "\n");
    try node_codegen.emitRegionUpdateFunctions(plan, &out, allocator);
    try out.appendSlice(allocator, "\n");
    try node_codegen.emitUpdateFunction(plan, &out, allocator);
    try out.appendSlice(allocator, "\n");
    try node_codegen.emitDestroyFunction(plan, &out, allocator);
    try out.appendSlice(allocator,
        \\
        \\export function createInstance(props = {}, eventHandlers = {}, slots = {}) {
        \\  const base = setup(props, eventHandlers);
        \\  const instance = {
        \\    scope: base.scope,
        \\    refresh: base.refresh,
        \\    setProps: base.setProps,
        \\    setEventHandlers: base.setEventHandlers,
        \\    setBoundaryRunner: base.setBoundaryRunner,
        \\    slots,
        \\    setSlots: (nextSlots = {}) => { instance.slots = nextSlots; },
        \\    refs: [],
        \\    destroyed: false,
        \\    update: () => {},
        \\    destroy: () => {},
        \\  };
        \\  instance.setBoundaryRunner((callback) => runOwnedBoundary(instance, callback));
        \\  return instance;
        \\}
        \\
        \\export function mountIntoBoundary(start, end, props = {}, eventHandlers = {}, slots = {}) {
        \\  const instance = createInstance(props, eventHandlers, slots);
        \\  instance.setSlots = (nextSlots = {}) => { instance.slots = nextSlots; };
        \\  const fragment = createDom(instance);
        \\  replaceBetween(start, end, fragment);
        \\  instance.update = () => updateDom(instance);
        \\  instance.destroy = () => { instance.destroyed = true; destroyDom(instance); replaceBetween(start, end, document.createDocumentFragment()); };
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

    return try out.toOwnedSlice(allocator);
}
