const std = @import("std");

pub const ScriptAnalysis = struct {
    ok: bool,
    source_path: []const u8,
    transpiled_code: []const u8,
    props: ?PropsRecord,
    imports: []ImportRecord,
    bindings: []BindingRecord,
    diagnostics: []DiagnosticRecord,

    pub fn deinit(self: *ScriptAnalysis, allocator: std.mem.Allocator) void {
        if (self.props) |*props| {
            props.deinit(allocator);
        }
        allocator.free(self.source_path);
        allocator.free(self.transpiled_code);
        for (self.imports) |*record| record.deinit(allocator);
        allocator.free(self.imports);
        for (self.bindings) |*binding| binding.deinit(allocator);
        allocator.free(self.bindings);
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(self.diagnostics);
        self.* = undefined;
    }
};

pub const PropsRecord = struct {
    has_props_export: bool,
    props_binding_name: ?[]const u8,
    props_type_name: ?[]const u8,

    fn deinit(self: *PropsRecord, allocator: std.mem.Allocator) void {
        if (self.props_binding_name) |value| allocator.free(value);
        if (self.props_type_name) |value| allocator.free(value);
    }
};

pub const ImportRecord = struct {
    source: []const u8,
    kind: []const u8,
    imported_name: ?[]const u8,
    local_name: []const u8,
    span_start: usize,
    span_end: usize,

    fn deinit(self: *ImportRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        allocator.free(self.kind);
        if (self.imported_name) |value| allocator.free(value);
        allocator.free(self.local_name);
    }
};

pub const BindingRecord = struct {
    name: []const u8,
    kind: []const u8,
    exported: bool,
    template_visible: bool,
    callable: bool,
    type_annotation: ?[]const u8,
    span_start: usize,
    span_end: usize,

    fn deinit(self: *BindingRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.kind);
        if (self.type_annotation) |value| allocator.free(value);
    }
};

pub const DiagnosticRecord = struct {
    severity: []const u8,
    message: []const u8,
    span_start: usize,
    span_end: usize,
    line: u32,
    column: u32,
    code: ?[]const u8,

    fn deinit(self: *DiagnosticRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.severity);
        allocator.free(self.message);
        if (self.code) |value| allocator.free(value);
    }
};

const JsonScriptAnalysis = struct {
    ok: bool,
    source_path: []const u8,
    transpiled_code: []const u8,
    props: ?JsonPropsRecord,
    imports: []JsonImportRecord,
    bindings: []JsonBindingRecord,
    diagnostics: []JsonDiagnosticRecord,
};

const JsonPropsRecord = struct {
    has_props_export: bool,
    props_binding_name: ?[]const u8,
    props_type_name: ?[]const u8,
};

const JsonImportRecord = struct {
    source: []const u8,
    kind: []const u8,
    imported_name: ?[]const u8,
    local_name: []const u8,
    span_start: usize,
    span_end: usize,
};

const JsonBindingRecord = struct {
    name: []const u8,
    kind: []const u8,
    exported: bool,
    template_visible: bool,
    callable: bool,
    type_annotation: ?[]const u8,
    span_start: usize,
    span_end: usize,
};

const JsonDiagnosticRecord = struct {
    severity: []const u8,
    message: []const u8,
    span_start: usize,
    span_end: usize,
    line: u32,
    column: u32,
    code: ?[]const u8,
};

pub fn parseFromJson(json_source: []const u8, allocator: std.mem.Allocator) !ScriptAnalysis {
    const parsed = try std.json.parseFromSlice(JsonScriptAnalysis, allocator, json_source, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    var imports = try allocator.alloc(ImportRecord, parsed.value.imports.len);
    errdefer allocator.free(imports);
    for (parsed.value.imports, 0..) |record, idx| {
        imports[idx] = .{
            .source = try allocator.dupe(u8, record.source),
            .kind = try allocator.dupe(u8, record.kind),
            .imported_name = if (record.imported_name) |value| try allocator.dupe(u8, value) else null,
            .local_name = try allocator.dupe(u8, record.local_name),
            .span_start = record.span_start,
            .span_end = record.span_end,
        };
    }

    var bindings = try allocator.alloc(BindingRecord, parsed.value.bindings.len);
    errdefer allocator.free(bindings);
    for (parsed.value.bindings, 0..) |record, idx| {
        bindings[idx] = .{
            .name = try allocator.dupe(u8, record.name),
            .kind = try allocator.dupe(u8, record.kind),
            .exported = record.exported,
            .template_visible = record.template_visible,
            .callable = record.callable,
            .type_annotation = if (record.type_annotation) |value| try allocator.dupe(u8, value) else null,
            .span_start = record.span_start,
            .span_end = record.span_end,
        };
    }

    var diagnostics = try allocator.alloc(DiagnosticRecord, parsed.value.diagnostics.len);
    errdefer allocator.free(diagnostics);
    for (parsed.value.diagnostics, 0..) |record, idx| {
        diagnostics[idx] = .{
            .severity = try allocator.dupe(u8, record.severity),
            .message = try allocator.dupe(u8, record.message),
            .span_start = record.span_start,
            .span_end = record.span_end,
            .line = record.line,
            .column = record.column,
            .code = if (record.code) |value| try allocator.dupe(u8, value) else null,
        };
    }

    return .{
        .ok = parsed.value.ok,
        .source_path = try allocator.dupe(u8, parsed.value.source_path),
        .transpiled_code = try allocator.dupe(u8, parsed.value.transpiled_code),
        .props = if (parsed.value.props) |props| .{
            .has_props_export = props.has_props_export,
            .props_binding_name = if (props.props_binding_name) |value| try allocator.dupe(u8, value) else null,
            .props_type_name = if (props.props_type_name) |value| try allocator.dupe(u8, value) else null,
        } else null,
        .imports = imports,
        .bindings = bindings,
        .diagnostics = diagnostics,
    };
}
