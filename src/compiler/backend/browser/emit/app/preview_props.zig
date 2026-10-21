const std = @import("std");
const component = @import("../../../../component_unit.zig");

pub fn inferLiteral(model: *const component.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    const props_record = model.script.props orelse return allocator.dupe(u8, "{}");
    const type_name = props_record.props_type_name orelse return allocator.dupe(u8, "{}");
    const body = findInterfaceBody(model.sfc_document.script.content, type_name) orelse return allocator.dupe(u8, "{}");
    return buildPreviewPropsObject(body, allocator);
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
    var properties = std.ArrayList(PropertyDefault).empty;
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
        const name = std.mem.trimEnd(u8, name_raw, "?");
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

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, "{ ");
    for (properties.items, 0..) |property, idx| {
        try out.print(allocator, "{s}: {s}", .{ property.name, property.value });
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
