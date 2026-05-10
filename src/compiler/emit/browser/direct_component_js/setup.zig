const std = @import("std");
const component = @import("../../../pipeline/index.zig");
const tracked_root = @import("../../../analyze/tracked_root.zig");
const common = @import("common.zig");

pub fn buildSetupCode(model: *const component.ComponentModel, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);

    try out.appendSlice(allocator,
        \\function setup(__weiv_props, __weiv_event_handlers = {}) {
        \\  let props = __weiv_props;
        \\  let __weiv_handlers = __weiv_event_handlers;
        \\  let __weiv_runBoundary = (callback) => callback();
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

    for (model.script.imports) |import_record| {
        if (import_record.local_name.len == 0) continue;
        if (std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
        try out.writer(allocator).print("  const {s} = __weiv_getTrackedRoot(\"{s}\", __weiv_import_{s});\n", .{
            import_record.local_name,
            import_record.local_name,
            import_record.local_name,
        });
    }
    if (model.script.props) |props_record| {
        if (props_record.props_binding_name) |binding_name| {
            try out.writer(allocator).print("  props = __weiv_getTrackedRoot(\"{s}\", props);\n", .{binding_name});
        }
    }
    for (model.script.bindings) |binding| {
        if (!tracked_root.isLocalTrackedBinding(model, binding.name)) continue;
        try out.writer(allocator).print("  {s} = __weiv_getTrackedRoot(\"{s}\", {s});\n", .{
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
        try out.writer(allocator).print("    __weiv_scope.{s} = {s};\n", .{ import_record.local_name, import_record.local_name });
    }
    for (model.script.bindings) |binding| {
        if (binding.template_visible and !std.mem.eql(u8, binding.kind, "import")) {
            try out.writer(allocator).print("    __weiv_scope.{s} = {s};\n", .{ binding.name, binding.name });
        }
    }
    try out.appendSlice(allocator, "    return __weiv_scope;\n");
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  function __weiv_setProps(nextProps) {\n");
    if (model.script.props) |props_record| {
        if (props_record.props_binding_name) |binding_name| {
            try out.writer(allocator).print("    props = __weiv_getTrackedRoot(\"{s}\", nextProps);\n", .{binding_name});
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
    try out.appendSlice(allocator, "    const __weiv_seen = new Set();\n");
    try out.appendSlice(allocator, "    const __weiv_register = (value) => {\n");
    try out.appendSlice(allocator, "      const __weiv_node = __weiv_getObservableNode(value);\n");
    try out.appendSlice(allocator, "      if (!__weiv_node || __weiv_seen.has(__weiv_node) || !__weiv_node.listeners || typeof __weiv_node.listeners.add !== \"function\") {\n");
    try out.appendSlice(allocator, "        return;\n");
    try out.appendSlice(allocator, "      }\n");
    try out.appendSlice(allocator, "      __weiv_seen.add(__weiv_node);\n");
    try out.appendSlice(allocator, "      const __weiv_listener = () => {\n");
    try out.appendSlice(allocator, "        if (instance.destroyed) {\n");
    try out.appendSlice(allocator, "          return;\n");
    try out.appendSlice(allocator, "        }\n");
    try out.appendSlice(allocator, "        if (typeof instance.update === \"function\") {\n");
    try out.appendSlice(allocator, "          instance.update();\n");
    try out.appendSlice(allocator, "        }\n");
    try out.appendSlice(allocator, "      };\n");
    try out.appendSlice(allocator, "      __weiv_node.listeners.add(__weiv_listener);\n");
    try out.appendSlice(allocator, "      __weiv_unsubscribes.push(() => __weiv_node.listeners.delete(__weiv_listener));\n");
    try out.appendSlice(allocator, "    };\n");
    for (model.script.imports) |import_record| {
        if (import_record.local_name.len == 0) continue;
        if (std.mem.endsWith(u8, import_record.source, ".weiv")) continue;
        try out.writer(allocator).print("    __weiv_register({s});\n", .{import_record.local_name});
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

pub fn buildPreservedImports(model: *const component.ComponentModel, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);

    for (model.script.imports) |record| {
        if (!common.shouldPreserveImport(record, &model.script)) continue;
        if (std.mem.endsWith(u8, record.source, ".weiv")) {
            const spec = try common.emittedDirectImportSpecifier(record.source, allocator);
            defer allocator.free(spec);
            try out.writer(allocator).print("import * as {s} from \"{s}\";\n", .{ record.local_name, spec });
            continue;
        }
        const spec = try common.emittedRuntimeImportSpecifier(record.source, allocator);
        defer allocator.free(spec);
        if (std.mem.eql(u8, record.kind, "side_effect")) {
            try out.writer(allocator).print("import \"{s}\";\n", .{spec});
        } else if (std.mem.eql(u8, record.kind, "default")) {
            try out.writer(allocator).print("import __weiv_import_{s} from \"{s}\";\n", .{ record.local_name, spec });
        } else if (std.mem.eql(u8, record.kind, "namespace")) {
            try out.writer(allocator).print("import * as __weiv_import_{s} from \"{s}\";\n", .{ record.local_name, spec });
        } else if (std.mem.eql(u8, record.kind, "named")) {
            if (record.imported_name) |imported_name| {
                try out.writer(allocator).print("import {{ {s} as __weiv_import_{s} }} from \"{s}\";\n", .{ imported_name, record.local_name, spec });
            }
        }
    }

    if (out.items.len > 0) try out.appendSlice(allocator, "\n");
    return try out.toOwnedSlice(allocator);
}
