const std = @import("std");
const binding = @import("../analyze/binder.zig");
const compiler_diagnostics = @import("../diagnostics.zig");
const lower_ir = @import("../lower/lower.zig");
const model = @import("model.zig");
const sfc = @import("../parse/sfc.zig");
const template = @import("../parse/template/index.zig");
const parser_backend = @import("../../ffi/parser_backend.zig");

pub fn build(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) !model.ComponentModel {
    const sfc_document = try sfc.parse(source);
    const template_document = try template.parse(sfc_document.template.content, allocator);
    errdefer {
        var temp = template_document;
        temp.deinit(allocator);
    }

    const normalized_template = try template.normalize(&template_document, allocator);
    errdefer {
        var temp = normalized_template;
        temp.deinit(allocator);
    }

    const script = try parser_backend.analyzeScript(sfc_document.script.content, source_path, allocator);
    errdefer {
        var temp = script;
        temp.deinit(allocator);
    }

    const binding_result = try binding.bind(&normalized_template, &script, source_path, allocator);
    errdefer {
        var temp = binding_result;
        temp.deinit(allocator);
    }

    const ir_document = try lower_ir.lower(&normalized_template, &binding_result, allocator);
    errdefer {
        var temp = ir_document;
        temp.deinit(allocator);
    }

    return .{
        .source_path = try allocator.dupe(u8, source_path),
        .sfc_document = sfc_document,
        .template_document = template_document,
        .normalized_template = normalized_template,
        .script = script,
        .binding_result = binding_result,
        .ir_document = ir_document,
    };
}

