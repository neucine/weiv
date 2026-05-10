const std = @import("std");

pub const Severity = enum {
    @"error",
    warning,
    info,
};

pub const Stage = enum {
    sfc_parse,
    template_parse,
    template_normalize,
    script_analysis,
    binding,
    lowering,
    browser_plan,
    emit,
    bundle,
};

pub const Span = struct {
    start: usize,
    end: usize,
};

pub const SourceLocation = struct {
    line: u32,
    column: u32,
};

pub const Diagnostic = struct {
    code: []const u8,
    severity: Severity,
    message: []const u8,
    stage: Stage,
    source_path: []const u8,
    span: ?Span,
    location: ?SourceLocation,
    fatal: bool,

    pub fn deinit(self: *Diagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.message);
        allocator.free(self.source_path);
    }
};

pub const DiagnosticBag = struct {
    diagnostics: std.ArrayList(Diagnostic),

    pub fn init() DiagnosticBag {
        return .{
            .diagnostics = .{},
        };
    }

    pub fn deinit(self: *DiagnosticBag, allocator: std.mem.Allocator) void {
        for (self.diagnostics.items) |*diagnostic| diagnostic.deinit(allocator);
        self.diagnostics.deinit(allocator);
    }

    pub fn append(self: *DiagnosticBag, allocator: std.mem.Allocator, diagnostic: Diagnostic) !void {
        try self.diagnostics.append(allocator, diagnostic);
    }

    pub fn appendOwned(
        self: *DiagnosticBag,
        allocator: std.mem.Allocator,
        code: []const u8,
        severity: Severity,
        message: []const u8,
        stage: Stage,
        source_path: []const u8,
        span: ?Span,
        location: ?SourceLocation,
        fatal: bool,
    ) !void {
        try self.append(allocator, .{
            .code = try allocator.dupe(u8, code),
            .severity = severity,
            .message = try allocator.dupe(u8, message),
            .stage = stage,
            .source_path = try allocator.dupe(u8, source_path),
            .span = span,
            .location = location,
            .fatal = fatal,
        });
    }

    pub fn hasFatal(self: *const DiagnosticBag) bool {
        return hasFatalDiagnostics(self.diagnostics.items);
    }

    pub fn toOwnedSlice(self: *DiagnosticBag, allocator: std.mem.Allocator) ![]Diagnostic {
        return self.diagnostics.toOwnedSlice(allocator);
    }
};

pub fn hasFatalDiagnostics(diagnostics: []const Diagnostic) bool {
    for (diagnostics) |diagnostic| {
        if (diagnostic.fatal) return true;
    }
    return false;
}

pub fn severityFromString(value: []const u8) Severity {
    if (std.mem.eql(u8, value, "warning")) return .warning;
    if (std.mem.eql(u8, value, "info")) return .info;
    return .@"error";
}

pub fn severityLabel(severity: Severity) []const u8 {
    return switch (severity) {
        .@"error" => "error",
        .warning => "warning",
        .info => "info",
    };
}

pub fn stageLabel(stage: Stage) []const u8 {
    return switch (stage) {
        .sfc_parse => "sfc_parse",
        .template_parse => "template_parse",
        .template_normalize => "template_normalize",
        .script_analysis => "script_analysis",
        .binding => "binding",
        .lowering => "lowering",
        .browser_plan => "browser_plan",
        .emit => "emit",
        .bundle => "bundle",
    };
}

pub fn computeLocation(source: []const u8, span: Span) SourceLocation {
    var line: u32 = 1;
    var column: u32 = 1;
    var index: usize = 0;
    while (index < span.start and index < source.len) : (index += 1) {
        if (source[index] == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return .{
        .line = line,
        .column = column,
    };
}

pub fn writeTextDiagnostics(
    writer: anytype,
    diagnostics: []const Diagnostic,
    line_prefix: []const u8,
) !void {
    for (diagnostics) |diagnostic| {
        try writer.print("{s}{s} {s} [{s}]", .{
            line_prefix,
            severityLabel(diagnostic.severity),
            diagnostic.code,
            stageLabel(diagnostic.stage),
        });
        if (diagnostic.location) |location| {
            try writer.print(" [{d}:{d}]", .{ location.line, location.column });
        }
        if (diagnostic.span) |span| {
            try writer.print(" [{d}..{d}]", .{ span.start, span.end });
        }
        if (diagnostic.fatal) {
            try writer.writeAll(" fatal");
        }
        try writer.print(": {s}\n", .{diagnostic.message});
    }
}

pub fn writeJsonDiagnostics(
    writer: anytype,
    diagnostics: []const Diagnostic,
    item_indent: []const u8,
) !void {
    for (diagnostics, 0..) |diagnostic, index| {
        try writer.print("{s}{{\n", .{item_indent});
        try writer.print("{s}  \"code\": {f},\n", .{ item_indent, std.json.fmt(diagnostic.code, .{}) });
        try writer.print("{s}  \"severity\": {f},\n", .{ item_indent, std.json.fmt(severityLabel(diagnostic.severity), .{}) });
        try writer.print("{s}  \"stage\": {f},\n", .{ item_indent, std.json.fmt(stageLabel(diagnostic.stage), .{}) });
        try writer.print("{s}  \"message\": {f},\n", .{ item_indent, std.json.fmt(diagnostic.message, .{}) });
        try writer.print("{s}  \"sourcePath\": {f},\n", .{ item_indent, std.json.fmt(diagnostic.source_path, .{}) });
        if (diagnostic.span) |span| {
            try writer.print("{s}  \"span\": {{ \"start\": {d}, \"end\": {d} }},\n", .{ item_indent, span.start, span.end });
        } else {
            try writer.print("{s}  \"span\": null,\n", .{item_indent});
        }
        if (diagnostic.location) |location| {
            try writer.print("{s}  \"location\": {{ \"line\": {d}, \"column\": {d} }},\n", .{ item_indent, location.line, location.column });
        } else {
            try writer.print("{s}  \"location\": null,\n", .{item_indent});
        }
        try writer.print("{s}  \"fatal\": {any}\n", .{ item_indent, diagnostic.fatal });
        if (index + 1 < diagnostics.len) {
            try writer.print("{s}}},\n", .{item_indent});
        } else {
            try writer.print("{s}}}\n", .{item_indent});
        }
    }
}
