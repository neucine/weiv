const std = @import("std");
const binding = @import("../analyze/binder.zig");
const ir = @import("../lower/ir.zig");
const sfc = @import("../parse/sfc.zig");
const template = @import("../parse/template.zig");
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
