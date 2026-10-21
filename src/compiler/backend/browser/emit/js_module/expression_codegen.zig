const std = @import("std");
const script_backend = @import("../../../../../ffi/script_backend.zig");

fn nextNonSpaceIs(expr: []const u8, start: usize, needle: u8) bool {
    var cursor = start;
    while (cursor < expr.len and isWhitespace(expr[cursor])) cursor += 1;
    return cursor < expr.len and expr[cursor] == needle;
}

fn isPropertyAccessExpr(expr: []const u8, ident_start: usize) bool {
    var cursor = ident_start;
    while (cursor > 0) {
        cursor -= 1;
        if (isWhitespace(expr[cursor])) continue;
        return expr[cursor] == '.';
    }
    return false;
}

fn isKeyword(ident: []const u8) bool {
    const keywords = [_][]const u8{
        "true",
        "false",
        "null",
        "undefined",
        "typeof",
        "instanceof",
        "return",
        "new",
        "await",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, ident, keyword)) return true;
    }
    return false;
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_' or ch == '$';
}

fn isIdentContinue(ch: u8) bool {
    return isIdentStart(ch) or std.ascii.isDigit(ch);
}

fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t';
}

pub fn emitResolvedExpression(
    expression: []const u8,
    scope_expr: []const u8,
    bindings_json: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const trimmed = std.mem.trim(u8, expression, &std.ascii.whitespace);
    if (trimmed.len == 0) {
        try out.appendSlice(allocator, "undefined");
        return;
    }

    if (isLiteralExpression(trimmed)) {
        try out.appendSlice(allocator, trimmed);
        return;
    }

    if (isSimpleAccessExpression(trimmed)) {
        try out.appendSlice(allocator, scope_expr);
        try out.append(allocator, '.');
        try out.appendSlice(allocator, trimmed);
        return;
    }

    if (try tryRewriteScopedCallExpression(trimmed, scope_expr, out, allocator)) {
        return;
    }

    if (try tryRewriteScopedExpression(trimmed, scope_expr, out, allocator)) {
        return;
    }

    if (bindings_json.len > 0) {
        if (script_backend.rewriteExpression(trimmed, bindings_json, scope_expr, allocator)) |rewritten| {
            defer allocator.free(rewritten);
            try out.appendSlice(allocator, rewritten);
            return;
        } else |_| {}
    }

    return error.UnsupportedTemplateExpression;
}

fn isLiteralExpression(expression: []const u8) bool {
    if (expression.len == 0) return false;
    if ((expression[0] == '\'' and expression[expression.len - 1] == '\'') or
        (expression[0] == '"' and expression[expression.len - 1] == '"')) return expression.len >= 2;

    if (std.mem.eql(u8, expression, "true") or
        std.mem.eql(u8, expression, "false") or
        std.mem.eql(u8, expression, "null") or
        std.mem.eql(u8, expression, "undefined")) return true;

    var seen_digit = false;
    var seen_dot = false;
    for (expression, 0..) |ch, idx| {
        if (idx == 0 and (ch == '+' or ch == '-')) continue;
        if (std.ascii.isDigit(ch)) {
            seen_digit = true;
            continue;
        }
        if (ch == '.' and !seen_dot) {
            seen_dot = true;
            continue;
        }
        return false;
    }
    return seen_digit;
}

fn isSimpleAccessExpression(expression: []const u8) bool {
    var cursor: usize = 0;
    if (!consumeIdentifier(expression, &cursor)) return false;
    while (cursor < expression.len) {
        if (expression[cursor] != '.') return false;
        cursor += 1;
        if (!consumeIdentifier(expression, &cursor)) return false;
    }
    return true;
}

fn consumeIdentifier(expression: []const u8, cursor: *usize) bool {
    if (cursor.* >= expression.len or !isIdentStart(expression[cursor.*])) return false;
    cursor.* += 1;
    while (cursor.* < expression.len and isIdentContinue(expression[cursor.*])) cursor.* += 1;
    return true;
}

fn tryRewriteScopedExpression(
    expression: []const u8,
    scope_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    return try tryRewriteScopedExpressionWithLocals(expression, scope_expr, &.{}, out, allocator);
}