pub fn buildReport(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) !model.ComponentBuildReport {
    var bag = compiler_diagnostics.DiagnosticBag.init();
    defer bag.deinit(allocator);

    var report = model.ComponentBuildReport{
        .source_path = try allocator.dupe(u8, source_path),
        .diagnostics = &.{},
        .sfc_document = null,
        .template_document = null,
        .normalized_template = null,
        .script = null,
        .binding_result = null,
        .ir_document = null,
        .halted_after = null,
    };
    errdefer report.deinit(allocator);

    const sfc_document = sfc.parse(source) catch |err| {
        try appendSfcDiagnostic(&bag, source_path, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .sfc_parse;
        return report;
    };
    report.sfc_document = sfc_document;

    var template_document = template.parse(sfc_document.template.content, allocator) catch |err| {
        try appendTemplateParseDiagnostic(&bag, source, source_path, sfc_document, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .template_parse;
        return report;
    };
    report.template_document = template_document;

    var normalized_template = template.normalize(&template_document, allocator) catch |err| {
        try appendTemplateNormalizeDiagnostic(&bag, source, source_path, sfc_document, template_document, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .template_normalize;
        return report;
    };
    report.normalized_template = normalized_template;

    var script = try parser_backend.analyzeScript(sfc_document.script.content, source_path, allocator);
    try appendScriptDiagnostics(&bag, source, source_path, sfc_document, &script, allocator);
    report.script = script;

    var binding_result = try binding.bind(&normalized_template, &script, source_path, allocator);
    try appendBindingDiagnostics(&bag, source, source_path, &binding_result, allocator);
    report.binding_result = binding_result;

    const ir_document = lower_ir.lower(&normalized_template, &binding_result, allocator) catch |err| {
        try appendLoweringDiagnostic(&bag, source, source_path, sfc_document, normalized_template, err, allocator);
        report.diagnostics = try bag.toOwnedSlice(allocator);
        report.halted_after = .lowering;
        return report;
    };
    report.ir_document = ir_document;

    report.diagnostics = try bag.toOwnedSlice(allocator);
    return report;
}

fn appendSfcDiagnostic(
    bag: *compiler_diagnostics.DiagnosticBag,
    source_path: []const u8,
    err: anyerror,
    allocator: std.mem.Allocator,
) !void {
    const entry = switch (err) {
        error.MissingTemplate => .{ "sfc.missing_template", "Missing <template> section" },
        error.MissingScript => .{ "sfc.missing_script", "Missing <script lang=\"ts\"> section" },
        error.DuplicateTemplate => .{ "sfc.duplicate_template", "Duplicate <template> section" },
        error.DuplicateScript => .{ "sfc.duplicate_script", "Duplicate <script> section" },
        error.DuplicateStyle => .{ "sfc.duplicate_style", "Duplicate <style> section" },
        error.UnknownTopLevelSection => .{ "sfc.unknown_top_level_section", "Unknown top-level section; only template, script, and style are supported" },
        error.InvalidScriptAttributes => .{ "sfc.invalid_script_attributes", "Only <script lang=\"ts\"> is supported" },
        error.InvalidSectionOrder => .{ "sfc.invalid_section_order", "Sections must appear in template, script, style order" },
        error.UnterminatedOpenTag => .{ "sfc.unterminated_open_tag", "Unterminated top-level open tag" },
        error.UnterminatedCloseTag => .{ "sfc.unterminated_close_tag", "Unterminated top-level close tag" },
        else => return err,
    };
    try bag.appendOwned(allocator, entry[0], .@"error", entry[1], .sfc_parse, source_path, null, null, true);
}

fn appendTemplateParseDiagnostic(
    bag: *compiler_diagnostics.DiagnosticBag,
    source: []const u8,
    source_path: []const u8,
    sfc_document: sfc.Document,
    err: anyerror,
    allocator: std.mem.Allocator,
) !void {
    const entry = switch (err) {
        error.UnterminatedTag => .{ "template.unterminated_tag", "Unterminated template tag" },
        error.UnexpectedCloseTag => .{ "template.unexpected_close_tag", "Closing tag appeared without a matching open tag" },
        error.MismatchedCloseTag => .{ "template.mismatched_close_tag", "Closing tag does not match the currently open element" },
        error.InvalidSlotOutlet => .{ "template.invalid_slot_outlet", "<slot> only supports an optional name attribute and no directives" },
        error.InvalidDirective => .{ "template.invalid_directive", "Invalid template directive usage" },
        error.UnterminatedInterpolation => .{ "template.unterminated_interpolation", "Unterminated interpolation" },
        else => return err,
    };
    const absolute_span = sfc.Span{
        .start = sfc_document.template.content_span.start,
        .end = sfc_document.template.content_span.start + 1,
    };
    try bag.appendOwned(
        allocator,
        entry[0],
        .@"error",
        entry[1],
        .template_parse,
        source_path,
        .{ .start = absolute_span.start, .end = absolute_span.end },
        compiler_diagnostics.computeLocation(source, .{ .start = absolute_span.start, .end = absolute_span.end }),
        true,
    );
}

fn appendTemplateNormalizeDiagnostic(
    bag: *compiler_diagnostics.DiagnosticBag,
    source: []const u8,
    source_path: []const u8,
    sfc_document: sfc.Document,
    template_document: template.Document,
    err: anyerror,
    allocator: std.mem.Allocator,
) !void {
    const entry = switch (err) {
        error.UnexpectedElse => .{ "template.unexpected_else", "`else` must immediately follow a sibling element with `if`" },
        else => return err,
    };

    const relative_span = template.debug.findFirstInvalidNormalizeSpan(template_document.nodes, err) orelse sfc.Span{ .start = 0, .end = 1 };

    const absolute_span = compiler_diagnostics.Span{
        .start = sfc_document.template.content_span.start + relative_span.start,
        .end = sfc_document.template.content_span.start + relative_span.end,
    };

    try bag.appendOwned(
        allocator,
        entry[0],
        .@"error",
        entry[1],
        .template_normalize,
        source_path,
        absolute_span,
        compiler_diagnostics.computeLocation(source, absolute_span),
        true,
    );
}

fn appendLoweringDiagnostic(
    bag: *compiler_diagnostics.DiagnosticBag,
    source: []const u8,
    source_path: []const u8,
    sfc_document: sfc.Document,
    normalized_template: template.NormalizedDocument,
    err: anyerror,
    allocator: std.mem.Allocator,
) !void {
    const entry = switch (err) {
        error.InvalidSlotPlacement => .{ "template.invalid_slot_placement", "`slot:name` may only be used on direct children of a component usage" },
        error.InvalidSlotTemplatePlacement => .{ "template.invalid_slot_template_placement", "<template> grouping is only valid inside a component usage when paired with slot:name" },
        else => return err,
    };

    const relative_span = template.debug.findFirstInvalidLoweringSpan(normalized_template.nodes, err) orelse sfc.Span{ .start = 0, .end = 1 };
    const absolute_span = compiler_diagnostics.Span{
        .start = sfc_document.template.content_span.start + relative_span.start,
        .end = sfc_document.template.content_span.start + relative_span.end,
    };

    try bag.appendOwned(
        allocator,
        entry[0],
        .@"error",
        entry[1],
        .lowering,
        source_path,
        absolute_span,
        compiler_diagnostics.computeLocation(source, absolute_span),
        true,
    );
}

fn appendScriptDiagnostics(
    bag: *compiler_diagnostics.DiagnosticBag,
    source: []const u8,
    source_path: []const u8,
    sfc_document: sfc.Document,
    script: *const @import("../analyze/ts/analysis.zig").ScriptAnalysis,
    allocator: std.mem.Allocator,
) !void {
    for (script.diagnostics) |diagnostic| {
        const absolute_span = compiler_diagnostics.Span{
            .start = sfc_document.script.content_span.start + diagnostic.span_start,
            .end = sfc_document.script.content_span.start + diagnostic.span_end,
        };
        try bag.appendOwned(
            allocator,
            diagnostic.code orelse "script.analysis",
            compiler_diagnostics.severityFromString(diagnostic.severity),
            diagnostic.message,
            .script_analysis,
            source_path,
            absolute_span,
            compiler_diagnostics.computeLocation(source, absolute_span),
            false,
        );
    }
}

fn appendBindingDiagnostics(
    bag: *compiler_diagnostics.DiagnosticBag,
    source: []const u8,
    source_path: []const u8,
    binding_result: *const binding.BindingResult,
    allocator: std.mem.Allocator,
) !void {
    for (binding_result.diagnostics) |diagnostic| {
        const span = compiler_diagnostics.Span{
            .start = diagnostic.span.start,
            .end = diagnostic.span.end,
        };
        try bag.appendOwned(
            allocator,
            diagnostic.kind,
            compiler_diagnostics.severityFromString(diagnostic.severity),
            diagnostic.message,
            .binding,
            source_path,
            span,
            compiler_diagnostics.computeLocation(source, span),
            false,
        );
    }
}
