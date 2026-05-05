const std = @import("std");
const browser_plan = @import("../browser_plan/index.zig");
const model = @import("../../pipeline/model.zig");

const DepList = struct {
    items: std.ArrayList([]const u8) = .{},

    fn deinit(self: *DepList, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
    }

    fn appendUnique(self: *DepList, allocator: std.mem.Allocator, name: []const u8) !void {
        for (self.items.items) |item| {
            if (std.mem.eql(u8, item, name)) return;
        }
        try self.items.append(allocator, name);
    }
};

const BoundaryKind = enum {
    template_event,
    child_event,
    slot_update,
};

const DiagnosticKind = enum {
    hidden_state,
    expression_mutation,
    unowned_callback_mutation,
};

const Diagnostic = struct {
    kind: DiagnosticKind,
    subject: []const u8,
    offset: ?usize = null,
};

const Formatter = struct {
    component: *const model.ComponentModel,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    next_region_id: usize = 1,
    diagnostics: std.ArrayList(Diagnostic) = .{},

    fn deinit(self: *Formatter) void {
        self.diagnostics.deinit(self.allocator);
    }

    fn format(self: *Formatter, plan: *const browser_plan.Document) !void {
        try self.out.writer(self.allocator).print("invalidation-graph source={s}\n", .{self.component.source_path});
        try self.out.appendSlice(self.allocator, "regions\n");
        try self.formatNodes(plan.nodes, 1, &.{});
        try self.out.appendSlice(self.allocator, "mutations\n");
        try self.formatMutations();
        try self.out.appendSlice(self.allocator, "boundaries\n");
        try self.formatBoundaries(plan.nodes, 1);
        if (self.diagnostics.items.len > 0) {
            try self.out.appendSlice(self.allocator, "diagnostics\n");
            for (self.diagnostics.items) |diagnostic| {
                try self.writeIndent(1);
                switch (diagnostic.kind) {
                    .hidden_state => try self.out.writer(self.allocator).print(
                        "hidden-state expression={s} reason=no-visible-component-dependency\n",
                        .{diagnostic.subject},
                    ),
                    .expression_mutation => try self.out.writer(self.allocator).print(
                        "expression-mutation binding={s} offset={d} reason=mutation-not-in-statement-position\n",
                        .{ diagnostic.subject, diagnostic.offset orelse 0 },
                    ),
                    .unowned_callback_mutation => try self.out.writer(self.allocator).print(
                        "unowned-callback-mutation binding={s} offset={d} reason=callback-boundary-not-owned\n",
                        .{ diagnostic.subject, diagnostic.offset orelse 0 },
                    ),
                }
            }
        }
    }

    fn formatNodes(self: *Formatter, nodes: []const browser_plan.Node, indent: usize, loop_locals: []const []const u8) !void {
        for (nodes) |node| {
            switch (node) {
                .text => {},
                .interpolation => |interp| {
                    try self.writeRegion(indent, "text", interp.ref_id, interp.expression, loop_locals);
                },
                .element => |element| {
                    for (element.bind_effects) |effect| {
                        switch (effect) {
                            .bind => |bind| try self.writeRegionWithName(indent, "attribute", element.ref_id, bind.target_name, bind.expression, loop_locals),
                            .event => {},
                        }
                    }
                    try self.formatNodes(element.children, indent, loop_locals);
                },
                .conditional => |conditional| {
                    try self.writeRegion(indent, "conditional", conditional.state_ref_id, conditional.condition, loop_locals);
                    try self.formatNodes(conditional.consequent, indent + 1, loop_locals);
                    try self.formatNodes(conditional.alternate, indent + 1, loop_locals);
                },
                .for_loop => |for_loop| {
                    try self.writeRegionWithName(indent, "loop", for_loop.state_ref_id, for_loop.item_name, for_loop.iterable_expr, loop_locals);

                    var next_locals = std.ArrayList([]const u8){};
                    defer next_locals.deinit(self.allocator);
                    try next_locals.appendSlice(self.allocator, loop_locals);
                    try next_locals.append(self.allocator, for_loop.item_name);
                    try self.formatNodes(for_loop.body, indent + 1, next_locals.items);
                },
                .component => |component_node| {
                    var deps = DepList{};
                    defer deps.deinit(self.allocator);
                    for (component_node.bind_effects) |effect| {
                        switch (effect) {
                            .bind => |bind| try self.collectExpressionDeps(bind.expression, loop_locals, &deps),
                            .event => {},
                        }
                    }
                    try self.writeRegionLine(indent, "child", component_node.handle_ref_id, component_node.tag_name, null, deps.items.items);
                    for (component_node.slot_provisions) |slot| {
                        const slot_name = slot.name orelse "default";
                        try self.writeRegionLine(indent + 1, "slot", component_node.handle_ref_id, slot_name, null, &.{});
                        try self.formatNodes(slot.children, indent + 2, loop_locals);
                    }
                },
                .slot_outlet => |slot_outlet| {
                    const slot_name = slot_outlet.name orelse "default";
                    try self.writeRegionLine(indent, "slot", slot_outlet.handle_ref_id, slot_name, null, &.{});
                    try self.formatNodes(slot_outlet.fallback_children, indent + 1, loop_locals);
                },
            }
        }
    }

    fn formatBoundaries(self: *Formatter, nodes: []const browser_plan.Node, indent: usize) !void {
        for (nodes) |node| {
            switch (node) {
                .element => |element| {
                    for (element.event_effects) |effect| {
                        switch (effect) {
                            .event => |event| try self.writeBoundary(indent, .template_event, event.event_name, event.expression),
                            .bind => {},
                        }
                    }
                    try self.formatBoundaries(element.children, indent);
                },
                .conditional => |conditional| {
                    try self.formatBoundaries(conditional.consequent, indent);
                    try self.formatBoundaries(conditional.alternate, indent);
                },
                .for_loop => |for_loop| try self.formatBoundaries(for_loop.body, indent),
                .component => |component_node| {
                    for (component_node.event_effects) |effect| {
                        switch (effect) {
                            .event => |event| try self.writeBoundary(indent, .child_event, event.event_name, event.expression),
                            .bind => {},
                        }
                    }
                    for (component_node.slot_provisions) |slot| {
                        try self.writeBoundary(indent, .slot_update, slot.name orelse "default", "compiler-emitted");
                        try self.formatBoundaries(slot.children, indent + 1);
                    }
                },
                .slot_outlet => |slot_outlet| try self.formatBoundaries(slot_outlet.fallback_children, indent),
                .text, .interpolation => {},
            }
        }
    }

    fn formatMutations(self: *Formatter) !void {
        const script = self.component.sfc_document.script.content;
        for (self.component.script.bindings) |binding| {
            if (!binding.template_visible) continue;
            var cursor: usize = 0;
            while (findIdentifier(script, binding.name, cursor)) |start| {
                cursor = start + binding.name.len;
                if (isPropertyAccess(script, start)) continue;
                if (isDeclarationBinding(script, start)) continue;

                const kind = classifyMutationAfterBinding(script, cursor) orelse continue;
                const absolute_offset = self.component.sfc_document.script.content_span.start + start;
                if (!isStatementPositionMutation(script, start)) {
                    try self.diagnostics.append(self.allocator, .{
                        .kind = .expression_mutation,
                        .subject = binding.name,
                        .offset = absolute_offset,
                    });
                    continue;
                }
                if (isInsideUnownedCallback(script, start)) {
                    try self.diagnostics.append(self.allocator, .{
                        .kind = .unowned_callback_mutation,
                        .subject = binding.name,
                        .offset = absolute_offset,
                    });
                    continue;
                }
                try self.writeIndent(1);
                try self.out.writer(self.allocator).print("{s} {s} offset={d}\n", .{
                    binding.name,
                    kind,
                    absolute_offset,
                });
            }
        }
    }

    fn writeRegion(self: *Formatter, indent: usize, kind: []const u8, ref_id: usize, expr: []const u8, loop_locals: []const []const u8) !void {
        var deps = DepList{};
        defer deps.deinit(self.allocator);
        try self.collectExpressionDeps(expr, loop_locals, &deps);
        try self.writeRegionLine(indent, kind, ref_id, null, expr, deps.items.items);
    }

    fn writeRegionWithName(
        self: *Formatter,
        indent: usize,
        kind: []const u8,
        ref_id: usize,
        name: []const u8,
        expr: []const u8,
        loop_locals: []const []const u8,
    ) !void {
        var deps = DepList{};
        defer deps.deinit(self.allocator);
        try self.collectExpressionDeps(expr, loop_locals, &deps);
        try self.writeRegionLine(indent, kind, ref_id, name, expr, deps.items.items);
    }

    fn writeRegionLine(
        self: *Formatter,
        indent: usize,
        kind: []const u8,
        ref_id: usize,
        name: ?[]const u8,
        expr: ?[]const u8,
        deps: []const []const u8,
    ) !void {
        const id = self.next_region_id;
        self.next_region_id += 1;

        try self.writeIndent(indent);
        try self.out.writer(self.allocator).print("#{d} {s} ref={d}", .{ id, kind, ref_id });
        if (name) |value| try self.out.writer(self.allocator).print(" name={s}", .{value});
        if (expr) |value| try self.out.writer(self.allocator).print(" expr={s}", .{value});
        try self.out.appendSlice(self.allocator, " deps=[");
        for (deps, 0..) |dep, idx| {
            if (idx > 0) try self.out.appendSlice(self.allocator, ",");
            try self.out.appendSlice(self.allocator, dep);
        }
        try self.out.appendSlice(self.allocator, "]\n");
    }

    fn writeBoundary(self: *Formatter, indent: usize, kind: BoundaryKind, name: []const u8, expr: []const u8) !void {
        try self.writeIndent(indent);
        try self.out.writer(self.allocator).print("{s} name={s} expr={s} owned=true", .{
            switch (kind) {
                .template_event => "template-event",
                .child_event => "child-event",
                .slot_update => "slot-update",
            },
            name,
            expr,
        });
        if (kind == .template_event and self.isAsyncFunction(expr)) {
            try self.out.appendSlice(self.allocator, " async=true");
        }
        try self.out.appendSlice(self.allocator, "\n");
    }

    fn collectExpressionDeps(self: *Formatter, expr: []const u8, loop_locals: []const []const u8, deps: *DepList) !void {
        var saw_call = false;
        var i: usize = 0;
        while (i < expr.len) {
            const ch = expr[i];
            if (!isIdentStart(ch)) {
                i += 1;
                continue;
            }

            const start = i;
            i += 1;
            while (i < expr.len and isIdentContinue(expr[i])) i += 1;
            const ident = expr[start..i];
            const call = nextNonSpaceIs(expr, i, '(');
            if (call) saw_call = true;

            if (isKeyword(ident)) continue;
            if (isPropertyAccess(expr, start)) continue;
            if (call and self.isImportedBinding(ident)) continue;

            if (self.isVisibleBinding(ident) or containsName(loop_locals, ident)) {
                try deps.appendUnique(self.allocator, ident);
            }
        }

        if (deps.items.items.len == 0 and saw_call) {
            try self.diagnostics.append(self.allocator, .{
                .kind = .hidden_state,
                .subject = expr,
            });
        }
    }

    fn isVisibleBinding(self: *const Formatter, name: []const u8) bool {
        for (self.component.script.bindings) |binding| {
            if (binding.template_visible and std.mem.eql(u8, binding.name, name)) return true;
        }
        return false;
    }

    fn isImportedBinding(self: *const Formatter, name: []const u8) bool {
        for (self.component.script.imports) |import| {
            if (std.mem.eql(u8, import.local_name, name)) return true;
        }
        return false;
    }

    fn isAsyncFunction(self: *const Formatter, name: []const u8) bool {
        const script = self.component.sfc_document.script.content;
        const pattern = std.fmt.allocPrint(self.allocator, "async function {s}", .{name}) catch return false;
        defer self.allocator.free(pattern);
        return std.mem.indexOf(u8, script, pattern) != null;
    }

    fn writeIndent(self: *Formatter, indent: usize) !void {
        for (0..indent) |_| try self.out.appendSlice(self.allocator, "  ");
    }
};

