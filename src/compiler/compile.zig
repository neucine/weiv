const std = @import("std");
const compiler_diagnostics = @import("diagnostics.zig");
const binding = @import("sema/binder.zig");
const lower = @import("lower/index.zig");
const component_unit = @import("component_unit.zig");
const parser = @import("parser/index.zig");
const parser_backend = @import("../ffi/parser_backend.zig");

pub fn compile(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) !component_unit.ComponentUnit {
    const sfc_document = try parser.parseSfc(source);
    const template_document = try parser.parseTemplate(sfc_document.template.content, allocator);
    errdefer {
        var temp = template_document;
        temp.deinit(allocator);
    }

    const normalized_template = try parser.normalizeTemplate(&template_document, allocator);
    errdefer {
        var temp = normalized_template;
        temp.deinit(allocator);
    }

    const script = try parser_backend.analyzeScript(sfc_document.script.content, source_path, allocator);
    errdefer {
        var temp = script;
        temp.deinit(allocator);
    }

    const template_bindings = try binding.bind(&normalized_template, &script, source_path, allocator);
    errdefer {
        var temp = template_bindings;
        temp.deinit(allocator);
    }

    const lir_document = try lower.lower(&normalized_template, &template_bindings, allocator);
    errdefer {
        var temp = lir_document;
        temp.deinit(allocator);
    }

    return .{
        .source_path = try allocator.dupe(u8, source_path),
        .sfc_document = sfc_document,
        .template_document = template_document,
        .normalized_template = normalized_template,
        .script = script,
        .template_bindings = template_bindings,
        .lir_document = lir_document,
    };
}

pub fn compileReport(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) !component_unit.ComponentCompileReport {
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);

    var report = component_unit.ComponentCompileReport{
        .source_path = try allocator.dupe(u8, source_path),
        .diagnostics = &.{},
        .sfc_document = null,
        .template_document = null,
        .normalized_template = null,
        .script = null,
        .template_bindings = null,
        .lir_document = null,
        .halted_after = null,
    };
    errdefer report.deinit(allocator);

    const sfc_document = parser.parseSfc(source) catch |err| {
        try compiler_diagnostics.appendSfcDiagnostic(&bag, source_path, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .sfc_parse;
        return report;
    };
    report.sfc_document = sfc_document;

    var template_document = parser.parseTemplate(sfc_document.template.content, allocator) catch |err| {
        try compiler_diagnostics.appendTemplateParseDiagnostic(&bag, source, source_path, sfc_document, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .template_parse;
        return report;
    };
    report.template_document = template_document;

    var normalized_template = parser.normalizeTemplate(&template_document, allocator) catch |err| {
        try compiler_diagnostics.appendTemplateNormalizeDiagnostic(&bag, source, source_path, sfc_document, template_document, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .template_normalize;
        return report;
    };
    report.normalized_template = normalized_template;

    var script = try parser_backend.analyzeScript(sfc_document.script.content, source_path, allocator);
    try compiler_diagnostics.appendScriptDiagnostics(&bag, source, source_path, sfc_document, &script, allocator);
    report.script = script;

    var template_bindings = try binding.bind(&normalized_template, &script, source_path, allocator);
    try compiler_diagnostics.appendBindingDiagnostics(&bag, source, source_path, &template_bindings, allocator);
    report.template_bindings = template_bindings;

    const lir_document = lower.lower(&normalized_template, &template_bindings, allocator) catch |err| {
        try compiler_diagnostics.appendLoweringDiagnostic(&bag, source, source_path, sfc_document, normalized_template, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .lowering;
        return report;
    };
    report.lir_document = lir_document;

    report.diagnostics = try bag.toOwnedSlice(allocator);
    return report;
}
