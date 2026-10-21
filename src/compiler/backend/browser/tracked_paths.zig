const std = @import("std");
const component = @import("../../component_unit.zig");
const tracked_root = @import("../../sema/tracked_root.zig");

// Shared tracked-path inventory for browser code generation and inspection.
// Slices in roots and paths borrow from the component or expression source.
pub const Root = struct {
    id: usize,
    binding_name: []const u8,
    kind: []const u8,
};

pub const Path = struct {
    id: usize,
    root_id: usize,
    path: []const u8,
    parent_path_id: ?usize,
};

pub const Table = struct {
    allocator: std.mem.Allocator,
    component_model: *const component.ComponentUnit,
    roots: std.ArrayList(Root) = .empty,
    paths: std.ArrayList(Path) = .empty,

    pub fn init(component_model: *const component.ComponentUnit, allocator: std.mem.Allocator) Table {
        return .{ .allocator = allocator, .component_model = component_model };
    }

    pub fn deinit(self: *Table) void {
        self.roots.deinit(self.allocator);
        self.paths.deinit(self.allocator);
    }

    pub fn findRoot(self: *const Table, binding_name: []const u8) ?Root {
        for (self.roots.items) |root| {
            if (std.mem.eql(u8, root.binding_name, binding_name)) return root;
        }
        return null;
    }

    pub fn collectExpressionIds(self: *Table, expr: []const u8, path_ids: *std.ArrayList(usize)) !void {
        var i: usize = 0;
        while (i < expr.len) {
            const ch = expr[i];
            if (!isIdentStart(ch)) {
                i += 1;
                continue;
            }

            const root_start = i;
            i += 1;
            while (i < expr.len and isIdentContinue(expr[i])) i += 1;
            const root_name = expr[root_start..i];

            if (isKeyword(root_name)) continue;
            if (isPropertyAccessExpr(expr, root_start)) continue;
            if (tracked_root.kindByName(self.component_model, root_name) == null) continue;

            var cursor = i;
            var segment_count: usize = 0;
            var leaf_end = i;

            while (true) {
                const dot_index = nextNonSpaceIndex(expr, cursor) orelse break;
                if (expr[dot_index] != '.') break;

                var segment_start = dot_index + 1;
                while (segment_start < expr.len and isWhitespace(expr[segment_start])) segment_start += 1;
                if (segment_start >= expr.len or !isIdentStart(expr[segment_start])) break;

                var segment_end = segment_start + 1;
                while (segment_end < expr.len and isIdentContinue(expr[segment_end])) segment_end += 1;

                const call_index = nextNonSpaceIndex(expr, segment_end);
                if (call_index != null and expr[call_index.?] == '(') break;

                segment_count += 1;
                leaf_end = segment_end;
                cursor = segment_end;
            }

            if (segment_count == 0) continue;

            const full_path = std.mem.trimEnd(u8, expr[root_start..leaf_end], " \t\r\n");
            const leaf_path_id = try self.ensurePathChain(full_path);
            try appendUniqueUsize(self.allocator, path_ids, leaf_path_id);
        }
    }

    fn ensureRoot(self: *Table, binding_name: []const u8, kind: []const u8) !usize {
        for (self.roots.items) |root| {
            if (std.mem.eql(u8, root.binding_name, binding_name)) return root.id;
        }
        const id = self.roots.items.len + 1;
        try self.roots.append(self.allocator, .{ .id = id, .binding_name = binding_name, .kind = kind });
        return id;
    }

    fn findPathId(self: *const Table, path: []const u8) ?usize {
        for (self.paths.items) |tracked_path| {
            if (std.mem.eql(u8, tracked_path.path, path)) return tracked_path.id;
        }
        return null;
    }

    fn ensurePathChain(self: *Table, full_path: []const u8) !usize {
        if (self.findPathId(full_path)) |id| return id;
        const first_dot = std.mem.indexOfScalar(u8, full_path, '.') orelse return error.InvalidTrackedPath;
        const root_name = full_path[0..first_dot];
        const kind = tracked_root.kindByName(self.component_model, root_name) orelse return error.InvalidTrackedPath;
        const root_id = try self.ensureRoot(root_name, kind.label());

        var parent_path_id: ?usize = null;
        var search_from: usize = 0;
        while (true) {
            const maybe_dot = std.mem.indexOfScalarPos(u8, full_path, search_from, '.');
            const end_index = maybe_dot orelse full_path.len;
            const prefix = full_path[0..end_index];
            const path_id = if (self.findPathId(prefix)) |existing|
                existing
            else blk: {
                const new_id = self.paths.items.len + 1;
                try self.paths.append(self.allocator, .{
                    .id = new_id,
                    .root_id = root_id,
                    .path = prefix,
                    .parent_path_id = parent_path_id,
                });
                break :blk new_id;
            };
            parent_path_id = path_id;
            if (maybe_dot == null) return path_id;
            search_from = end_index + 1;
        }
    }
};

fn nextNonSpaceIndex(expr: []const u8, start: usize) ?usize {
    var cursor = start;
    while (cursor < expr.len) : (cursor += 1) {
        if (isWhitespace(expr[cursor])) continue;
        return cursor;
    }
    return null;
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

fn appendUniqueUsize(allocator: std.mem.Allocator, list: *std.ArrayList(usize), value: usize) !void {
    for (list.items) |item| {
        if (item == value) return;
    }
    try list.append(allocator, value);
}