pub fn formatDocument(
    component: *const model.ComponentModel,
    plan: *const browser_plan.Document,
    allocator: std.mem.Allocator,
) ![]u8 {
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);

    var formatter = Formatter{
        .component = component,
        .out = &out,
        .allocator = allocator,
    };
    defer formatter.deinit();

    try formatter.format(plan);
    return try out.toOwnedSlice(allocator);
}

fn containsName(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}

fn findIdentifier(source: []const u8, name: []const u8, start: usize) ?usize {
    var cursor = start;
    while (std.mem.indexOfPos(u8, source, cursor, name)) |found| {
        const before_ok = found == 0 or !isIdentContinue(source[found - 1]);
        const after = found + name.len;
        const after_ok = after >= source.len or !isIdentContinue(source[after]);
        if (before_ok and after_ok) return found;
        cursor = found + name.len;
    }
    return null;
}

fn isDeclarationBinding(source: []const u8, ident_start: usize) bool {
    const previous = previousIdentifier(source, ident_start) orelse return false;
    return std.mem.eql(u8, previous, "let") or
        std.mem.eql(u8, previous, "const") or
        std.mem.eql(u8, previous, "var") or
        std.mem.eql(u8, previous, "function") or
        std.mem.eql(u8, previous, "interface") or
        std.mem.eql(u8, previous, "type");
}

