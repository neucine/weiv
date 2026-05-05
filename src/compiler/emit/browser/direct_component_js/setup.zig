const std = @import("std");
const component = @import("../../../pipeline/index.zig");
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

    try out.appendSlice(allocator, "  const __weiv_scope = {};\n");
    try out.appendSlice(allocator, "  function __weiv_refresh() {\n");
    try out.appendSlice(allocator, "    __weiv_scope.props = props;\n");
    try out.appendSlice(allocator, "    __weiv_scope.emit = emit;\n");
    for (model.script.bindings) |binding| {
        if (binding.template_visible and !std.mem.eql(u8, binding.kind, "import")) {
            try out.writer(allocator).print("    __weiv_scope.{s} = {s};\n", .{ binding.name, binding.name });
        }
    }
    try out.appendSlice(allocator, "    return __weiv_scope;\n");
    try out.appendSlice(allocator, "  }\n");
    try out.appendSlice(allocator, "  function __weiv_setProps(nextProps) {\n    props = nextProps;\n  }\n");
    try out.appendSlice(allocator, "  function __weiv_setEventHandlers(nextHandlers) {\n    __weiv_handlers = nextHandlers;\n  }\n");
    try out.appendSlice(allocator, "  function __weiv_setBoundaryRunner(nextRunner) {\n    __weiv_runBoundary = nextRunner;\n  }\n");
    try out.appendSlice(allocator, "  return { scope: __weiv_scope, refresh: __weiv_refresh, setProps: __weiv_setProps, setEventHandlers: __weiv_setEventHandlers, setBoundaryRunner: __weiv_setBoundaryRunner };\n}\n");

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
            try out.writer(allocator).print("import {s} from \"{s}\";\n", .{ record.local_name, spec });
        } else if (std.mem.eql(u8, record.kind, "namespace")) {
            try out.writer(allocator).print("import * as {s} from \"{s}\";\n", .{ record.local_name, spec });
        } else if (std.mem.eql(u8, record.kind, "named")) {
            if (record.imported_name) |imported_name| {
                if (std.mem.eql(u8, imported_name, record.local_name)) {
                    try out.writer(allocator).print("import {{ {s} }} from \"{s}\";\n", .{ imported_name, spec });
                } else {
                    try out.writer(allocator).print("import {{ {s} as {s} }} from \"{s}\";\n", .{ imported_name, record.local_name, spec });
                }
            }
        }
    }

    if (out.items.len > 0) try out.appendSlice(allocator, "\n");
    return try out.toOwnedSlice(allocator);
}
