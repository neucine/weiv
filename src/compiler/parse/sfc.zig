const std = @import("std");

pub const Span = struct {
    start: usize,
    end: usize,
};

pub const Section = struct {
    tag_name: []const u8,
    attributes: []const u8,
    open_span: Span,
    content_span: Span,
    close_span: Span,
    content: []const u8,
};

pub const Document = struct {
    source: []const u8,
    template: Section,
    script: Section,
    style: ?Section,
};

pub const ParseError = error{
    OutOfMemory,
    MissingTemplate,
    MissingScript,
    DuplicateTemplate,
    DuplicateScript,
    DuplicateStyle,
    UnknownTopLevelSection,
    InvalidScriptAttributes,
    InvalidSectionOrder,
    UnterminatedOpenTag,
    UnterminatedCloseTag,
};

pub fn parse(source: []const u8) ParseError!Document {
    var index: usize = 0;
    var template: ?Section = null;
    var script: ?Section = null;
    var style: ?Section = null;
    var expected_order: u8 = 0;

    while (true) {
        skipWhitespace(source, &index);
        if (index >= source.len) break;
        if (source[index] != '<') return error.UnknownTopLevelSection;

        const section = try parseSection(source, &index);
        if (std.mem.eql(u8, section.tag_name, "template")) {
            if (template != null) return error.DuplicateTemplate;
            if (expected_order != 0) return error.InvalidSectionOrder;
            template = section;
            expected_order = 1;
        } else if (std.mem.eql(u8, section.tag_name, "script")) {
            if (script != null) return error.DuplicateScript;
            if (expected_order > 1 or template == null) return error.InvalidSectionOrder;
            if (!isValidScriptAttributes(section.attributes)) return error.InvalidScriptAttributes;
            script = section;
            expected_order = 2;
        } else if (std.mem.eql(u8, section.tag_name, "style")) {
            if (style != null) return error.DuplicateStyle;
            if (expected_order > 2 or script == null) return error.InvalidSectionOrder;
            style = section;
            expected_order = 3;
        } else {
            return error.UnknownTopLevelSection;
        }
    }

    return .{
        .source = source,
        .template = template orelse return error.MissingTemplate,
        .script = script orelse return error.MissingScript,
        .style = style,
    };
}

fn parseSection(source: []const u8, index: *usize) ParseError!Section {
    const open_start = index.*;
    const gt_rel = std.mem.indexOfScalarPos(u8, source, open_start, '>') orelse return error.UnterminatedOpenTag;
    const open_end = gt_rel + 1;
    const open_inner = std.mem.trim(u8, source[open_start + 1 .. gt_rel], &std.ascii.whitespace);

    var parts = std.mem.tokenizeScalar(u8, open_inner, ' ');
    const tag_name = parts.next() orelse return error.UnknownTopLevelSection;
    const attrs_start = open_start + 1 + tag_name.len;
    const attrs_raw = std.mem.trim(u8, source[attrs_start..gt_rel], &std.ascii.whitespace);

    const content_start = open_end;
    const close_start = findMatchingCloseTag(source, content_start, tag_name) orelse return error.UnterminatedCloseTag;
    const close_tag = try std.fmt.allocPrint(std.heap.page_allocator, "</{s}>", .{tag_name});
    defer std.heap.page_allocator.free(close_tag);
    const close_end = close_start + close_tag.len;

    index.* = close_end;

    return .{
        .tag_name = tag_name,
        .attributes = attrs_raw,
        .open_span = .{ .start = open_start, .end = open_end },
        .content_span = .{ .start = content_start, .end = close_start },
        .close_span = .{ .start = close_start, .end = close_end },
        .content = source[content_start..close_start],
    };
}

fn skipWhitespace(source: []const u8, index: *usize) void {
    while (index.* < source.len and std.ascii.isWhitespace(source[index.*])) : (index.* += 1) {}
}

fn isValidScriptAttributes(attributes: []const u8) bool {
    return std.mem.eql(u8, attributes, "lang=\"ts\"");
}

fn findMatchingCloseTag(source: []const u8, content_start: usize, tag_name: []const u8) ?usize {
    var depth: usize = 1;
    var pos = content_start;

    while (pos < source.len) {
        const next_open = std.mem.indexOfPos(u8, source, pos, "<") orelse return null;
        pos = next_open;

        if (matchesOpenTag(source, pos, tag_name)) {
            const gt = std.mem.indexOfScalarPos(u8, source, pos, '>') orelse return null;
            if (gt > pos and source[gt - 1] != '/') {
                depth += 1;
            }
            pos = gt + 1;
            continue;
        }

        if (matchesCloseTag(source, pos, tag_name)) {
            if (depth == 1) return pos;
            depth -= 1;
            const gt = std.mem.indexOfScalarPos(u8, source, pos, '>') orelse return null;
            pos = gt + 1;
            continue;
        }

        pos += 1;
    }

    return null;
}

fn matchesOpenTag(source: []const u8, index: usize, tag_name: []const u8) bool {
    if (index + 1 + tag_name.len > source.len) return false;
    if (source[index] != '<') return false;
    if (index + 1 < source.len and source[index + 1] == '/') return false;
    if (!std.mem.eql(u8, source[index + 1 .. index + 1 + tag_name.len], tag_name)) return false;
    return hasTagBoundary(source, index + 1 + tag_name.len);
}

fn matchesCloseTag(source: []const u8, index: usize, tag_name: []const u8) bool {
    if (index + 2 + tag_name.len > source.len) return false;
    if (source[index] != '<' or source[index + 1] != '/') return false;
    if (!std.mem.eql(u8, source[index + 2 .. index + 2 + tag_name.len], tag_name)) return false;
    return hasTagBoundary(source, index + 2 + tag_name.len);
}

fn hasTagBoundary(source: []const u8, index: usize) bool {
    if (index >= source.len) return false;
    return std.ascii.isWhitespace(source[index]) or source[index] == '>' or source[index] == '/';
}
