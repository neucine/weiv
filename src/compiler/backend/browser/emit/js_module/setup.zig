const std = @import("std");
const component = @import("../../../../component_unit.zig");
const tracked_roots = @import("../../tracked_roots.zig");
const common = @import("common.zig");

pub fn buildTemplateBindingsJson(unit: *const component.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    var json = std.ArrayList(u8).empty;
    defer json.deinit(allocator);
    try json.append(allocator, '[');
    var first = true;
    for (unit.script.bindings) |binding| {
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

pub fn buildSetupCode(model: *const component.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator,
        \\function setup(__weiv_props, __weiv_event_handlers = {}) {
        \\  let props = __weiv_props;
        \\  let __weiv_handlers = __weiv_event_handlers;
        \\  let __weiv_runBoundary = (callback) => callback();
        \\  const weivUpdate = (callback) => __weiv_runBoundary(callback);
        \\  const __weiv_wrapCallback = (callback) => {
        \\    if (typeof callback !== "function") {
        \\      return callback;
        \\    }
        \\    return (...args) => __weiv_runBoundary(() => callback(...args));
        \\  };
        \\  const setTimeout = (callback, ...args) => globalThis.setTimeout(__weiv_wrapCallback(callback), ...args);
        \\  const setInterval = (callback, ...args) => globalThis.setInterval(__weiv_wrapCallback(callback), ...args);
        \\  const queueMicrotask = (callback) => globalThis.queueMicrotask(__weiv_wrapCallback(callback));
        \\  const requestAnimationFrame = (callback) => globalThis.requestAnimationFrame(__weiv_wrapCallback(callback));
        \\  const emit = (name, payload) => {
        \\    if (typeof __weiv_handlers[name] === "function") {
        \\      return __weiv_handlers[name](payload);
        \\    }
        \\    return undefined;
        \\  };
        \\
    );

    var lines = std.mem.tokenizeScalar(u8, model.script.transpiled_code, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, &std.ascii.whitespace);
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "import ")) continue;
        if (std.mem.startsWith(u8, line, "export let props")) continue;
        if (std.mem.startsWith(u8, line, "export ")) {
            try out.appendSlice(allocator, "  ");
            try out.appendSlice(allocator, line["export ".len..]);
            try out.appendSlice(allocator, "\n");
            continue;
        }
        try out.appendSlice(allocator, "  ");
        try out.appendSlice(allocator, line);
        try out.appendSlice(allocator, "\n");
    }

    for (model.script.bindings) |binding| {
        if (!binding.callable or !std.mem.eql(u8, binding.kind, "function")) continue;
        if (!isAsyncHelper(model, binding.name)) continue;
        try out.print(
            allocator,
            "  {s} = __weiv_wrapCallback({s});\n",
            .{ binding.name, binding.name },
        );
    }

    for (model.script.imports) |import_record| {
        if (import_record.local_name.len == 0) continue;
        if (std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
        try out.print(allocator, "  const {s} = __weiv_getTrackedRoot(\"{s}\", __weiv_import_{s});\n", .{
            import_record.local_name,
            import_record.local_name,
            import_record.local_name,
        });
    }
    if (model.script.props) |props_record| {
        if (props_record.props_binding_name) |binding_name| {
            try out.print(allocator, "  props = __weiv_getTrackedRoot(\"{s}\", props);\n", .{binding_name});
        }
    }
    for (model.script.bindings) |binding| {
        if (!tracked_roots.isLocalTrackedBinding(model, binding.name)) continue;
        try out.print(allocator, "  {s} = __weiv_getTrackedRoot(\"{s}\", {s});\n", .{
            binding.name,
            binding.name,
            binding.name,
        });
    }

    try out.appendSlice(allocator, "  const __weiv_scope = {};\n");
    try out.appendSlice(allocator, "  function __weiv_refresh() {\n");
    try out.appendSlice(allocator, "    __weiv_scope.props = props;\n");
    try out.appendSlice(allocator, "    __weiv_scope.emit = emit;\n");
    for (model.script.imports) |import_record| {
        if (import_record.local_name.len == 0) continue;
        if (std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
        try out.print(allocator, "    __weiv_scope.{s} = {s};\n", .{ import_record.local_name, import_record.local_name });
    }
    for (model.script.bindings) |binding| {
        if (binding.template_visible and !std.mem.eql(u8, binding.kind, "import")) {
            try out.print(allocator, "    __weiv_scope.{s} = {s};\n", .{ binding.name, binding.name });
        }
    }
    try out.appendSlice(allocator, "    return __weiv_scope;\n");
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  function __weiv_setProps(nextProps) {\n");
    if (model.script.props) |props_record| {
        if (props_record.props_binding_name) |binding_name| {
            try out.print(allocator, "    props = __weiv_getTrackedRoot(\"{s}\", nextProps);\n", .{binding_name});
        } else {
            try out.appendSlice(allocator, "    props = nextProps;\n");
        }
    } else {
        try out.appendSlice(allocator, "    props = nextProps;\n");
    }
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  function __weiv_setEventHandlers(nextHandlers) {\n    __weiv_handlers = nextHandlers;\n  }\n");
    try out.appendSlice(allocator, "  function __weiv_setBoundaryRunner(nextRunner) {\n    __weiv_runBoundary = nextRunner;\n  }\n");
    try out.appendSlice(allocator, "  function __weiv_subscribeImportedObservables(instance) {\n");
    try out.appendSlice(allocator, "    const __weiv_unsubscribes = [];\n");
    try out.appendSlice(allocator, "    const __weiv_seen = new Map();\n");
    try out.appendSlice(allocator, "    const __weiv_register = (bindingName, value) => {\n");
    try out.appendSlice(allocator, "      const __weiv_node = __weiv_getObservableNode(value);\n");
    try out.appendSlice(allocator, "      if (!__weiv_node || !__weiv_node.listeners || typeof __weiv_node.listeners.add !== \"function\") {\n");
    try out.appendSlice(allocator, "        return;\n");
    try out.appendSlice(allocator, "      }\n");
    try out.appendSlice(allocator, "      const __weiv_existingNames = __weiv_seen.get(__weiv_node);\n");
    try out.appendSlice(allocator, "      if (__weiv_existingNames) { __weiv_existingNames.add(bindingName); return; }\n");
    try out.appendSlice(allocator, "      const __weiv_bindingNames = new Set([bindingName]);\n");
    try out.appendSlice(allocator, "      __weiv_seen.set(__weiv_node, __weiv_bindingNames);\n");
    try out.appendSlice(allocator, "      const __weiv_listener = (changedPaths) => {\n");
    try out.appendSlice(allocator, "        if (instance.destroyed) {\n");
    try out.appendSlice(allocator, "          return;\n");
    try out.appendSlice(allocator, "        }\n");
    try out.appendSlice(allocator, "        if (typeof instance.updateDirty === \"function\") {\n");
    try out.appendSlice(allocator, "          const __weiv_preciseNames = changedPaths instanceof Set ? Array.from(__weiv_bindingNames) : [];\n");
    try out.appendSlice(allocator, "          const __weiv_dirtyPaths = new Set();\n");
    try out.appendSlice(allocator, "          if (__weiv_preciseNames.length > 0 && trackedStateGraph && Array.isArray(trackedStateGraph.paths)) {\n");
    try out.appendSlice(allocator, "            for (const __weiv_name of __weiv_preciseNames) {\n");
    try out.appendSlice(allocator, "              for (const __weiv_changedPath of changedPaths) {\n");
    try out.appendSlice(allocator, "                const __weiv_fullPath = `${__weiv_name}.${__weiv_changedPath}`;\n");
    try out.appendSlice(allocator, "                for (const __weiv_record of trackedStateGraph.paths) {\n");
    try out.appendSlice(allocator, "                  if (__weiv_record.path === __weiv_fullPath || __weiv_record.path.startsWith(`${__weiv_fullPath}.`) || __weiv_fullPath.startsWith(`${__weiv_record.path}.`)) __weiv_dirtyPaths.add(__weiv_record.pathId);\n");
    try out.appendSlice(allocator, "                }\n");
    try out.appendSlice(allocator, "              }\n");
    try out.appendSlice(allocator, "            }\n");
    try out.appendSlice(allocator, "          }\n");
    try out.appendSlice(allocator, "          instance.updateDirty({ bindings: Array.from(__weiv_bindingNames), paths: Array.from(__weiv_dirtyPaths), preciseBindings: __weiv_preciseNames }, instance.refresh());\n");
    try out.appendSlice(allocator, "        } else if (typeof instance.update === \"function\") {\n");
    try out.appendSlice(allocator, "          instance.update();\n");
    try out.appendSlice(allocator, "        }\n");
    try out.appendSlice(allocator, "      };\n");
    try out.appendSlice(allocator, "      __weiv_node.listeners.add(__weiv_listener);\n");
    try out.appendSlice(allocator, "      __weiv_unsubscribes.push(() => __weiv_node.listeners.delete(__weiv_listener));\n");
    try out.appendSlice(allocator, "    };\n");
    for (model.script.imports) |import_record| {
        if (import_record.local_name.len == 0) continue;
        if (std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
        try out.print(allocator, "    __weiv_register(\"{s}\", {s});\n", .{ import_record.local_name, import_record.local_name });
    }
    try out.appendSlice(allocator, "    return () => {\n");
    try out.appendSlice(allocator, "      for (const __weiv_unsubscribe of __weiv_unsubscribes) {\n");
    try out.appendSlice(allocator, "        __weiv_unsubscribe();\n");
    try out.appendSlice(allocator, "      }\n");
    try out.appendSlice(allocator, "    };\n");
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  return { scope: __weiv_scope, refresh: __weiv_refresh, setProps: __weiv_setProps, setEventHandlers: __weiv_setEventHandlers, setBoundaryRunner: __weiv_setBoundaryRunner, subscribeImportedObservables: __weiv_subscribeImportedObservables };\n}\n");

    return try out.toOwnedSlice(allocator);
}

fn isAsyncHelper(model: *const component.ComponentUnit, name: []const u8) bool {
    for (model.script.state_facts.helpers) |helper| {
        if (std.mem.eql(u8, helper.name, name)) return helper.async_flag;
    }
    return false;
}

pub fn buildPreservedImports(model: *const component.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (model.script.imports) |record| {
        if (!common.shouldPreserveImport(record, &model.script)) continue;
        if (std.mem.endsWith(u8, record.source, ".weiv")) {
            const spec = try common.emittedDirectImportSpecifier(record.source, allocator);
            defer allocator.free(spec);
            try out.print(allocator, "import * as {s} from \"{s}\";\n", .{ record.local_name, spec });
            continue;
        }
        const spec = try common.emittedRuntimeImportSpecifier(record.source, allocator);
        defer allocator.free(spec);
        if (std.mem.eql(u8, record.kind, "side_effect")) {
            try out.print(allocator, "import \"{s}\";\n", .{spec});
        } else if (std.mem.eql(u8, record.kind, "default")) {
            try out.print(allocator, "import __weiv_import_{s} from \"{s}\";\n", .{ record.local_name, spec });
        } else if (std.mem.eql(u8, record.kind, "namespace")) {
            try out.print(allocator, "import * as __weiv_import_{s} from \"{s}\";\n", .{ record.local_name, spec });
        } else if (std.mem.eql(u8, record.kind, "named")) {
            if (record.imported_name) |imported_name| {
                try out.print(allocator, "import {{ {s} as __weiv_import_{s} }} from \"{s}\";\n", .{ imported_name, record.local_name, spec });
            }
        }
    }

    if (out.items.len > 0) try out.appendSlice(allocator, "\n");
    return try out.toOwnedSlice(allocator);
}