fn tryRewriteScopedExpressionWithLocals(
    expression: []const u8,
    scope_expr: []const u8,
    locals: []const []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    var rewritten = std.ArrayList(u8).empty;
    defer rewritten.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < expression.len) {
        const ch = expression[cursor];
        if (isWhitespace(ch)) {
            try rewritten.append(allocator, ch);
            cursor += 1;
            continue;
        }

        if (ch == '\'' or ch == '"') {
            const end = scanQuotedString(expression, cursor) orelse return false;
            try rewritten.appendSlice(allocator, expression[cursor .. end + 1]);
            cursor = end + 1;
            continue;
        }

        if (isIdentStart(ch)) {
            const start = cursor;
            cursor += 1;
            while (cursor < expression.len and isIdentContinue(expression[cursor])) cursor += 1;
            const ident = expression[start..cursor];

            if (nextNonSpaceIs(expression, cursor, '(')) return false;

            if (isKeyword(ident)) {
                try rewritten.appendSlice(allocator, ident);
                continue;
            }

            if (containsName(locals, ident)) {
                try rewritten.appendSlice(allocator, ident);
                continue;
            }

            if (isPropertyAccessExpr(expression, start)) {
                try rewritten.appendSlice(allocator, ident);
                continue;
            }

            try rewritten.appendSlice(allocator, scope_expr);
            try rewritten.append(allocator, '.');
            try rewritten.appendSlice(allocator, ident);
            continue;
        }

        if (std.ascii.isDigit(ch)) {
            const start = cursor;
            cursor += 1;
            while (cursor < expression.len and (std.ascii.isDigit(expression[cursor]) or expression[cursor] == '.')) cursor += 1;
            try rewritten.appendSlice(allocator, expression[start..cursor]);
            continue;
        }

        if (isSupportedExpressionPunctuation(ch)) {
            try rewritten.append(allocator, ch);
            cursor += 1;
            continue;
        }

        return false;
    }

    try out.appendSlice(allocator, rewritten.items);
    return true;
}

fn tryRewriteScopedCallExpression(
    expression: []const u8,
    scope_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    const open_paren = std.mem.indexOfScalar(u8, expression, '(') orelse return false;
    const callee = std.mem.trimEnd(u8, expression[0..open_paren], &std.ascii.whitespace);
    if (callee.len == 0 or !isSimpleAccessExpression(callee)) return false;

    const close_paren = findMatchingParen(expression, open_paren) orelse return false;
    const suffix = std.mem.trim(u8, expression[close_paren + 1 ..], &std.ascii.whitespace);
    if (suffix.len != 0 and !isSimpleCallSuffixExpression(suffix)) return false;

    var rewritten = std.ArrayList(u8).empty;
    defer rewritten.deinit(allocator);

    try rewritten.appendSlice(allocator, scope_expr);
    try rewritten.append(allocator, '.');
    try rewritten.appendSlice(allocator, callee);
    try rewritten.append(allocator, '(');

    const args_source = expression[open_paren + 1 .. close_paren];
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    try splitCallArguments(args_source, &args, allocator);

    for (args.items, 0..) |arg, idx| {
        if (idx > 0) try rewritten.appendSlice(allocator, ", ");
        const trimmed_arg = std.mem.trim(u8, arg, &std.ascii.whitespace);
        if (trimmed_arg.len == 0) continue;
        if (try tryRewriteArrowCallbackExpression(trimmed_arg, scope_expr, &rewritten, allocator)) continue;
        if (!try tryRewriteScopedExpression(trimmed_arg, scope_expr, &rewritten, allocator)) return false;
    }

    try rewritten.append(allocator, ')');
    if (suffix.len != 0) try rewritten.appendSlice(allocator, suffix);
    try out.appendSlice(allocator, rewritten.items);
    return true;
}

