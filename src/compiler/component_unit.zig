const std = @import("std");
const compiler_diagnostics = @import("diagnostics.zig");
const lir = @import("lower/lir.zig");
const parser = @import("parser/index.zig");
const sir = @import("sema/sir.zig");

const sfc = parser.sfc;
const template = parser.template;

pub const ComponentUnit = struct {
    source_path: []const u8,
    source: []const u8,
    sfc_document: sfc.Document,
    template_document: template.Document,
    normalized_template: template.NormalizedDocument,
    script: sir.ScriptFacts,
    script_js: []const u8,
    template_bindings: sir.TemplateBindings,
    lir_document: lir.Document,

    pub fn deinit(self: *ComponentUnit, allocator: std.mem.Allocator) void {
        allocator.free(self.source_path);
        self.lir_document.deinit(allocator);
        self.template_bindings.deinit(allocator);
        self.normalized_template.deinit(allocator);
        self.template_document.deinit(allocator);
        self.script.deinit(allocator);
        allocator.free(self.script_js);
        allocator.free(self.source);
        self.* = undefined;
    }
};

pub const ComponentCompileReport = struct {
    source_path: []const u8,
    source: ?[]const u8,
    diagnostics: []compiler_diagnostics.Diagnostic,
    sfc_document: ?sfc.Document,
    template_document: ?template.Document,
    normalized_template: ?template.NormalizedDocument,
    script: ?sir.ScriptFacts,
    script_js: ?[]const u8,
    template_bindings: ?sir.TemplateBindings,
    lir_document: ?lir.Document,
    halted_after: ?compiler_diagnostics.Stage,
    halt_error: ?anyerror,

    pub fn deinit(self: *ComponentCompileReport, allocator: std.mem.Allocator) void {
        if (self.source_path.len != 0) allocator.free(self.source_path);
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        if (self.diagnostics.len != 0) allocator.free(self.diagnostics);
        if (self.lir_document) |*lir_document| lir_document.deinit(allocator);
        if (self.template_bindings) |*template_bindings| template_bindings.deinit(allocator);
        if (self.normalized_template) |*normalized_template| normalized_template.deinit(allocator);
        if (self.template_document) |*template_document| template_document.deinit(allocator);
        if (self.script) |*script| script.deinit(allocator);
        if (self.script_js) |script_js| allocator.free(script_js);
        if (self.source) |source| allocator.free(source);
        self.* = undefined;
    }

    pub fn takeUnit(self: *ComponentCompileReport, allocator: std.mem.Allocator) !ComponentUnit {
        if (self.sfc_document == null or
            self.source == null or
            self.template_document == null or
            self.normalized_template == null or
            self.script == null or
            self.script_js == null or
            self.template_bindings == null or
            self.lir_document == null)
        {
            return error.IncompleteCompileReport;
        }

        const result = ComponentUnit{
            .source_path = self.source_path,
            .source = self.source.?,
            .sfc_document = self.sfc_document.?,
            .template_document = self.template_document.?,
            .normalized_template = self.normalized_template.?,
            .script = self.script.?,
            .script_js = self.script_js.?,
            .template_bindings = self.template_bindings.?,
            .lir_document = self.lir_document.?,
        };

        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        if (self.diagnostics.len != 0) allocator.free(self.diagnostics);
        self.diagnostics = &.{};
        self.source_path = &.{};
        self.source = null;
        self.sfc_document = null;
        self.template_document = null;
        self.normalized_template = null;
        self.script = null;
        self.script_js = null;
        self.template_bindings = null;
        self.lir_document = null;
        self.halted_after = null;
        self.halt_error = null;

        return result;
    }
};