fn previousIdentifier(source: []const u8, before: usize) ?[]const u8 {
    if (before == 0) return null;
    var cursor = before;
    while (cursor > 0 and isWhitespace(source[cursor - 1])) cursor -= 1;
    if (cursor == 0) return null;

    const end = cursor;
    while (cursor > 0 and isIdentContinue(source[cursor - 1])) cursor -= 1;
    if (cursor == end) return null;
    return source[cursor..end];
}

fn isStatementPositionMutation(source: []const u8, ident_start: usize) bool {
    if (isPostfixUpdate(source, ident_start)) return false;

    var cursor = ident_start;
    while (cursor > 0) {
        cursor -= 1;
        const ch = source[cursor];
        if (isWhitespace(ch)) continue;
        return ch == ';' or ch == '{' or ch == '}';
    }
    return true;
}

fn isPostfixUpdate(source: []const u8, ident_start: usize) bool {
    var cursor = ident_start;
    while (cursor > 0 and isWhitespace(source[cursor - 1])) cursor -= 1;
    if (cursor < 2) return false;
    const previous = source[cursor - 2 .. cursor];
    return std.mem.eql(u8, previous, "++") or std.mem.eql(u8, previous, "--");
}

fn isInsideUnownedCallback(source: []const u8, ident_start: usize) bool {
    var cursor = ident_start;
    while (cursor > 0) {
        cursor -= 1;
        const ch = source[cursor];
        if (ch == ';') return false;
        if (ch == '{') {
            const before_body = previousNonWhitespace(source, cursor) orelse return false;
            if (source[before_body] == ')') {
                return callbackOpenerLooksUnowned(source, before_body);
            }
            if (source[before_body] == '>' and before_body > 0 and source[before_body - 1] == '=') {
                const before_arrow = previousNonWhitespace(source, before_body - 1) orelse return false;
                if (source[before_arrow] == ')') return callbackOpenerLooksUnowned(source, before_arrow);
                if (isIdentContinue(source[before_arrow])) return singleParamCallbackLooksUnowned(source, before_arrow);
            }
            return false;
        }
    }
    return false;
}

