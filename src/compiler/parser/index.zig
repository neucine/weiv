pub const ast = @import("ast.zig");
pub const sfc = @import("sfc.zig");
pub const template = @import("template/index.zig");

pub const SfcDocument = ast.SfcDocument;
pub const TemplateDocument = ast.TemplateDocument;
pub const NormalizedTemplate = ast.NormalizedTemplateDocument;

pub const parseSfc = sfc.parse;
pub const parseTemplate = template.parse;
pub const normalizeTemplate = template.normalize;
