const std = @import("std");
const component = @import("../../../component_unit.zig");
const compiler_diagnostics = @import("../../../diagnostics.zig");

pub fn emitScopedCss(model: *const component.ComponentUnit, allocator: std.mem.Allocator) ![]u8 {
    const style_section = model.sfc_document.style orelse return allocator.dupe(u8, "");
    const scope_id = try scopeIdForPath(model.source_path, allocator);
    defer allocator.free(scope_id);

    const scope_selector = try std.fmt.allocPrint(allocator, "[data-weiv-scope=\"{s}\"]", .{scope_id});
    defer allocator.free(scope_selector);

    return try rewriteStylesheet(style_section.content, scope_selector, allocator);
}

pub fn appendEmitDiagnostics(
    bag: *compiler_diagnostics.DiagnosticBag,
    model: *const component.ComponentUnit,
    source: []const u8,
    allocator: std.mem.Allocator,
) !void {
    const style_section = model.sfc_document.style orelse return;
    const css = emitScopedCss(model, allocator) catch |err| {
        switch (err) {
            error.UnterminatedRule => {
                const span_end = if (style_section.content_span.end > style_section.content_span.start)
                    style_section.content_span.end
                else
                    @min(source.len, style_section.content_span.start + 1);
                const span = compiler_diagnostics.Span{
                    .start = style_section.content_span.start,
                    .end = span_end,
                };
                try bag.appendOwned(
                    allocator,
                    "style.unterminated_rule",
                    .@"error",
                    "Unterminated scoped style rule",
                    .emit,
                    model.source_path,
                    span,
                    compiler_diagnostics.computeLocation(source, span),
                    true,
                );
                return;
            },
            else => return err,
        }
    };
    allocator.free(css);
}

pub fn scopeIdForPath(source_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(source_path);
    return std.fmt.allocPrint(allocator, "w{X:0>16}", .{hasher.final()});
}

fn rewriteStylesheet(input: []const u8, scope_selector: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try rewriteRules(input, scope_selector, allocator, &out);
    return try out.toOwnedSlice(allocator);
}

fn rewriteRules(
    input: []const u8,
    scope_selector: []const u8,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) anyerror!void {
    var i: usize = 0;
    while (i < input.len) {
        if (isWhitespace(input[i])) {
            const start = i;
            while (i < input.len and isWhitespace(input[i])) : (i += 1) {}
            try out.appendSlice(allocator, input[start..i]);
            continue;
        }

        if (startsWithComment(input, i)) {
            const end = indexAfterComment(input, i) orelse input.len;
            try out.appendSlice(allocator, input[i..end]);
            i = end;
            continue;
        }

        if (input[i] == '@') {
            i = try rewriteAtRule(input, i, scope_selector, allocator, out);
            continue;
        }

        i = try rewriteQualifiedRule(input, i, scope_selector, allocator, out);
    }
}

fn rewriteAtRule(
    input: []const u8,
    start: usize,
    scope_selector: []const u8,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) anyerror!usize {
    const header_end = try findAtRuleEnd(input, start);
    if (header_end >= input.len or input[header_end] == ';') {
        try out.appendSlice(allocator, input[start .. header_end + 1]);
        return header_end + 1;
    }

    try out.appendSlice(allocator, input[start .. header_end + 1]);

    const block_end = try findMatchingBrace(input, header_end);
    const inner = input[header_end + 1 .. block_end];
    const header = std.mem.trim(u8, input[start..header_end], &std.ascii.whitespace);

    if (shouldRecurseAtRule(header)) {
        try rewriteRules(inner, scope_selector, allocator, out);
    } else {
        try out.appendSlice(allocator, inner);
    }

    try out.append(allocator, '}');
    return block_end + 1;
}

fn rewriteQualifiedRule(
    input: []const u8,
    start: usize,
    scope_selector: []const u8,
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) anyerror!usize {
    const brace_index = try findRuleOpenBrace(input, start);
    const block_end = try findMatchingBrace(input, brace_index);

    const selector_source = std.mem.trim(u8, input[start..brace_index], &std.ascii.whitespace);
    const scoped_selector = try prefixSelectorList(selector_source, scope_selector, allocator);
    defer allocator.free(scoped_selector);

    try out.appendSlice(allocator, scoped_selector);
    try out.appendSlice(allocator, " {");
    try out.appendSlice(allocator, input[brace_index + 1 .. block_end]);
    try out.append(allocator, '}');

    return block_end + 1;
}

