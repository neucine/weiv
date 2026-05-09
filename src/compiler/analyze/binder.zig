const std = @import("std");
const template = @import("../parse/template/index.zig");
const script_analysis = @import("ts/analysis.zig");
const sfc = @import("../parse/sfc.zig");
const slot_manifest = @import("slot_manifest.zig");

pub const BindingResult = struct {
    component_refs: []ComponentRef,
    diagnostics: []Diagnostic,
    own_slot_manifest: slot_manifest.Manifest,

    pub fn deinit(self: *BindingResult, allocator: std.mem.Allocator) void {
        allocator.free(self.component_refs);
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(self.diagnostics);
        self.own_slot_manifest.deinit(allocator);
        self.* = undefined;
    }
};

pub const ComponentRef = struct {
    tag_name: []const u8,
    resolved: bool,
    span: sfc.Span,
};

pub const Diagnostic = struct {
    severity: []const u8,
    kind: []const u8,
    name: []const u8,
    message: []const u8,
    span: sfc.Span,

    fn deinit(self: *Diagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.severity);
        allocator.free(self.kind);
        allocator.free(self.name);
        allocator.free(self.message);
    }
};

const Scope = struct {
    names: []const []const u8,

    fn contains(self: Scope, name: []const u8) bool {
        for (self.names) |local_name| {
            if (std.mem.eql(u8, local_name, name)) return true;
        }
        return false;
    }
};

/// Loads and caches slot manifests for neighbour .weiv components referenced by the parent.
const NeighbourLoader = struct {
    parent_path: []const u8,
    script: *const script_analysis.ScriptAnalysis,
    cache: std.StringHashMap(slot_manifest.Manifest),
    allocator: std.mem.Allocator,

    fn init(
        allocator: std.mem.Allocator,
        parent_path: []const u8,
        script: *const script_analysis.ScriptAnalysis,
    ) NeighbourLoader {
        return .{
            .parent_path = parent_path,
            .script = script,
            .cache = std.StringHashMap(slot_manifest.Manifest).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *NeighbourLoader) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.cache.deinit();
    }

    /// Returns null if:
    ///  - tag_name has no matching import binding
    ///  - the import is not a .weiv file
    ///  - the file cannot be opened/parsed (treated as "unknown" — no diagnostic)
    fn manifestFor(self: *NeighbourLoader, tag_name: []const u8) !?*const slot_manifest.Manifest {
        const specifier = self.findImportSpecifier(tag_name) orelse return null;
        if (!std.mem.endsWith(u8, specifier, ".weiv")) return null;

        const abs_path = try self.resolve(specifier);
        defer self.allocator.free(abs_path);

        if (self.cache.getPtr(abs_path)) |existing| return existing;

        if (!std.fs.path.isAbsolute(abs_path)) return null;
        const file = std.fs.openFileAbsolute(abs_path, .{}) catch return null;
        defer file.close();
        const file_source = file.readToEndAlloc(self.allocator, 1024 * 1024) catch return null;
        defer self.allocator.free(file_source);

        // Parse the SFC sections
        const sfc_doc = sfc.parse(file_source) catch return null;
        const template_content = sfc_doc.template.content;

        // Parse template AST and normalize
        var ast_doc = template.parse(template_content, self.allocator) catch return null;
        defer ast_doc.deinit(self.allocator);

        var normalized_doc = template.normalize(&ast_doc, self.allocator) catch return null;
        defer normalized_doc.deinit(self.allocator);

        // Build manifest (ignore duplicates — those are the child's own diagnostics)
        const manifest_result = slot_manifest.build(&normalized_doc, self.allocator) catch return null;
        // Free duplicates — we don't report them from the parent's perspective
        for (manifest_result.duplicates) |dup| {
            if (dup.name) |n| self.allocator.free(n);
        }
        self.allocator.free(manifest_result.duplicates);

        const key = try self.allocator.dupe(u8, abs_path);
        errdefer self.allocator.free(key);
        try self.cache.put(key, manifest_result.manifest);
        return self.cache.getPtr(key);
    }

    fn findImportSpecifier(self: *NeighbourLoader, tag_name: []const u8) ?[]const u8 {
        for (self.script.imports) |record| {
            if (std.mem.eql(u8, record.local_name, tag_name)) {
                return record.source;
            }
        }
        return null;
    }

    fn resolve(self: *NeighbourLoader, specifier: []const u8) ![]const u8 {
        const parent_dir = std.fs.path.dirname(self.parent_path) orelse ".";
        const joined = try std.fs.path.join(self.allocator, &.{ parent_dir, specifier });
        defer self.allocator.free(joined);
        // Try realpath first; fall back to the joined path if file doesn't exist yet
        return std.fs.realpathAlloc(self.allocator, joined) catch try self.allocator.dupe(u8, joined);
    }
};

