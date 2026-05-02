const std = @import("std");
const ast = @import("ast.zig");
const directives = @import("directives.zig");
const normalized = @import("normalized.zig");
const sfc = @import("../sfc.zig");

pub fn findFirstInvalidLoweringSpan(
    nodes: []const normalized.Node,
    err: anyerror,
) ?sfc.Span {
    return findInvalidSpan(nodes, err, false);
}

pub fn findFirstInvalidNormalizeSpan(
    nodes: []const ast.Node,
    err: anyerror,
) ?sfc.Span {
    return findInvalidNormalizeSpanInNodes(nodes, err);
}

fn findInvalidSpan(
    nodes: []const normalized.Node,
    err: anyerror,
    allow_direct_slot_assignment: bool,
) ?sfc.Span {
    for (nodes) |node| {
        switch (node) {
            .element => |element| {
                if (std.mem.eql(u8, element.tag_name, "template")) {
                    if (!allow_direct_slot_assignment or findSlotAssign(element.directives) == null) {
                        if (err == error.InvalidSlotTemplatePlacement) return element.span;
                    }
                    if (findInvalidSpan(element.children, err, false)) |span| return span;
                    continue;
                }

                if (!allow_direct_slot_assignment and findSlotAssign(element.directives) != null) {
                    if (err == error.InvalidSlotPlacement) return element.span;
                }

                const child_allows_direct_slot_assignment = !allow_direct_slot_assignment and isComponentTag(element.tag_name);
                if (findInvalidSpan(element.children, err, child_allows_direct_slot_assignment)) |span| return span;
            },
            .conditional => |conditional| {
                if (findInvalidSpan(conditional.consequent, err, false)) |span| return span;
                if (findInvalidSpan(conditional.alternate, err, false)) |span| return span;
            },
            .for_loop => |for_loop| {
                if (findInvalidSpan(for_loop.body, err, false)) |span| return span;
            },
            .slot_outlet => |slot_outlet| {
                if (findInvalidSpan(slot_outlet.fallback_children, err, false)) |span| return span;
            },
            .text, .interpolation => {},
        }
    }

    return null;
}

fn findInvalidNormalizeSpanInNodes(nodes: []const ast.Node, err: anyerror) ?sfc.Span {
    if (err != error.UnexpectedElse) return null;

    var i: usize = 0;
    while (i < nodes.len) : (i += 1) {
        switch (nodes[i]) {
            .element => |element| {
                if (hasElseDirective(element.directives) and !previousSiblingHasIf(nodes, i)) {
                    return element.span;
                }
                if (findInvalidNormalizeSpanInNodes(element.children, err)) |span| return span;
            },
            .slot_outlet => |slot_outlet| {
                if (findInvalidNormalizeSpanInNodes(slot_outlet.fallback_children, err)) |span| return span;
            },
            .text, .interpolation => {},
        }
    }

    return null;
}

fn findSlotAssign(input: []const directives.Directive) ?[]const u8 {
    for (input) |directive| {
        switch (directive) {
            .slot_assign => |slot_assign| return slot_assign.slot_name,
            else => {},
        }
    }
    return null;
}

fn isComponentTag(tag_name: []const u8) bool {
    if (tag_name.len == 0) return false;
    return std.ascii.isUpper(tag_name[0]);
}

fn hasElseDirective(input: []const directives.Directive) bool {
    for (input) |directive| {
        switch (directive) {
            .else_branch => return true,
            else => {},
        }
    }
    return false;
}

fn previousSiblingHasIf(nodes: []const ast.Node, index: usize) bool {
    if (index == 0) return false;
    switch (nodes[index - 1]) {
        .element => |element| {
            for (element.directives) |directive| {
                switch (directive) {
                    .if_expr => return true,
                    else => {},
                }
            }
            return false;
        },
        else => return false,
    }
}
