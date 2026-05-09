const std = @import("std");
const browser_plan = @import("../browser_plan/index.zig");
const model = @import("../../pipeline/model.zig");
const script_analysis = @import("../../analyze/ts/analysis.zig");
const tracked_root = @import("../../analyze/tracked_root.zig");

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
    alias_mutation,
    unowned_callback_mutation,
    escape_warning,
    runtime_evaluate_fallback,
};

const DiagnosticSeverity = enum {
    warning,
    info,
};

const Diagnostic = struct {
    severity: DiagnosticSeverity,
    kind: DiagnosticKind,
    subject: []const u8,
    related: ?[]const u8 = null,
    offset: ?usize = null,
    reason: ?[]const u8 = null,
};

const TrackedRoot = struct {
    id: usize,
    binding_name: []const u8,
    kind: []const u8,

    fn deinit(self: *TrackedRoot, allocator: std.mem.Allocator) void {
        allocator.free(self.binding_name);
        allocator.free(self.kind);
    }
};

const TrackedPath = struct {
    id: usize,
    root_id: usize,
    path: []const u8,
    parent_path_id: ?usize,

    fn deinit(self: *TrackedPath, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

const Formatter = struct {
    component: *const model.ComponentModel,
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    next_region_id: usize = 1,
    diagnostics: std.ArrayList(Diagnostic) = .{},
    tracked_roots: std.ArrayList(TrackedRoot) = .{},
    tracked_paths: std.ArrayList(TrackedPath) = .{},

    fn deinit(self: *Formatter) void {
        self.diagnostics.deinit(self.allocator);
        for (self.tracked_roots.items) |*root| root.deinit(self.allocator);
        self.tracked_roots.deinit(self.allocator);
        for (self.tracked_paths.items) |*path| path.deinit(self.allocator);
        self.tracked_paths.deinit(self.allocator);
    }

    fn format(self: *Formatter, plan: *const browser_plan.Document) !void {
        try self.out.writer(self.allocator).print("invalidation-graph source={s}\n", .{self.component.source_path});
        try self.out.appendSlice(self.allocator, "regions\n");
        try self.formatNodes(plan.nodes, 1, &.{});
        if (self.tracked_roots.items.len > 0) {
            try self.out.appendSlice(self.allocator, "tracked-roots\n");
            try self.formatTrackedRoots();
            try self.out.appendSlice(self.allocator, "tracked-paths\n");
            try self.formatTrackedPaths();
        }
        try self.out.appendSlice(self.allocator, "mutations\n");
        try self.formatMutations();
        try self.out.appendSlice(self.allocator, "callback-registrations\n");
        try self.formatCallbackRegistrations();
        try self.out.appendSlice(self.allocator, "boundaries\n");
        try self.formatBoundaries(plan.nodes, 1);
        try self.formatHelperEscapeWarnings();
        try self.formatCallEscapeWarnings();
        if (self.diagnostics.items.len > 0) {
            try self.out.appendSlice(self.allocator, "diagnostics\n");
            for (self.diagnostics.items) |diagnostic| {
                try self.writeIndent(1);
                switch (diagnostic.kind) {
                    .hidden_state => try self.out.writer(self.allocator).print(
                        "{s} hidden-state expression={s} reason={s}\n",
                        .{ severityLabel(diagnostic.severity), diagnostic.subject, diagnostic.reason orelse "no-visible-component-dependency" },
                    ),
                    .expression_mutation => try self.out.writer(self.allocator).print(
                        "{s} expression-mutation binding={s} offset={d} reason=mutation-not-in-statement-position\n",
                        .{ severityLabel(diagnostic.severity), diagnostic.subject, diagnostic.offset orelse 0 },
                    ),
                    .alias_mutation => try self.out.writer(self.allocator).print(
                        "{s} alias-mutation binding={s} alias={s} offset={d} reason=alias-tracking-not-implemented\n",
                        .{ severityLabel(diagnostic.severity), diagnostic.subject, diagnostic.related orelse "", diagnostic.offset orelse 0 },
                    ),
                    .unowned_callback_mutation => try self.out.writer(self.allocator).print(
                        "{s} unowned-callback-mutation binding={s} offset={d} reason=callback-boundary-not-owned\n",
                        .{ severityLabel(diagnostic.severity), diagnostic.subject, diagnostic.offset orelse 0 },
                    ),
                    .escape_warning => try self.out.writer(self.allocator).print(
                        "{s} escape-warning binding={s} related={s} offset={d} reason={s}\n",
                        .{
                            severityLabel(diagnostic.severity),
                            diagnostic.subject,
                            diagnostic.related orelse "",
                            diagnostic.offset orelse 0,
                            diagnostic.reason orelse "tracked-root-escape",
                        },
                    ),
                    .runtime_evaluate_fallback => try self.out.writer(self.allocator).print(
                        "{s} runtime-evaluate-fallback expression={s} reason={s}\n",
                        .{ severityLabel(diagnostic.severity), diagnostic.subject, classifyEvaluateFallback(diagnostic.subject) },
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
                    try self.writeRegionLine(indent, "child", component_node.handle_ref_id, component_node.tag_name, null, deps.items.items, &.{});
                    for (component_node.slot_provisions) |slot| {
                        const slot_name = slot.name orelse "default";
                        try self.writeRegionLine(indent + 1, "slot", component_node.handle_ref_id, slot_name, null, &.{}, &.{});
                        try self.formatNodes(slot.children, indent + 2, loop_locals);
                    }
                },
                .slot_outlet => |slot_outlet| {
                    const slot_name = slot_outlet.name orelse "default";
                    try self.writeRegionLine(indent, "slot", slot_outlet.handle_ref_id, slot_name, null, &.{}, &.{});
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
        for (self.component.script.state_analysis.mutations) |mutation| {
            const absolute_offset = self.component.sfc_document.script.content_span.start + mutation.span_start;

            if (self.findAliasTarget(mutation.binding)) |target| {
                if (self.isVisibleBinding(target) or self.findTrackedRoot(target) != null) {
                    if (self.findTrackedRoot(target) != null) {
                        try self.diagnostics.append(self.allocator, .{
                            .severity = .warning,
                            .kind = .escape_warning,
                            .subject = target,
                            .related = mutation.binding,
                            .offset = absolute_offset,
                            .reason = "tracked-root-alias-escape",
                        });
                    }
                    try self.diagnostics.append(self.allocator, .{
                        .severity = .warning,
                        .kind = .alias_mutation,
                        .subject = target,
                        .related = mutation.binding,
                        .offset = absolute_offset,
                    });
                }
                continue;
            }

            if (!self.isVisibleBinding(mutation.binding) and self.findTrackedRoot(mutation.binding) == null) continue;

            if (!mutation.statement_position) {
                try self.diagnostics.append(self.allocator, .{
                    .severity = .warning,
                    .kind = .expression_mutation,
                    .subject = mutation.binding,
                    .offset = absolute_offset,
                });
                continue;
            }

            if (mutation.inside_callback and !mutation.callback_owned_candidate) {
                if (self.findTrackedRoot(mutation.binding) != null) {
                    try self.diagnostics.append(self.allocator, .{
                        .severity = .warning,
                        .kind = .escape_warning,
                        .subject = mutation.binding,
                        .offset = absolute_offset,
                        .reason = "tracked-root-unowned-callback",
                    });
                }
                try self.diagnostics.append(self.allocator, .{
                    .severity = .warning,
                    .kind = .unowned_callback_mutation,
                    .subject = mutation.binding,
                    .offset = absolute_offset,
                });
                continue;
            }

            try self.writeIndent(1);
            try self.out.writer(self.allocator).print("{s} {s} offset={d}\n", .{
                mutation.binding,
                mutation.kind,
                absolute_offset,
            });
        }
    }

    fn formatCallbackRegistrations(self: *Formatter) !void {
        for (self.component.script.state_analysis.callback_registrations) |registration| {
            try self.writeIndent(1);
            try self.out.writer(self.allocator).print(
                "callback callee={s} kind={s} owned_candidate={s} reason={s} offset={d}\n",
                .{
                    registration.callee,
                    registration.callback_kind,
                    if (registration.owned_candidate) "true" else "false",
                    registration.reason,
                    self.component.sfc_document.script.content_span.start + registration.callback_span_start,
                },
            );
        }
    }

    fn formatHelperEscapeWarnings(self: *Formatter) !void {
        const script = self.component.sfc_document.script.content;
        for (self.component.script.state_analysis.helpers) |helper| {
            if (helper.span_end <= helper.span_start or helper.span_end > script.len) continue;
            const helper_source = script[helper.span_start..helper.span_end];
            for (self.tracked_roots.items) |root| {
                const return_pattern = std.fmt.allocPrint(self.allocator, "return {s}.", .{root.binding_name}) catch continue;
                defer self.allocator.free(return_pattern);
                const arrow_pattern = std.fmt.allocPrint(self.allocator, "=> {s}.", .{root.binding_name}) catch continue;
                defer self.allocator.free(arrow_pattern);

                if (std.mem.indexOf(u8, helper_source, return_pattern) == null and
                    std.mem.indexOf(u8, helper_source, arrow_pattern) == null) continue;

                try self.diagnostics.append(self.allocator, .{
                    .severity = .warning,
                    .kind = .escape_warning,
                    .subject = root.binding_name,
                    .related = helper.name,
                    .offset = self.component.sfc_document.script.content_span.start + helper.span_start,
                    .reason = "tracked-root-nested-return",
                });
            }
        }
    }

    fn formatCallEscapeWarnings(self: *Formatter) !void {
        const script = self.component.sfc_document.script.content;
        for (self.tracked_roots.items) |root| {
            const pattern = std.fmt.allocPrint(self.allocator, "{s}.", .{root.binding_name}) catch continue;
            defer self.allocator.free(pattern);

            var search_from: usize = 0;
            while (std.mem.indexOfPos(u8, script, search_from, pattern)) |match_index| {
                search_from = match_index + pattern.len;
                if (!isLikelyCallEscape(script, match_index)) continue;

                try self.diagnostics.append(self.allocator, .{
                    .severity = .warning,
                    .kind = .escape_warning,
                    .subject = root.binding_name,
                    .offset = self.component.sfc_document.script.content_span.start + match_index,
                    .reason = "tracked-root-call-escape",
                });
                break;
            }
        }
    }

    fn formatTrackedRoots(self: *Formatter) !void {
        for (self.tracked_roots.items) |root| {
            try self.writeIndent(1);
            try self.out.writer(self.allocator).print("root id={d} binding={s} kind={s}\n", .{
                root.id,
                root.binding_name,
                root.kind,
            });
        }
    }

    fn formatTrackedPaths(self: *Formatter) !void {
        for (self.tracked_paths.items) |path| {
            try self.writeIndent(1);
            try self.out.writer(self.allocator).print("path id={d} root={d} path={s}", .{
                path.id,
                path.root_id,
                path.path,
            });
            if (path.parent_path_id) |parent_id| {
                try self.out.writer(self.allocator).print(" parent={d}", .{parent_id});
            }
            try self.out.appendSlice(self.allocator, "\n");
        }
    }

    fn writeRegion(self: *Formatter, indent: usize, kind: []const u8, ref_id: usize, expr: []const u8, loop_locals: []const []const u8) !void {
        var deps = DepList{};
        defer deps.deinit(self.allocator);
        try self.collectExpressionDeps(expr, loop_locals, &deps);
        var tracked_path_ids = std.ArrayList(usize){};
        defer tracked_path_ids.deinit(self.allocator);
        try self.collectTrackedPathIds(expr, &tracked_path_ids);
        try self.writeRegionLine(indent, kind, ref_id, null, expr, deps.items.items, tracked_path_ids.items);
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
        var tracked_path_ids = std.ArrayList(usize){};
        defer tracked_path_ids.deinit(self.allocator);
        try self.collectTrackedPathIds(expr, &tracked_path_ids);
        try self.writeRegionLine(indent, kind, ref_id, name, expr, deps.items.items, tracked_path_ids.items);
    }

    fn writeRegionLine(
        self: *Formatter,
        indent: usize,
        kind: []const u8,
        ref_id: usize,
        name: ?[]const u8,
        expr: ?[]const u8,
        deps: []const []const u8,
        tracked_path_ids: []const usize,
    ) !void {
        const id = self.next_region_id;
        self.next_region_id += 1;

        try self.writeIndent(indent);
        try self.out.writer(self.allocator).print("#{d} {s} ref={d}", .{ id, kind, ref_id });
        if (name) |value| try self.out.writer(self.allocator).print(" name={s}", .{value});
        if (expr) |value| {
            try self.out.writer(self.allocator).print(" expr={s}", .{value});
            const compiled_direct = expressionCompilesDirect(value);
            try self.out.writer(self.allocator).print(" eval={s}", .{
                if (compiled_direct) "direct" else "fallback",
            });
            if (!compiled_direct) {
                try self.out.writer(self.allocator).print(" reason={s}", .{classifyEvaluateFallback(value)});
                try self.diagnostics.append(self.allocator, .{
                    .severity = .info,
                    .kind = .runtime_evaluate_fallback,
                    .subject = value,
                });
            }
        }
        try self.out.appendSlice(self.allocator, " deps=[");
        for (deps, 0..) |dep, idx| {
            if (idx > 0) try self.out.appendSlice(self.allocator, ",");
            try self.out.appendSlice(self.allocator, dep);
        }
        try self.out.appendSlice(self.allocator, "]");
        if (tracked_path_ids.len > 0) {
            try self.out.appendSlice(self.allocator, " tracked_paths=[");
            for (tracked_path_ids, 0..) |path_id, idx| {
                if (idx > 0) try self.out.appendSlice(self.allocator, ",");
                try self.out.writer(self.allocator).print("{d}", .{path_id});
            }
            try self.out.appendSlice(self.allocator, "]");
        }
        try self.out.appendSlice(self.allocator, "\n");
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

    fn collectExpressionDeps(self: *Formatter, expr: []const u8, loop_locals: []const []const u8, deps: *DepList) anyerror!void {
        try self.collectExpressionDepsWithTrail(expr, loop_locals, deps, &.{});
    }

    fn collectExpressionDepsWithTrail(
        self: *Formatter,
        expr: []const u8,
        loop_locals: []const []const u8,
        deps: *DepList,
        call_trail: []const []const u8,
    ) anyerror!void {
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
            if (call and tracked_root.isImportedBinding(self.component, ident)) continue;

            if (call) {
                if (self.findVisibleBinding(ident)) |binding| {
                    try deps.appendUnique(self.allocator, ident);
                    if (binding.callable and !containsName(call_trail, ident)) {
                        if (self.findHelperRecord(binding.name)) |helper| {
                            if (helper.contains_external_reads) {
                                try self.diagnostics.append(self.allocator, .{
                                    .severity = .warning,
                                    .kind = .hidden_state,
                                    .subject = expr,
                                    .reason = "helper-contains-external-reads",
                                });
                            } else if (helper.contains_side_effects) {
                                try self.diagnostics.append(self.allocator, .{
                                    .severity = .warning,
                                    .kind = .hidden_state,
                                    .subject = expr,
                                    .reason = "helper-contains-side-effects",
                                });
                            }
                        }
                        try self.collectCallableBindingDeps(binding, deps, call_trail);
                    }
                    continue;
                }
            }

            if (self.isVisibleBinding(ident) or containsName(loop_locals, ident)) {
                try deps.appendUnique(self.allocator, ident);
            }
        }

        if (deps.items.items.len == 0 and saw_call) {
            try self.diagnostics.append(self.allocator, .{
                .severity = .warning,
                .kind = .hidden_state,
                .subject = expr,
                .reason = "no-visible-component-dependency",
            });
        }
    }

    fn collectTrackedPathIds(self: *Formatter, expr: []const u8, path_ids: *std.ArrayList(usize)) !void {
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
            if (isPropertyAccess(expr, root_start)) continue;
            if (tracked_root.kindByName(self.component, root_name) == null) continue;

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

            const full_path = std.mem.trimRight(u8, expr[root_start..leaf_end], " \t\r\n");
            const leaf_path_id = try self.ensureTrackedPathChain(full_path);
            try appendUniqueUsize(self.allocator, path_ids, leaf_path_id);
        }
    }

    fn ensureTrackedRoot(self: *Formatter, binding_name: []const u8, kind: []const u8) !usize {
        for (self.tracked_roots.items) |root| {
            if (std.mem.eql(u8, root.binding_name, binding_name)) return root.id;
        }

        const id = self.tracked_roots.items.len + 1;
        try self.tracked_roots.append(self.allocator, .{
            .id = id,
            .binding_name = try self.allocator.dupe(u8, binding_name),
            .kind = try self.allocator.dupe(u8, kind),
        });
        return id;
    }

    fn findTrackedPathId(self: *const Formatter, path: []const u8) ?usize {
        for (self.tracked_paths.items) |tracked_path| {
            if (std.mem.eql(u8, tracked_path.path, path)) return tracked_path.id;
        }
        return null;
    }

    fn findTrackedRoot(self: *const Formatter, binding_name: []const u8) ?TrackedRoot {
        for (self.tracked_roots.items) |root| {
            if (std.mem.eql(u8, root.binding_name, binding_name)) return root;
        }
        return null;
    }

    fn ensureTrackedPathChain(self: *Formatter, full_path: []const u8) !usize {
        if (self.findTrackedPathId(full_path)) |existing| return existing;

        const first_dot = std.mem.indexOfScalar(u8, full_path, '.') orelse return error.InvalidTrackedPath;
        const root_name = full_path[0..first_dot];
        const kind = tracked_root.kindByName(self.component, root_name) orelse return error.InvalidTrackedPath;
        const root_id = try self.ensureTrackedRoot(root_name, kind.label());

        var parent_path_id: ?usize = null;
        var search_from: usize = 0;
        while (true) {
            const maybe_dot = std.mem.indexOfScalarPos(u8, full_path, search_from, '.');
            const end_index = maybe_dot orelse full_path.len;
            const prefix = full_path[0..end_index];

            const path_id = if (self.findTrackedPathId(prefix)) |existing|
                existing
            else blk: {
                const new_id = self.tracked_paths.items.len + 1;
                try self.tracked_paths.append(self.allocator, .{
                    .id = new_id,
                    .root_id = root_id,
                    .path = try self.allocator.dupe(u8, prefix),
                    .parent_path_id = parent_path_id,
                });
                break :blk new_id;
            };

            parent_path_id = path_id;
            if (maybe_dot == null) return path_id;
            search_from = end_index + 1;
        }
    }

    fn isVisibleBinding(self: *const Formatter, name: []const u8) bool {
        return self.findVisibleBinding(name) != null;
    }

    fn findVisibleBinding(self: *const Formatter, name: []const u8) ?script_analysis.BindingRecord {
        for (self.component.script.bindings) |binding| {
            if (binding.template_visible and std.mem.eql(u8, binding.name, name)) return binding;
        }
        return null;
    }

    fn collectCallableBindingDeps(
        self: *Formatter,
        binding: script_analysis.BindingRecord,
        deps: *DepList,
        call_trail: []const []const u8,
    ) anyerror!void {
        const helper = self.findHelperRecord(binding.name) orelse return;

        var next_trail = std.ArrayList([]const u8){};
        defer next_trail.deinit(self.allocator);
        try next_trail.appendSlice(self.allocator, call_trail);
        try next_trail.append(self.allocator, binding.name);

        for (helper.reads) |name| {
            try deps.appendUnique(self.allocator, name);
        }

        for (helper.calls) |name| {
            try deps.appendUnique(self.allocator, name);
            if (containsName(next_trail.items, name)) continue;
            if (self.findVisibleBinding(name)) |next_binding| {
                if (next_binding.callable) {
                    try self.collectCallableBindingDeps(next_binding, deps, next_trail.items);
                }
            }
        }
    }

    fn findHelperRecord(self: *const Formatter, name: []const u8) ?script_analysis.HelperRecord {
        for (self.component.script.state_analysis.helpers) |helper| {
            if (std.mem.eql(u8, helper.name, name)) return helper;
        }
        return null;
    }

    fn findAliasTarget(self: *const Formatter, alias_name: []const u8) ?[]const u8 {
        for (self.component.script.state_analysis.aliases) |alias| {
            if (std.mem.eql(u8, alias.alias, alias_name)) return alias.target;
        }
        return null;
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

fn nextNonSpaceIndex(expr: []const u8, idx: usize) ?usize {
    var cursor = idx;
    while (cursor < expr.len) : (cursor += 1) {
        if (isWhitespace(expr[cursor])) continue;
        return cursor;
    }
    return null;
}

fn isLikelyCallEscape(script: []const u8, match_index: usize) bool {
    if (match_index == 0) return false;

    var cursor = match_index;
    while (cursor > 0) {
        cursor -= 1;
        if (isWhitespace(script[cursor])) continue;

        if (script[cursor] == ',') return true;
        if (script[cursor] != '(') return false;
        if (cursor == 0) return false;

        var head = cursor;
        while (head > 0) {
            head -= 1;
            if (isWhitespace(script[head])) continue;
            break;
        }

        if (!isIdentContinue(script[head]) and script[head] != ')') return false;
        if (script[head] == ')') return true;

        var word_start = head;
        while (word_start > 0 and isIdentContinue(script[word_start - 1])) word_start -= 1;
        const callee = script[word_start .. head + 1];
        if (std.mem.eql(u8, callee, "if") or
            std.mem.eql(u8, callee, "for") or
            std.mem.eql(u8, callee, "while") or
            std.mem.eql(u8, callee, "switch"))
        {
            return false;
        }
        return true;
    }

    return false;
}

fn appendUniqueUsize(allocator: std.mem.Allocator, list: *std.ArrayList(usize), value: usize) !void {
    for (list.items) |item| {
        if (item == value) return;
    }
    try list.append(allocator, value);
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

fn consumeIdentifierSlice(source: []const u8, cursor: *usize) bool {
    if (cursor.* >= source.len or !isIdentStart(source[cursor.*])) return false;
    cursor.* += 1;
    while (cursor.* < source.len and isIdentContinue(source[cursor.*])) cursor.* += 1;
    return true;
}

fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t';
}

fn expressionCompilesDirect(expression: []const u8) bool {
    const trimmed = std.mem.trim(u8, expression, &std.ascii.whitespace);
    if (trimmed.len == 0) return true;
    if (isLiteralExpression(trimmed)) return true;
    if (isSimpleAccessExpression(trimmed)) return true;
    if (canRewriteScopedCallExpression(trimmed)) return true;
    return canRewriteScopedExpression(trimmed);
}

fn classifyEvaluateFallback(expression: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, expression, &std.ascii.whitespace);
    if (std.mem.indexOf(u8, trimmed, "=>") != null) return "callback-argument";
    if (std.mem.indexOfScalar(u8, trimmed, '(') != null) return "dynamic-call-arguments";
    return "complex-expression";
}

fn severityLabel(severity: DiagnosticSeverity) []const u8 {
    return switch (severity) {
        .warning => "warning",
        .info => "info",
    };
}

fn canRewriteScopedCallExpression(expression: []const u8) bool {
    const open_paren = std.mem.indexOfScalar(u8, expression, '(') orelse return false;
    const callee = std.mem.trimRight(u8, expression[0..open_paren], &std.ascii.whitespace);
    if (callee.len == 0 or !isSimpleAccessExpression(callee)) return false;

    const close_paren = findMatchingParenForward(expression, open_paren) orelse return false;
    const suffix = std.mem.trim(u8, expression[close_paren + 1 ..], &std.ascii.whitespace);
    if (suffix.len != 0 and !isSimpleCallSuffixExpression(suffix)) return false;

    var args = std.ArrayList([]const u8){};
    defer args.deinit(std.heap.page_allocator);
    splitCallArguments(expression[open_paren + 1 .. close_paren], &args) catch return false;
    for (args.items) |arg| {
        const trimmed_arg = std.mem.trim(u8, arg, &std.ascii.whitespace);
        if (trimmed_arg.len == 0) continue;
        if (canRewriteArrowCallbackExpression(trimmed_arg)) continue;
        if (!canRewriteScopedExpression(trimmed_arg)) return false;
    }
    return true;
}

fn canRewriteScopedExpression(expression: []const u8) bool {
    return canRewriteScopedExpressionWithLocals(expression, &.{});
}

fn canRewriteScopedExpressionWithLocals(expression: []const u8, locals: []const []const u8) bool {
    var cursor: usize = 0;
    while (cursor < expression.len) {
        const ch = expression[cursor];
        if (isWhitespace(ch)) {
            cursor += 1;
            continue;
        }
        if (ch == '\'' or ch == '"') {
            cursor = scanQuotedString(expression, cursor) orelse return false;
            cursor += 1;
            continue;
        }
        if (isIdentStart(ch)) {
            const start = cursor;
            cursor += 1;
            while (cursor < expression.len and isIdentContinue(expression[cursor])) cursor += 1;
            const ident = expression[start..cursor];
            if (nextNonSpaceIs(expression, cursor, '(')) return false;
            if (isKeyword(ident) or containsName(locals, ident) or isPropertyAccess(expression, start)) continue;
            continue;
        }
        if (std.ascii.isDigit(ch)) {
            cursor += 1;
            while (cursor < expression.len and (std.ascii.isDigit(expression[cursor]) or expression[cursor] == '.')) cursor += 1;
            continue;
        }
        if (isSupportedExpressionPunctuation(ch)) {
            cursor += 1;
            continue;
        }
        return false;
    }
    return true;
}

fn canRewriteArrowCallbackExpression(expression: []const u8) bool {
    const arrow = std.mem.indexOf(u8, expression, "=>") orelse return false;
    const params_expr = std.mem.trim(u8, expression[0..arrow], &std.ascii.whitespace);
    const raw_body_expr = std.mem.trim(u8, expression[arrow + 2 ..], &std.ascii.whitespace);
    const body_expr = extractArrowCallbackReturnExpression(raw_body_expr) orelse return false;
    if (params_expr.len == 0 or body_expr.len == 0) return false;

    const param = parseArrowCallbackParam(params_expr) orelse return false;
    const locals = [_][]const u8{param};
    return canRewriteScopedExpressionWithLocals(body_expr, &locals);
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

fn splitCallArguments(source: []const u8, out: *std.ArrayList([]const u8)) !void {
    var start: usize = 0;
    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_brace: usize = 0;
    var cursor: usize = 0;
    while (cursor < source.len) : (cursor += 1) {
        const ch = source[cursor];
        if (ch == '\'' or ch == '"') {
            cursor = scanQuotedString(source, cursor) orelse return error.InvalidCharacter;
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
                    try out.append(std.heap.page_allocator, source[start..cursor]);
                    start = cursor + 1;
                }
            },
            else => {},
        }
    }
    try out.append(std.heap.page_allocator, source[start..]);
}

fn findMatchingParenForward(source: []const u8, open_paren: usize) ?usize {
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