fn prefixSelectorList(selector_source: []const u8, scope_selector: []const u8, allocator: std.mem.Allocator) anyerror![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var start: usize = 0;
    var i: usize = 0;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    while (i <= selector_source.len) : (i += 1) {
        const is_end = i == selector_source.len;
        if (!is_end) {
            switch (selector_source[i]) {
                '(' => paren_depth += 1,
                ')' => {
                    if (paren_depth > 0) paren_depth -= 1;
                },
                '[' => bracket_depth += 1,
                ']' => {
                    if (bracket_depth > 0) bracket_depth -= 1;
                },
                else => {},
            }
        }

        if (is_end or (selector_source[i] == ',' and paren_depth == 0 and bracket_depth == 0)) {
            const part = std.mem.trim(u8, selector_source[start..i], &std.ascii.whitespace);
            if (part.len > 0) {
                if (out.items.len > 0) try out.appendSlice(allocator, ", ");
                if (globalSelectorContents(part)) |global_selector| {
                    try out.appendSlice(allocator, global_selector);
                } else {
                    try out.print(allocator, "{s}{s}, {s} {s}", .{ scope_selector, part, scope_selector, part });
                }
            }
            start = i + 1;
        }
    }

    return try out.toOwnedSlice(allocator);
}

fn globalSelectorContents(selector: []const u8) ?[]const u8 {
    const prefix = ":global(";
    if (!std.mem.startsWith(u8, selector, prefix) or selector.len <= prefix.len or selector[selector.len - 1] != ')') {
        return null;
    }

    var depth: usize = 1;
    var i: usize = prefix.len;
    while (i + 1 < selector.len) : (i += 1) {
        switch (selector[i]) {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if (depth == 0) return null;
            },
            else => {},
        }
    }
    if (depth != 1) return null;

    const contents = std.mem.trim(u8, selector[prefix.len .. selector.len - 1], &std.ascii.whitespace);
    return if (contents.len == 0) null else contents;
}

fn shouldRecurseAtRule(header: []const u8) bool {
    return std.mem.startsWith(u8, header, "@media") or
        std.mem.startsWith(u8, header, "@supports") or
        std.mem.startsWith(u8, header, "@layer");
}

fn findAtRuleEnd(input: []const u8, start: usize) anyerror!usize {
    var i = start;
    var paren_depth: usize = 0;
    var in_string: ?u8 = null;
    while (i < input.len) : (i += 1) {
        const ch = input[i];
        if (in_string) |quote| {
            if (ch == '\\' and i + 1 < input.len) {
                i += 1;
                continue;
            }
            if (ch == quote) in_string = null;
            continue;
        }
        switch (ch) {
            '"', '\'' => in_string = ch,
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            ';', '{' => if (paren_depth == 0) return i,
            else => {},
        }
    }
    return error.UnterminatedRule;
}

fn findRuleOpenBrace(input: []const u8, start: usize) anyerror!usize {
    var i = start;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var in_string: ?u8 = null;
    while (i < input.len) : (i += 1) {
        const ch = input[i];
        if (in_string) |quote| {
            if (ch == '\\' and i + 1 < input.len) {
                i += 1;
                continue;
            }
            if (ch == quote) in_string = null;
            continue;
        }
        switch (ch) {
            '"', '\'' => in_string = ch,
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth > 0) bracket_depth -= 1;
            },
            '{' => if (paren_depth == 0 and bracket_depth == 0) return i,
            else => {},
        }
    }
    return error.UnterminatedRule;
}

fn findMatchingBrace(input: []const u8, open_brace_index: usize) anyerror!usize {
    var i = open_brace_index;
    var depth: usize = 0;
    var in_string: ?u8 = null;
    while (i < input.len) : (i += 1) {
        const ch = input[i];
        if (in_string) |quote| {
            if (ch == '\\' and i + 1 < input.len) {
                i += 1;
                continue;
            }
            if (ch == quote) in_string = null;
            continue;
        }
        switch (ch) {
            '"', '\'' => in_string = ch,
            '{' => depth += 1,
            '}' => {
                if (depth == 0) return error.UnterminatedRule;
                depth -= 1;
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    return error.UnterminatedRule;
}

fn startsWithComment(input: []const u8, index: usize) bool {
    return index + 1 < input.len and input[index] == '/' and input[index + 1] == '*';
}

fn indexAfterComment(input: []const u8, start: usize) ?usize {
    const close = std.mem.indexOfPos(u8, input, start + 2, "*/") orelse return null;
    return close + 2;
}

fn isWhitespace(ch: u8) bool {
    return std.ascii.isWhitespace(ch);
}