fn callbackOpenerLooksUnowned(source: []const u8, close_paren: usize) bool {
    const open_paren = findMatchingOpenParen(source, close_paren) orelse return false;
    return callArgumentBeforeCallback(source, open_paren);
}

fn callArgumentBeforeCallback(source: []const u8, callback_open_paren: usize) bool {
    var cursor = callback_open_paren;
    while (cursor > 0) {
        cursor -= 1;
        const ch = source[cursor];
        if (isWhitespace(ch)) continue;
        return ch == ',' or ch == '(';
    }
    return false;
}

fn singleParamCallbackLooksUnowned(source: []const u8, param_end: usize) bool {
    var cursor = param_end + 1;
    while (cursor > 0 and isIdentContinue(source[cursor - 1])) cursor -= 1;
    return callArgumentBeforeCallback(source, cursor);
}

fn findMatchingOpenParen(source: []const u8, close_paren: usize) ?usize {
    var depth: usize = 0;
    var cursor = close_paren + 1;
    while (cursor > 0) {
        cursor -= 1;
        if (source[cursor] == ')') {
            depth += 1;
            continue;
        }
        if (source[cursor] == '(') {
            if (depth == 1) return cursor;
            depth -= 1;
        }
    }
    return null;
}

fn previousNonWhitespace(source: []const u8, before: usize) ?usize {
    var cursor = before;
    while (cursor > 0) {
        cursor -= 1;
        if (isWhitespace(source[cursor])) continue;
        return cursor;
    }
    return null;
}

