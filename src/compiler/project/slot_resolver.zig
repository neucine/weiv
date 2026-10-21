const std = @import("std");
const template = @import("../parser/template/index.zig");
const sfc = @import("../parser/sfc.zig");
const sir = @import("../sema/sir.zig");
const slot_manifest = @import("../sema/slot_manifest.zig");

/// Loads and caches slot manifests for neighbour .weiv components referenced by the parent.
pub const NeighbourSlotResolver = struct {
    parent_path: []const u8,
    script: *const sir.ScriptFacts,
    cache: std.StringHashMap(slot_manifest.Manifest),
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        parent_path: []const u8,
        script: *const sir.ScriptFacts,
    ) NeighbourSlotResolver {
        return .{
            .parent_path = parent_path,
            .script = script,
            .cache = std.StringHashMap(slot_manifest.Manifest).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *NeighbourSlotResolver) void {
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
    pub fn manifestFor(self: *NeighbourSlotResolver, tag_name: []const u8) !?*const slot_manifest.Manifest {
        const specifier = self.findImportSpecifier(tag_name) orelse return null;
        if (!std.mem.endsWith(u8, specifier, ".weiv")) return null;

        const abs_path = try self.resolve(specifier);
        defer self.allocator.free(abs_path);

        if (self.cache.getPtr(abs_path)) |existing| return existing;

        if (!std.fs.path.isAbsolute(abs_path)) return null;
        const file_source = std.Io.Dir.cwd().readFileAlloc(
            std.Io.Threaded.global_single_threaded.io(),
            abs_path,
            self.allocator,
            .limited(1024 * 1024),
        ) catch return null;
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

    fn findImportSpecifier(self: *NeighbourSlotResolver, tag_name: []const u8) ?[]const u8 {
        for (self.script.imports) |record| {
            if (std.mem.eql(u8, record.local_name, tag_name)) {
                return record.source;
            }
        }
        return null;
    }

    fn resolve(self: *NeighbourSlotResolver, specifier: []const u8) ![]const u8 {
        const parent_dir = std.fs.path.dirname(self.parent_path) orelse ".";
        const joined = try std.fs.path.join(self.allocator, &.{ parent_dir, specifier });
        defer self.allocator.free(joined);
        // Try realpath first; fall back to the joined path if file doesn't exist yet
        const real_path = std.Io.Dir.cwd().realPathFileAlloc(std.Io.Threaded.global_single_threaded.io(), joined, self.allocator) catch return try self.allocator.dupe(u8, joined);
        defer self.allocator.free(real_path);
        return try self.allocator.dupe(u8, real_path);
    }

    pub fn provider(self: *NeighbourSlotResolver) slot_manifest.Provider {
        return .{ .context = self, .manifest_for = manifestForContext };
    }

    fn manifestForContext(context: *anyopaque, tag_name: []const u8) anyerror!?*const slot_manifest.Manifest {
        const self: *NeighbourSlotResolver = @ptrCast(@alignCast(context));
        return self.manifestFor(tag_name);
    }
};