pub fn bind(
    document: *const template.NormalizedDocument,
    script: *const script_analysis.ScriptAnalysis,
    parent_path: []const u8,
    allocator: std.mem.Allocator,
) anyerror!BindingResult {
    var component_refs = std.ArrayList(ComponentRef){};
    defer component_refs.deinit(allocator);
    var diagnostics = std.ArrayList(Diagnostic){};
    defer diagnostics.deinit(allocator);
    var scopes = std.ArrayList(Scope){};
    defer scopes.deinit(allocator);

    const manifest_result = try slot_manifest.build(document, allocator);
    defer {
        for (manifest_result.duplicates) |dup| {
            if (dup.name) |n| allocator.free(n);
        }
        allocator.free(manifest_result.duplicates);
    }

    for (manifest_result.duplicates) |dup| {
        const name_for_diag = dup.name orelse "default";
        try appendDiagnostic(&diagnostics, "slot.duplicate_outlet", name_for_diag, "Slot outlet declared more than once with the same name", dup.span, allocator);
    }

    try validateFrameworkBindings(script, &diagnostics, allocator);
    try validateStateModelDiagnostics(script, &diagnostics, allocator);

    var loader = NeighbourLoader.init(allocator, parent_path, script);
    defer loader.deinit();

    try bindNodes(document.nodes, script, &component_refs, &diagnostics, &scopes, &loader, allocator);

    return .{
        .component_refs = try component_refs.toOwnedSlice(allocator),
        .diagnostics = try diagnostics.toOwnedSlice(allocator),
        .own_slot_manifest = manifest_result.manifest,
    };
}

fn validateFrameworkBindings(
    script: *const script_analysis.ScriptAnalysis,
    diagnostics: *std.ArrayList(Diagnostic),
    allocator: std.mem.Allocator,
) !void {
    for (script.bindings) |binding| {
        if (std.mem.eql(u8, binding.name, "emit")) {
            try appendDiagnostic(
                diagnostics,
                "framework.reserved_binding",
                "emit",
                "`emit` is provided by Weiv for component events; declare `export interface Emits` for typing instead of defining `emit` yourself",
                .{ .start = binding.span_start, .end = binding.span_end },
                allocator,
            );
        }
    }
}

fn validateStateModelDiagnostics(
    script: *const script_analysis.ScriptAnalysis,
    diagnostics: *std.ArrayList(Diagnostic),
    allocator: std.mem.Allocator,
) !void {
    for (script.state_analysis.mutations) |mutation| {
        if (findAliasTarget(script, mutation.binding)) |target| {
            if (isVisibleBinding(target, script)) {
                try appendDiagnostic(
                    diagnostics,
                    "alias.mutation",
                    target,
                    "Mutation through a local alias is only shallowly tracked today, so Weiv will treat this site conservatively",
                    .{ .start = mutation.span_start, .end = mutation.span_end },
                    allocator,
                );
            }
            continue;
        }

        if (!isVisibleBinding(mutation.binding, script)) continue;

        if (!mutation.statement_position) {
            try appendDiagnostic(
                diagnostics,
                "mutation.expression_position",
                mutation.binding,
                "Mutation is nested inside a larger expression, so Weiv will treat this site conservatively",
                .{ .start = mutation.span_start, .end = mutation.span_end },
                allocator,
            );
            continue;
        }

        if (mutation.inside_callback and !mutation.callback_owned_candidate) {
            try appendDiagnostic(
                diagnostics,
                "callback.unowned_mutation",
                mutation.binding,
                "Mutation happens inside a callback boundary that Weiv does not own, so updates are conservative here",
                .{ .start = mutation.span_start, .end = mutation.span_end },
                allocator,
            );
            continue;
        }
    }
}

