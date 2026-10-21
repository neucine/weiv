const std = @import("std");
const sfc = @import("../parser/sfc.zig");
const slot_manifest = @import("slot_manifest.zig");

pub const ScriptFacts = struct {
    ok: bool,
    source_path: []const u8,
    props: ?PropsFacts,
    imports: []ScriptImport,
    bindings: []ScriptBinding,
    state_facts: StateFacts,
    diagnostics: []ScriptDiagnostic,

    pub fn deinit(self: *ScriptFacts, allocator: std.mem.Allocator) void {
        if (self.props) |*props| {
            props.deinit(allocator);
        }
        allocator.free(self.source_path);
        for (self.imports) |*record| record.deinit(allocator);
        allocator.free(self.imports);
        for (self.bindings) |*binding| binding.deinit(allocator);
        allocator.free(self.bindings);
        self.state_facts.deinit(allocator);
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(self.diagnostics);
        self.* = undefined;
    }
};

pub const StateFacts = struct {
    helpers: []HelperFacts,
    mutations: []MutationFacts,
    aliases: []AliasFacts,
    callback_registrations: []CallbackRegistrationFacts,

    fn deinit(self: *StateFacts, allocator: std.mem.Allocator) void {
        for (self.helpers) |*record| record.deinit(allocator);
        allocator.free(self.helpers);
        for (self.mutations) |*record| record.deinit(allocator);
        allocator.free(self.mutations);
        for (self.aliases) |*record| record.deinit(allocator);
        allocator.free(self.aliases);
        for (self.callback_registrations) |*record| record.deinit(allocator);
        allocator.free(self.callback_registrations);
    }
};

pub const PropsFacts = struct {
    has_props_export: bool,
    props_binding_name: ?[]const u8,
    props_type_name: ?[]const u8,

    fn deinit(self: *PropsFacts, allocator: std.mem.Allocator) void {
        if (self.props_binding_name) |value| allocator.free(value);
        if (self.props_type_name) |value| allocator.free(value);
    }
};

pub const ScriptImport = struct {
    source: []const u8,
    kind: []const u8,
    imported_name: ?[]const u8,
    local_name: []const u8,
    span_start: usize,
    span_end: usize,

    fn deinit(self: *ScriptImport, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        allocator.free(self.kind);
        if (self.imported_name) |value| allocator.free(value);
        allocator.free(self.local_name);
    }
};

pub const ScriptBinding = struct {
    name: []const u8,
    kind: []const u8,
    exported: bool,
    template_visible: bool,
    callable: bool,
    type_annotation: ?[]const u8,
    span_start: usize,
    span_end: usize,

    fn deinit(self: *ScriptBinding, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.kind);
        if (self.type_annotation) |value| allocator.free(value);
    }
};

pub const ScriptDiagnostic = struct {
    severity: []const u8,
    message: []const u8,
    span_start: usize,
    span_end: usize,
    line: u32,
    column: u32,
    code: ?[]const u8,

    fn deinit(self: *ScriptDiagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.severity);
        allocator.free(self.message);
        if (self.code) |value| allocator.free(value);
    }
};

pub const HelperFacts = struct {
    name: []const u8,
    kind: []const u8,
    span_start: usize,
    span_end: usize,
    reads: [][]const u8,
    writes: [][]const u8,
    calls: [][]const u8,
    async_flag: bool,
    returns_expression_only: bool,
    contains_external_reads: bool,
    contains_side_effects: bool,

    fn deinit(self: *HelperFacts, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.kind);
        for (self.reads) |value| allocator.free(value);
        allocator.free(self.reads);
        for (self.writes) |value| allocator.free(value);
        allocator.free(self.writes);
        for (self.calls) |value| allocator.free(value);
        allocator.free(self.calls);
    }
};

pub const MutationFacts = struct {
    binding: []const u8,
    kind: []const u8,
    span_start: usize,
    span_end: usize,
    statement_position: bool,
    member_path: ?[]const u8,
    inside_callback: bool,
    callback_owned_candidate: bool,

    fn deinit(self: *MutationFacts, allocator: std.mem.Allocator) void {
        allocator.free(self.binding);
        allocator.free(self.kind);
        if (self.member_path) |value| allocator.free(value);
    }
};

pub const AliasFacts = struct {
    alias: []const u8,
    target: []const u8,
    kind: []const u8,
    span_start: usize,
    span_end: usize,

    fn deinit(self: *AliasFacts, allocator: std.mem.Allocator) void {
        allocator.free(self.alias);
        allocator.free(self.target);
        allocator.free(self.kind);
    }
};

pub const CallbackRegistrationFacts = struct {
    callee: []const u8,
    callback_kind: []const u8,
    callback_span_start: usize,
    callback_span_end: usize,
    owned_candidate: bool,
    reason: []const u8,

    fn deinit(self: *CallbackRegistrationFacts, allocator: std.mem.Allocator) void {
        allocator.free(self.callee);
        allocator.free(self.callback_kind);
        allocator.free(self.reason);
    }
};

pub const TemplateBindings = struct {
    component_refs: []ComponentRef,
    expressions: []ExpressionFacts,
    diagnostics: []TemplateBindingDiagnostic,
    own_slot_manifest: slot_manifest.Manifest,

    pub fn deinit(self: *TemplateBindings, allocator: std.mem.Allocator) void {
        allocator.free(self.component_refs);
        for (self.expressions) |expression| allocator.free(expression.references);
        allocator.free(self.expressions);
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(self.diagnostics);
        self.own_slot_manifest.deinit(allocator);
        self.* = undefined;
    }
};

pub const ExpressionFacts = struct {
    /// Borrows a slice of the normalized template's expression source.
    source: []const u8,
    references: []ExpressionReference,
};

pub const ExpressionReference = struct {
    /// Borrows a slice of ExpressionFacts.source.
    name: []const u8,
    call: bool,
};

pub const ComponentRef = struct {
    tag_name: []const u8,
    resolved: bool,
    span: sfc.Span,
};

pub const TemplateBindingDiagnostic = struct {
    severity: []const u8,
    kind: []const u8,
    name: []const u8,
    message: []const u8,
    span: sfc.Span,

    fn deinit(self: *TemplateBindingDiagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.severity);
        allocator.free(self.kind);
        allocator.free(self.name);
        allocator.free(self.message);
    }
};
