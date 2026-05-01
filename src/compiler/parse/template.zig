pub const ast = @import("template/ast.zig");
pub const directives = @import("template/directives.zig");
pub const normalized = @import("template/normalized.zig");
pub const normalize_mod = @import("template/normalize.zig");
pub const parser = @import("template/parser.zig");

pub const NodeTag = ast.NodeTag;
pub const Attribute = ast.Attribute;
pub const ElementNode = ast.ElementNode;
pub const TextNode = ast.TextNode;
pub const InterpolationNode = ast.InterpolationNode;
pub const Node = ast.Node;
pub const Document = ast.Document;
pub const NormalizedNodeTag = normalized.NodeTag;
pub const NormalizedNode = normalized.Node;
pub const NormalizedDocument = normalized.Document;
pub const DirectiveTag = directives.DirectiveTag;
pub const Directive = directives.Directive;
pub const IfDirective = directives.IfDirective;
pub const ElseDirective = directives.ElseDirective;
pub const ForDirective = directives.ForDirective;
pub const EventDirective = directives.EventDirective;
pub const BindDirective = directives.BindDirective;
pub const ParseError = parser.ParseError;
pub const NormalizeError = normalize_mod.NormalizeError;

pub const parse = parser.parse;
pub const normalize = normalize_mod.normalize;
