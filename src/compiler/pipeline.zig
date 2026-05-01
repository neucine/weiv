const std = @import("std");
const binding = @import("analyze/binder.zig");
const ir = @import("lower/ir.zig");
const lower_ir = @import("lower/lower.zig");
const sfc = @import("parse/sfc.zig");
const template = @import("parse/template.zig");
const script_analysis = @import("analyze/ts/analysis.zig");
const parser_backend = @import("../ffi/parser_backend.zig");

pub const ComponentModel = struct {
    source_path: []const u8,
    sfc_document: sfc.Document,
    template_document: template.Document,
    normalized_template: template.NormalizedDocument,
    script: script_analysis.ScriptAnalysis,
    binding_result: binding.BindingResult,
    ir_document: ir.Document,

    pub fn deinit(self: *ComponentModel, allocator: std.mem.Allocator) void {
        allocator.free(self.source_path);
        self.ir_document.deinit(allocator);
        self.binding_result.deinit(allocator);
        self.normalized_template.deinit(allocator);
        self.template_document.deinit(allocator);
        self.script.deinit(allocator);
        self.* = undefined;
    }
};

pub fn build(
    source: []const u8,
    source_path: []const u8,
    allocator: std.mem.Allocator,
) !ComponentModel {
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
    const binding_result = try binding.bind(&normalized_template, &script, allocator);
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
