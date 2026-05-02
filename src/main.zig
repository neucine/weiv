const std = @import("std");
const cli = @import("cli.zig");

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    cli.run(allocator) catch |err| {
        if (err == error.Reported) {
            std.process.exit(1);
        }
        cli.printUnhandledError(err) catch {};
        std.process.exit(1);
    };
}