fn classifyMutationAfterBinding(source: []const u8, idx: usize) ?[]const u8 {
    const next = skipWhitespaceIndex(source, idx);
    if (next >= source.len) return null;

    if (source[next] == '+' and next + 1 < source.len and source[next + 1] == '+') return "update";
    if (source[next] == '-' and next + 1 < source.len and source[next + 1] == '-') return "update";
    if (isAssignmentOperator(source, next)) return "assignment";

    if (source[next] == '.' or source[next] == '[') {
        if (classifyMemberMutation(source[next..])) |kind| return kind;
    }

    return null;
}

fn classifyMemberMutation(source: []const u8) ?[]const u8 {
    if (source.len == 0) return null;
    const statement_end = std.mem.indexOfAny(u8, source, ";\n") orelse source.len;
    const statement = source[0..statement_end];

    if (containsKnownMutatingMethod(statement)) return "method";
    if (std.mem.indexOfScalar(u8, statement, '=') != null) return "member-assignment";
    return null;
}

fn containsKnownMutatingMethod(source: []const u8) bool {
    const methods = [_][]const u8{
        ".push(",
        ".pop(",
        ".shift(",
        ".unshift(",
        ".splice(",
        ".sort(",
        ".reverse(",
        ".copyWithin(",
        ".fill(",
        ".set(",
        ".delete(",
        ".clear(",
        ".add(",
    };
    for (methods) |method| {
        if (std.mem.indexOf(u8, source, method) != null) return true;
    }
    return false;
}

fn isAssignmentOperator(source: []const u8, idx: usize) bool {
    const ch = source[idx];
    if (ch == '=') {
        return idx + 1 >= source.len or source[idx + 1] != '=' and source[idx + 1] != '>';
    }
    if (idx + 1 >= source.len or source[idx + 1] != '=') return false;
    return ch == '+' or ch == '-' or ch == '*' or ch == '/' or ch == '%' or
        ch == '&' or ch == '|' or ch == '^';
}

fn skipWhitespaceIndex(source: []const u8, idx: usize) usize {
    var cursor = idx;
    while (cursor < source.len and isWhitespace(source[cursor])) : (cursor += 1) {}
    return cursor;
}

fn isPropertyAccess(expr: []const u8, ident_start: usize) bool {
    if (ident_start == 0) return false;
    var idx = ident_start;
    while (idx > 0) {
        idx -= 1;
        if (isWhitespace(expr[idx])) continue;
        return expr[idx] == '.';
    }
    return false;
}

fn nextNonSpaceIs(expr: []const u8, idx: usize, expected: u8) bool {
    var cursor = idx;
    while (cursor < expr.len) : (cursor += 1) {
        if (isWhitespace(expr[cursor])) continue;
        return expr[cursor] == expected;
    }
    return false;
}

fn isKeyword(value: []const u8) bool {
    const keywords = [_][]const u8{
        "true",
        "false",
        "null",
        "undefined",
        "if",
        "else",
        "return",
        "typeof",
        "instanceof",
        "new",
        "await",
        "async",
        "event",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, value, keyword)) return true;
    }
    return false;
}

fn isIdentStart(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        ch == '_' or
        ch == '$';
}

fn isIdentContinue(ch: u8) bool {
    return isIdentStart(ch) or (ch >= '0' and ch <= '9');
}

fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t';
}
