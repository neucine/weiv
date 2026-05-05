const std = @import("std");
const template = @import("../parse/template.zig");
const sfc = @import("../parse/sfc.zig");

pub const SlotEntry = struct {
    /// null name == default slot
    name: ?[]const u8,
    span: sfc.Span,
};

pub const Manifest = struct {
    entries: []SlotEntry,

    pub fn deinit(self: *Manifest, allocator: std.mem.Allocator) void {
        for (self.entries) |entry| {
            if (entry.name) |n| allocator.free(n);
        }
        allocator.free(self.entries);
        self.* = undefined;
    }

    pub fn hasDefault(self: Manifest) bool {
        for (self.entries) |entry| if (entry.name == null) return true;
        return false;
    }

    pub fn hasName(self: Manifest, name: []const u8) bool {
        for (self.entries) |entry| {
            if (entry.name) |n| {
                if (std.mem.eql(u8, n, name)) return true;
            }
        }
        return false;
    }
};

pub const DuplicateReport = struct {
    name: ?[]const u8,
    span: sfc.Span,
};

pub const BuildResult = struct {
    manifest: Manifest,
    duplicates: []DuplicateReport,

    pub fn deinit(self: *BuildResult, allocator: std.mem.Allocator) void {
        for (self.duplicates) |dup| {
            if (dup.name) |n| allocator.free(n);
        }
        allocator.free(self.duplicates);
        self.manifest.deinit(allocator);
        self.* = undefined;
    }
};

pub fn build(
    document: *const template.NormalizedDocument,
    allocator: std.mem.Allocator,
) !BuildResult {
    var entries = std.ArrayList(SlotEntry){};
    defer entries.deinit(allocator);
    var dups = std.ArrayList(DuplicateReport){};
    defer dups.deinit(allocator);

    try walk(document.nodes, &entries, &dups, allocator);

    return .{
        .manifest = .{ .entries = try entries.toOwnedSlice(allocator) },
        .duplicates = try dups.toOwnedSlice(allocator),
    };
}

fn walk(
    nodes: []const template.NormalizedNode,
    entries: *std.ArrayList(SlotEntry),
    dups: *std.ArrayList(DuplicateReport),
    allocator: std.mem.Allocator,
) anyerror!void {
    for (nodes) |node| {
        switch (node) {
            .element => |el| try walk(el.children, entries, dups, allocator),
            .slot_outlet => |out| {
                const name_copy: ?[]const u8 = if (out.name) |n| try allocator.dupe(u8, n) else null;
                for (entries.items) |existing| {
                    const both_default = existing.name == null and name_copy == null;
                    const same_name = blk: {
                        if (existing.name) |a| {
                            if (name_copy) |b| {
                                break :blk std.mem.eql(u8, a, b);
                            }
                        }
                        break :blk false;
                    };
                    if (both_default or same_name) {
                        const dup_name: ?[]const u8 = if (name_copy) |n| try allocator.dupe(u8, n) else null;
                        try dups.append(allocator, .{ .name = dup_name, .span = out.span });
                        break;
                    }
                }
                try entries.append(allocator, .{ .name = name_copy, .span = out.span });
            },
            .conditional => |c| {
                try walk(c.consequent, entries, dups, allocator);
                try walk(c.alternate, entries, dups, allocator);
            },
            .for_loop => |f| try walk(f.body, entries, dups, allocator),
            .text, .interpolation => {},
        }
    }
}