fn bindNodes(
    nodes: []const template.NormalizedNode,
    script: *const script_analysis.ScriptAnalysis,
    component_refs: *std.ArrayList(ComponentRef),
    diagnostics: *std.ArrayList(Diagnostic),
    scopes: *std.ArrayList(Scope),
    loader: *NeighbourLoader,
    allocator: std.mem.Allocator,
) anyerror!void {
    for (nodes) |node| {
        switch (node) {
            .text => {},
            .interpolation => |interp| try bindExpression(interp.expression, interp.span, script, diagnostics, scopes.items, allocator),
            .slot_outlet => |slot_outlet| {
                try bindNodes(slot_outlet.fallback_children, script, component_refs, diagnostics, scopes, loader, allocator);
            },
            .conditional => |conditional| {
                try bindExpression(conditional.condition, conditional.span, script, diagnostics, scopes.items, allocator);
                try bindNodes(conditional.consequent, script, component_refs, diagnostics, scopes, loader, allocator);
                try bindNodes(conditional.alternate, script, component_refs, diagnostics, scopes, loader, allocator);
            },
            .for_loop => |for_loop| {
                try bindExpression(for_loop.iterable_expr, for_loop.span, script, diagnostics, scopes.items, allocator);
                var loop_scope_names = [1][]const u8{for_loop.item_name};
                try scopes.append(allocator, .{ .names = loop_scope_names[0..1] });
                defer _ = scopes.pop();
                try bindNodes(for_loop.body, script, component_refs, diagnostics, scopes, loader, allocator);
            },
            .element => |element| try bindElement(&element, script, component_refs, diagnostics, scopes, loader, allocator),
        }
    }
}

fn bindElement(
    element: *const template.normalized.ElementNode,
    script: *const script_analysis.ScriptAnalysis,
    component_refs: *std.ArrayList(ComponentRef),
    diagnostics: *std.ArrayList(Diagnostic),
    scopes: *std.ArrayList(Scope),
    loader: *NeighbourLoader,
    allocator: std.mem.Allocator,
) anyerror!void {
    if (isComponentTag(element.tag_name)) {
        const resolved = isNameVisible(element.tag_name, script, scopes.items);
        try component_refs.append(allocator, .{
            .tag_name = element.tag_name,
            .resolved = resolved,
            .span = element.span,
        });
        if (!resolved) {
            try appendDiagnostic(diagnostics, "unresolved_component", element.tag_name, "Unresolved component tag", element.span, allocator);
        }
    }

    for (element.directives) |directive| {
        switch (directive) {
            .bind => |bind_dir| {
                try bindExpression(bind_dir.expression, element.span, script, diagnostics, scopes.items, allocator);
            },
            .event => |event_dir| {
                try bindExpression(event_dir.expression, element.span, script, diagnostics, scopes.items, allocator);
            },
            // slot:name placement (and <template slot:foo> placement) is enforced
            // as a hard error at parse/lower time in src/compiler/lower/lower.zig.
            // The binder no longer needs to re-check it.
            .slot_assign => {},
            .if_expr, .else_branch, .for_expr => unreachable,
        }
    }

    if (isComponentTag(element.tag_name)) {
        var seen = std.StringHashMap(bool).init(allocator);
        defer seen.deinit();
        for (element.children) |child| {
            switch (child) {
                .element => |child_el| {
                    for (child_el.directives) |dir| {
                        if (dir == .slot_assign) {
                            const sa = dir.slot_assign;
                            const is_template_group = std.mem.eql(u8, child_el.tag_name, "template");
                            if (seen.get(sa.slot_name)) |previous_was_template| {
                                if (!(previous_was_template and is_template_group)) {
                                    try appendDiagnostic(diagnostics, "slot.duplicate_provision", sa.slot_name, "Slot is provided more than once; use <template slot:<name>> to group multi-node content", sa.span, allocator);
                                }
                            }
                            try seen.put(sa.slot_name, is_template_group);
                        }
                    }
                },
                else => {},
            }
        }

        // Cross-component slot validation: check that provided slots exist in the child manifest.
        if (try loader.manifestFor(element.tag_name)) |child_manifest| {
            var has_unnamed_content = false;
            for (element.children) |child| {
                switch (child) {
                    .element => |child_el| {
                        var has_slot_assign = false;
                        for (child_el.directives) |dir| {
                            if (dir == .slot_assign) {
                                has_slot_assign = true;
                                const sa = dir.slot_assign;
                                if (!child_manifest.hasName(sa.slot_name)) {
                                    try appendDiagnostic(diagnostics, "slot.unknown_name", sa.slot_name, "Child component has no <slot> with this name", sa.span, allocator);
                                }
                            }
                        }
                        if (!has_slot_assign) has_unnamed_content = true;
                    },
                    .text => |t| {
                        if (!isWhitespaceOnly(t.content)) has_unnamed_content = true;
                    },
                    .interpolation => has_unnamed_content = true,
                    else => has_unnamed_content = true,
                }
            }
            if (has_unnamed_content and !child_manifest.hasDefault()) {
                try appendDiagnostic(diagnostics, "slot.default_not_supported", element.tag_name, "Component has no default <slot>; default content is not allowed", element.span, allocator);
            }
        }
    }

    try bindNodes(element.children, script, component_refs, diagnostics, scopes, loader, allocator);
}

