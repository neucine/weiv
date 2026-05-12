const std = @import("std");
const script_analysis = @import("../compiler/analyze/ts/analysis.zig");

const backend = struct {
    extern fn weiv_script_analyze(source: [*:0]const u8, source_path: [*:0]const u8) ?[*:0]u8;
    extern fn weiv_transpile_module(source: [*:0]const u8, source_path: [*:0]const u8) ?[*:0]u8;
    extern fn weiv_rewrite_expression(expression: [*:0]const u8, scope_bindings_json: [*:0]const u8, scope_prefix: [*:0]const u8) ?[*:0]u8;
    extern fn weiv_backend_free(ptr: [*:0]u8) void;
};

pub fn analyzeScriptRaw(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);

    const path_z = try allocator.dupeZ(u8, source_path);
    defer allocator.free(path_z);

    const result_ptr = backend.weiv_script_analyze(source_z.ptr, path_z.ptr) orelse return error.BackendFailure;
    defer backend.weiv_backend_free(result_ptr);

    const json = std.mem.span(result_ptr);
    return try allocator.dupe(u8, json);
}

pub fn analyzeScript(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) !script_analysis.ScriptAnalysis {
    const json = try analyzeScriptRaw(source, source_path, allocator);
    defer allocator.free(json);
    return try script_analysis.parseFromJson(json, allocator);
}

pub fn rewriteExpression(
    expression: []const u8,
    scope_bindings_json: []const u8,
    scope_prefix: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    const expr_z = try allocator.dupeZ(u8, expression);
    defer allocator.free(expr_z);

    const bindings_z = try allocator.dupeZ(u8, scope_bindings_json);
    defer allocator.free(bindings_z);

    const prefix_z = try allocator.dupeZ(u8, scope_prefix);
    defer allocator.free(prefix_z);

    const result_ptr = backend.weiv_rewrite_expression(expr_z.ptr, bindings_z.ptr, prefix_z.ptr) orelse return error.ExpressionRewriteFailed;
    defer backend.weiv_backend_free(result_ptr);

    const result = std.mem.span(result_ptr);
    return try allocator.dupe(u8, result);
}

pub fn transpileModule(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    const source_z = try allocator.dupeZ(u8, source);
    defer allocator.free(source_z);

    const path_z = try allocator.dupeZ(u8, source_path);
    defer allocator.free(path_z);

    const result_ptr = backend.weiv_transpile_module(source_z.ptr, path_z.ptr) orelse return error.BackendFailure;
    defer backend.weiv_backend_free(result_ptr);

    const js = std.mem.span(result_ptr);
    return try allocator.dupe(u8, js);
}