fn tryRewriteArrowCallbackExpression(
    expression: []const u8,
    scope_expr: []const u8,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !bool {
    const arrow = std.mem.indexOf(u8, expression, "=>") orelse return false;
    const params_expr = std.mem.trim(u8, expression[0..arrow], &std.ascii.whitespace);
    const raw_body_expr = std.mem.trim(u8, expression[arrow + 2 ..], &std.ascii.whitespace);
    const body_expr = extractArrowCallbackReturnExpression(raw_body_expr) orelse return false;
    if (params_expr.len == 0 or body_expr.len == 0) return false;

    const param = parseArrowCallbackParam(params_expr) orelse return false;
    const locals = [_][]const u8{param};

    try out.appendSlice(allocator, params_expr);
    if (raw_body_expr.len > 0 and raw_body_expr[0] == '{') {
        try out.appendSlice(allocator, " => { return ");
        if (!try tryRewriteScopedExpressionWithLocals(body_expr, scope_expr, &locals, out, allocator)) return false;
        try out.appendSlice(allocator, "; }");
        return true;
    }

    try out.appendSlice(allocator, " => ");
    if (!try tryRewriteScopedExpressionWithLocals(body_expr, scope_expr, &locals, out, allocator)) return false;
    return true;
}

fn parseArrowCallbackParam(params_expr: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, params_expr, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    if (trimmed[0] == '(') {
        if (trimmed[trimmed.len - 1] != ')') return null;
        const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], &std.ascii.whitespace);
        if (inner.len == 0 or !isSimpleAccessExpression(inner)) return null;
        return inner;
    }
    if (!isSimpleAccessExpression(trimmed)) return null;
    return trimmed;
}

fn extractArrowCallbackReturnExpression(body_expr: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, body_expr, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;
    if (trimmed[0] != '{') return trimmed;
    if (trimmed[trimmed.len - 1] != '}') return null;

    const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], &std.ascii.whitespace);
    if (!std.mem.startsWith(u8, inner, "return")) return null;

    const return_expr = std.mem.trim(u8, inner["return".len..], &std.ascii.whitespace);
    if (return_expr.len == 0) return null;
    if (return_expr[return_expr.len - 1] != ';') return null;

    const expr = std.mem.trim(u8, return_expr[0 .. return_expr.len - 1], &std.ascii.whitespace);
    if (expr.len == 0) return null;
    return expr;
}

fn isSimpleCallSuffixExpression(expression: []const u8) bool {
    var cursor: usize = 0;
    while (cursor < expression.len) {
        if (expression[cursor] != '.') return false;
        cursor += 1;
        if (!consumeIdentifier(expression, &cursor)) return false;
    }
    return true;
}

fn containsName(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}

fn splitCallArguments(
    source: []const u8,
    out: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !void {
    var start: usize = 0;
    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_brace: usize = 0;
    var cursor: usize = 0;
    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (ch == '\'' or ch == '"') {
            const end = scanQuotedString(source, cursor) orelse return error.InvalidCallArgumentString;
            cursor = end;
            continue;
        }
        switch (ch) {
            '(' => depth_paren += 1,
            ')' => {
                if (depth_paren > 0) depth_paren -= 1;
            },
            '[' => depth_bracket += 1,
            ']' => {
                if (depth_bracket > 0) depth_bracket -= 1;
            },
            '{' => depth_brace += 1,
            '}' => {
                if (depth_brace > 0) depth_brace -= 1;
            },
            ',' => {
                if (depth_paren == 0 and depth_bracket == 0 and depth_brace == 0) {
                    try out.append(allocator, source[start..cursor]);
                    start = cursor + 1;
                }
            },
            else => {},
        }
    }
    if (start <= source.len) {
        try out.append(allocator, source[start..]);
    }
}

fn findMatchingParen(source: []const u8, open_paren: usize) ?usize {
    var depth: usize = 0;
    var cursor = open_paren;
    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (ch == '\'' or ch == '"') {
            cursor = scanQuotedString(source, cursor) orelse return null;
            continue;
        }
        if (ch == '(') {
            depth += 1;
            continue;
        }
        if (ch == ')') {
            depth -= 1;
            if (depth == 0) return cursor;
        }
    }
    return null;
}

fn scanQuotedString(expression: []const u8, start: usize) ?usize {
    const quote = expression[start];
    var cursor = start + 1;
    while (cursor < expression.len) : (cursor += 1) {
        if (expression[cursor] == '\\') {
            cursor += 1;
            continue;
        }
        if (expression[cursor] == quote) return cursor;
    }
    return null;
}

fn isSupportedExpressionPunctuation(ch: u8) bool {
    return switch (ch) {
        '.', '(', ')', '[', ']', '?', ':', '!', '=', '>', '<', '&', '|', '+', '-', '*', '/', '%', ',' => true,
        else => false,
    };
}