fn isWhitespaceOnly(s: []const u8) bool {
    for (s) |b| {
        if (b != ' ' and b != '\t' and b != '\n' and b != '\r') return false;
    }
    return true;
}

fn bindExpression(
    expression: []const u8,
    span: sfc.Span,
    script: *const script_analysis.ScriptAnalysis,
    diagnostics: *std.ArrayList(Diagnostic),
    scopes: []const Scope,
    allocator: std.mem.Allocator,
) anyerror!void {
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var i: usize = 0;
    var in_quote: ?u8 = null;
    while (i < expression.len) {
        if (in_quote) |quote| {
            if (expression[i] == '\\' and i + 1 < expression.len) {
                i += 2;
                continue;
            }
            if (expression[i] == quote) {
                in_quote = null;
            }
            i += 1;
            continue;
        }

        if (expression[i] == '"' or expression[i] == '\'') {
            in_quote = expression[i];
            i += 1;
            continue;
        }
        if (!isIdentifierStart(expression[i])) {
            i += 1;
            continue;
        }

        const start = i;
        i += 1;
        while (i < expression.len and isIdentifierContinue(expression[i])) : (i += 1) {}
        const ident = expression[start..i];
        const is_call = nextNonSpaceIs(expression, i, '(');

        if (isKeyword(ident)) continue;
        if (start > 0 and expression[start - 1] == '.') continue;
        if (seen.contains(ident)) continue;
        try seen.put(ident, {});

        if (is_call) {
            if (findVisibleHelper(script, ident)) |helper| {
                const ident_span = sfc.Span{
                    .start = span.start + start,
                    .end = span.start + i,
                };
                if (helper.contains_external_reads) {
                    try appendDiagnostic(
                        diagnostics,
                        "helper.external_state",
                        ident,
                        "Local helper reads external state, so Weiv will treat this template call conservatively",
                        ident_span,
                        allocator,
                    );
                } else if (helper.contains_side_effects) {
                    try appendDiagnostic(
                        diagnostics,
                        "helper.side_effects",
                        ident,
                        "Local helper has side effects, so Weiv will treat this template call conservatively",
                        ident_span,
                        allocator,
                    );
                }
            }
        }

        if (!isNameVisible(ident, script, scopes)) {
            const ident_span = sfc.Span{
                .start = span.start + start,
                .end = span.start + i,
            };
            try appendDiagnostic(diagnostics, "unresolved_binding", ident, "Unresolved template binding", ident_span, allocator);
        }
    }
}

