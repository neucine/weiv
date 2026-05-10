const std = @import("std");
const binding = @import("../analyze/binder.zig");
const compiler_diagnostics = @import("../diagnostics.zig");
const ir = @import("../lower/ir.zig");
const sfc = @import("../parse/sfc.zig");
const template = @import("../parse/template/index.zig");
const script_analysis = @import("../analyze/ts/analysis.zig");

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

pub const ComponentBuildReport = struct {
    source_path: []const u8,
    diagnostics: []compiler_diagnostics.Diagnostic,
    sfc_document: ?sfc.Document,
    template_document: ?template.Document,
    normalized_template: ?template.NormalizedDocument,
    script: ?script_analysis.ScriptAnalysis,
    binding_result: ?binding.BindingResult,
    ir_document: ?ir.Document,
    halted_after: ?compiler_diagnostics.Stage,

    pub fn deinit(self: *ComponentBuildReport, allocator: std.mem.Allocator) void {
        if (self.source_path.len != 0) allocator.free(self.source_path);
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        if (self.diagnostics.len != 0) allocator.free(self.diagnostics);
        if (self.ir_document) |*ir_document| ir_document.deinit(allocator);
        if (self.binding_result) |*binding_result| binding_result.deinit(allocator);
        if (self.normalized_template) |*normalized_template| normalized_template.deinit(allocator);
        if (self.template_document) |*template_document| template_document.deinit(allocator);
        if (self.script) |*script| script.deinit(allocator);
        self.* = undefined;
    }

    pub fn intoComponentModel(self: *ComponentBuildReport) !ComponentModel {
        if (self.sfc_document == null or
            self.template_document == null or
            self.normalized_template == null or
            self.script == null or
            self.binding_result == null or
            self.ir_document == null)
        {
            return error.IncompleteBuildReport;
        }

        const result = ComponentModel{
            .source_path = self.source_path,
            .sfc_document = self.sfc_document.?,
            .template_document = self.template_document.?,
            .normalized_template = self.normalized_template.?,
            .script = self.script.?,
            .binding_result = self.binding_result.?,
            .ir_document = self.ir_document.?,
        };

        return result;
    }
};
