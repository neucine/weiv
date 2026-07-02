const std = @import("std");
const cli = @import("cli.zig");

pub fn main(init: std.process.Init) void {
    const allocator = init.gpa;
    cli.run(allocator, init.io, init.minimal.args, init.environ_map) catch |err| {
        if (err == error.Reported) {
            std.process.exit(1);
        }
        cli.printUnhandledError(err) catch {};
        std.process.exit(1);
    };
}
