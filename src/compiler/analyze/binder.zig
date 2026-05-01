const std = @import("std");
const template = @import("../parse/template.zig");
const script_analysis = @import("ts/analysis.zig");
const sfc = @import("../parse/sfc.zig");

pub const BindingResult = struct {
    component_refs: []ComponentRef,
    diagnostics: []Diagnostic,

    pub fn deinit(self: *BindingResult, allocator: std.mem.Allocator) void {
        allocator.free(self.component_refs);
        for (self.diagnostics) |*diagnostic| diagnostic.deinit(allocator);
        allocator.free(self.diagnostics);
        self.* = undefined;
    }
};

pub const ComponentRef = struct {
    tag_name: []const u8,
    resolved: bool,
    span: sfc.Span,
};

pub const Diagnostic = struct {
    kind: []const u8,
    name: []const u8,
    message: []const u8,
    span: sfc.Span,

    fn deinit(self: *Diagnostic, allocator: std.mem.Allocator) void {
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

pub fn bind(
    document: *const template.NormalizedDocument,
    script: *const script_analysis.ScriptAnalysis,
    allocator: std.mem.Allocator,
) anyerror!BindingResult {
    var component_refs = std.ArrayList(ComponentRef){};
    defer component_refs.deinit(allocator);
    var diagnostics = std.ArrayList(Diagnostic){};
    defer diagnostics.deinit(allocator);
    var scopes = std.ArrayList(Scope){};
    defer scopes.deinit(allocator);

    try bindNodes(document.nodes, script, &component_refs, &diagnostics, &scopes, allocator);

    return .{
        .component_refs = try component_refs.toOwnedSlice(allocator),
        .diagnostics = try diagnostics.toOwnedSlice(allocator),
    };
}

fn bindNodes(
    nodes: []const template.NormalizedNode,
    script: *const script_analysis.ScriptAnalysis,
    component_refs: *std.ArrayList(ComponentRef),
    diagnostics: *std.ArrayList(Diagnostic),
    scopes: *std.ArrayList(Scope),
    allocator: std.mem.Allocator,
) anyerror!void {
    for (nodes) |node| {
        switch (node) {
            .text => {},
            .interpolation => |interp| try bindExpression(interp.expression, interp.span, script, diagnostics, scopes.items, allocator),
            .slot_outlet => |slot_outlet| {
                try bindNodes(slot_outlet.fallback_children, script, component_refs, diagnostics, scopes, allocator);
            },
            .conditional => |conditional| {
                try bindExpression(conditional.condition, conditional.span, script, diagnostics, scopes.items, allocator);
                try bindNodes(conditional.consequent, script, component_refs, diagnostics, scopes, allocator);
                try bindNodes(conditional.alternate, script, component_refs, diagnostics, scopes, allocator);
            },
            .for_loop => |for_loop| {
                try bindExpression(for_loop.iterable_expr, for_loop.span, script, diagnostics, scopes.items, allocator);
                var loop_scope_names = [1][]const u8{for_loop.item_name};
                try scopes.append(allocator, .{ .names = loop_scope_names[0..1] });
                defer _ = scopes.pop();
                try bindNodes(for_loop.body, script, component_refs, diagnostics, scopes, allocator);
            },
            .element => |element| try bindElement(&element, script, component_refs, diagnostics, scopes, allocator),
        }
    }
}

fn bindElement(
    element: *const template.normalized.ElementNode,
    script: *const script_analysis.ScriptAnalysis,
    component_refs: *std.ArrayList(ComponentRef),
    diagnostics: *std.ArrayList(Diagnostic),
    scopes: *std.ArrayList(Scope),
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
            .slot_assign => {},
            .if_expr, .else_branch, .for_expr => unreachable,
        }
    }

    try bindNodes(element.children, script, component_refs, diagnostics, scopes, allocator);
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

        if (isKeyword(ident)) continue;
        if (start > 0 and expression[start - 1] == '.') continue;
        if (seen.contains(ident)) continue;
        try seen.put(ident, {});

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
        .kind = try allocator.dupe(u8, kind),
        .name = try allocator.dupe(u8, name),
        .message = try allocator.dupe(u8, message),
        .span = span,
    });
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

fn isKeyword(value: []const u8) bool {
    return std.mem.eql(u8, value, "true") or
        std.mem.eql(u8, value, "false") or
        std.mem.eql(u8, value, "null") or
        std.mem.eql(u8, value, "undefined") or
        std.mem.eql(u8, value, "in") or
        std.mem.eql(u8, value, "typeof") or
        std.mem.eql(u8, value, "return");
}
