const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "weiv",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkLibC();
    exe.addLibraryPath(b.path("libs/parser-backend/target/release"));
    exe.linkSystemLibrary("weiv_parser_backend");

    if (target.result.os.tag == .macos) {
        exe.linkFramework("CoreFoundation");
        exe.linkFramework("Security");
        exe.linkSystemLibrary("iconv");
    }

    const build_parser_backend = b.addSystemCommand(&.{
        "cargo",
        "build",
        "--release",
        "--quiet",
    });
    build_parser_backend.setCwd(b.path("libs/parser-backend"));

    exe.step.dependOn(&build_parser_backend.step);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the weiv CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.linkLibC();
    tests.addLibraryPath(b.path("libs/parser-backend/target/release"));
    tests.linkSystemLibrary("weiv_parser_backend");
    if (target.result.os.tag == .macos) {
        tests.linkFramework("CoreFoundation");
        tests.linkFramework("Security");
        tests.linkSystemLibrary("iconv");
    }
    tests.step.dependOn(&build_parser_backend.step);

    const test_step = b.step("test", "Run compiler e2e tests");
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const render_check = b.addSystemCommand(&.{
        "bun",
        "test",
        "test/render/render_check.test.ts",
    });
    render_check.setCwd(b.path("."));
    render_check.step.dependOn(&build_parser_backend.step);

    const render_test_step = b.step("render-test", "Run render module verification with Bun");
    render_test_step.dependOn(&render_check.step);
}
