pub const binder = @import("binder.zig");
pub const script_facts = @import("script_facts.zig");
pub const sir = @import("sir.zig");
pub const slot_manifest = @import("slot_manifest.zig");
pub const tracked_root = @import("tracked_root.zig");

pub const TemplateBindings = sir.TemplateBindings;
pub const ScriptFacts = sir.ScriptFacts;

pub const bind = binder.bind;
