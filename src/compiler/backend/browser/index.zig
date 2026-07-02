pub const component = @import("component.zig");
pub const emit = @import("emit/index.zig");
pub const render_tree = @import("render_tree/index.zig");

pub const AppValidationReport = emit.AppValidationReport;
pub const RenderTree = render_tree.Document;

pub const emitApp = emit.emitApp;
pub const validateApp = emit.validateApp;
pub const emitJsModule = emit.emitJsModule;
pub const emitScopedCss = emit.emitScopedCss;
