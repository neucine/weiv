const std = @import("std");
const binding = @import("../analyze/binder.zig");
const ir = @import("ir.zig");
const template = @import("../parse/template.zig");

pub fn lower(
    normalized_template: *const template.NormalizedDocument,
    binding_result: *const binding.BindingResult,
    allocator: std.mem.Allocator,
) anyerror!ir.Document {
    _ = binding_result;
    return .{
        .nodes = try lowerNodes(normalized_template.nodes, allocator),
    };
}

fn lowerNodes(nodes: []const template.NormalizedNode, allocator: std.mem.Allocator) anyerror![]ir.Node {
    var out = std.ArrayList(ir.Node){};
    defer out.deinit(allocator);

    for (nodes) |node| {
        try out.append(allocator, try lowerNode(node, allocator));
    }

    return try out.toOwnedSlice(allocator);
}

fn lowerNode(node: template.NormalizedNode, allocator: std.mem.Allocator) anyerror!ir.Node {
    return switch (node) {
        .text => |text| .{
            .text = .{ .content = text.content },
        },
        .interpolation => |interp| .{
            .interpolation = .{ .expression = interp.expression },
        },
        .conditional => |conditional| .{
            .conditional = .{
                .condition = conditional.condition,
                .consequent = try lowerNodes(conditional.consequent, allocator),
                .alternate = try lowerNodes(conditional.alternate, allocator),
            },
        },
        .for_loop => |for_loop| .{
            .for_loop = .{
                .item_name = for_loop.item_name,
                .iterable_expr = for_loop.iterable_expr,
                .body = try lowerNodes(for_loop.body, allocator),
            },
        },
        .element => |element| blk: {
            const effects = try lowerEffects(element.directives, allocator);
            errdefer allocator.free(effects);
            if (isComponentTag(element.tag_name)) {
                break :blk .{
                    .component = .{
                        .tag_name = element.tag_name,
                        .effects = effects,
                    },
                };
            }

            const attributes = try lowerAttributes(element.attributes, allocator);
            errdefer allocator.free(attributes);
            const children = try lowerNodes(element.children, allocator);
            errdefer {
                for (children) |*child| child.deinit(allocator);
                allocator.free(children);
            }
            break :blk .{
                .element = .{
                    .tag_name = element.tag_name,
                    .attributes = attributes,
                    .effects = effects,
                    .children = children,
                },
            };
        },
    };
}

fn lowerEffects(directives: []const template.Directive, allocator: std.mem.Allocator) anyerror![]ir.DirectiveEffect {
    var out = std.ArrayList(ir.DirectiveEffect){};
    defer out.deinit(allocator);

    for (directives) |directive| {
        switch (directive) {
            .bind => |bind_dir| try out.append(allocator, .{
                .bind = .{
                    .target_name = bind_dir.target_name,
                    .expression = bind_dir.expression,
                },
            }),
            .event => |event_dir| try out.append(allocator, .{
                .event = .{
                    .event_name = event_dir.event_name,
                    .expression = event_dir.expression,
                },
            }),
            .if_expr, .else_branch, .for_expr => unreachable,
        }
    }

    return try out.toOwnedSlice(allocator);
}

fn lowerAttributes(
    attributes: []const template.Attribute,
    allocator: std.mem.Allocator,
) anyerror![]ir.Attribute {
    var out = try allocator.alloc(ir.Attribute, attributes.len);
    for (attributes, 0..) |attribute, idx| {
        out[idx] = .{
            .name = attribute.name,
            .value = attribute.value,
        };
    }
    return out;
}

fn isComponentTag(tag_name: []const u8) bool {
    if (tag_name.len == 0) return false;
    return std.ascii.isUpper(tag_name[0]);
}