fn appendDiagnostic(
    diagnostics: *std.ArrayList(Diagnostic),
    kind: []const u8,
    name: []const u8,
    message: []const u8,
    span: sfc.Span,
    allocator: std.mem.Allocator,
) anyerror!void {
    try diagnostics.append(allocator, .{
        .severity = try allocator.dupe(u8, classifyDiagnosticSeverity(kind)),
        .kind = try allocator.dupe(u8, kind),
        .name = try allocator.dupe(u8, name),
        .message = try allocator.dupe(u8, message),
        .span = span,
    });
}

fn classifyDiagnosticSeverity(kind: []const u8) []const u8 {
    if (std.mem.eql(u8, kind, "framework.reserved_binding")) return "error";
    if (std.mem.eql(u8, kind, "unresolved_binding")) return "error";
    if (std.mem.eql(u8, kind, "unresolved_component")) return "error";
    if (std.mem.startsWith(u8, kind, "slot.")) return "error";
    if (std.mem.eql(u8, kind, "helper.external_state")) return "warning";
    if (std.mem.eql(u8, kind, "helper.side_effects")) return "warning";
    if (std.mem.eql(u8, kind, "mutation.expression_position")) return "warning";
    if (std.mem.eql(u8, kind, "callback.unowned_mutation")) return "warning";
    if (std.mem.eql(u8, kind, "alias.mutation")) return "warning";
    return "info";
}

fn isNameVisible(name: []const u8, script: *const script_analysis.ScriptAnalysis, scopes: []const Scope) bool {
    if (std.mem.eql(u8, name, "emit")) return true;

    var idx = scopes.len;
    while (idx > 0) {
        idx -= 1;
        if (scopes[idx].contains(name)) return true;
    }

    for (script.bindings) |binding| {
        if (binding.template_visible and std.mem.eql(u8, binding.name, name)) return true;
    }
    return false;
}

fn findVisibleHelper(script: *const script_analysis.ScriptAnalysis, name: []const u8) ?script_analysis.HelperRecord {
    for (script.bindings) |binding| {
        if (!binding.template_visible or !binding.callable) continue;
        if (!std.mem.eql(u8, binding.name, name)) continue;
        for (script.state_analysis.helpers) |helper| {
            if (std.mem.eql(u8, helper.name, name)) return helper;
        }
        return null;
    }
    return null;
}

fn findAliasTarget(script: *const script_analysis.ScriptAnalysis, alias_name: []const u8) ?[]const u8 {
    for (script.state_analysis.aliases) |alias| {
        if (std.mem.eql(u8, alias.alias, alias_name)) return alias.target;
    }
    return null;
}

fn isVisibleBinding(name: []const u8, script: *const script_analysis.ScriptAnalysis) bool {
    for (script.bindings) |binding| {
        if (binding.template_visible and std.mem.eql(u8, binding.name, name)) return true;
    }
    return false;
}

fn isComponentTag(tag_name: []const u8) bool {
    if (tag_name.len == 0) return false;
    return std.ascii.isUpper(tag_name[0]);
}

fn isIdentifierStart(char: u8) bool {
    return std.ascii.isAlphabetic(char) or char == '_' or char == '$';
}

fn isIdentifierContinue(char: u8) bool {
    return isIdentifierStart(char) or std.ascii.isDigit(char);
}

fn nextNonSpaceIs(expr: []const u8, idx: usize, expected: u8) bool {
    var cursor = idx;
    while (cursor < expr.len) : (cursor += 1) {
        if (expr[cursor] == ' ' or expr[cursor] == '\n' or expr[cursor] == '\r' or expr[cursor] == '\t') continue;
        return expr[cursor] == expected;
    }
    return false;
}

fn isKeyword(value: []const u8) bool {
    return std.mem.eql(u8, value, "true") or
        std.mem.eql(u8, value, "false") or
        std.mem.eql(u8, value, "null") or
        std.mem.eql(u8, value, "undefined") or
        std.mem.eql(u8, value, "in") or
        std.mem.eql(u8, value, "typeof") or
        std.mem.eql(u8, value, "return");
}
