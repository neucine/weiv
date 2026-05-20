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
    if (target.result.os.tag == .windows) {
        exe.bundle_compiler_rt = false;
    }

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
    if (target.result.os.tag == .windows) {
        tests.bundle_compiler_rt = false;
    }
    if (target.result.os.tag == .macos) {
        tests.linkFramework("CoreFoundation");
        tests.linkFramework("Security");
        tests.linkSystemLibrary("iconv");
    }
    tests.step.dependOn(&build_parser_backend.step);

    const test_step = b.step("test", "Run compiler e2e tests");
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const component_check = b.addSystemCommand(&.{
        "bun",
        "test",
        "test/component",
    });
    component_check.setCwd(b.path("."));
    component_check.step.dependOn(&build_parser_backend.step);

    const component_test_step = b.step("component-test", "Run emitted component tests with Bun");
    component_test_step.dependOn(&component_check.step);

    const render_test_step = b.step("render-test", "Compatibility alias for component-test");
    render_test_step.dependOn(&component_check.step);

    const runtime_check = b.addSystemCommand(&.{
        "bun",
        "test",
        "test/runtime",
    });
    runtime_check.setCwd(b.path("."));
    runtime_check.step.dependOn(&build_parser_backend.step);

    const runtime_test_step = b.step("runtime-test", "Run observable runtime tests with Bun");
    runtime_test_step.dependOn(&runtime_check.step);

    const cypress_direct = b.addSystemCommand(&.{
        "bun",
        "test",
        "test/cypress/run_direct.ts",
    });
    cypress_direct.setCwd(b.path("."));
    cypress_direct.step.dependOn(&build_parser_backend.step);

    const cypress_slots = b.addSystemCommand(&.{
        "bun",
        "test",
        "test/cypress/run_slots.ts",
    });
    cypress_slots.setCwd(b.path("."));
    cypress_slots.step.dependOn(&build_parser_backend.step);

    const cypress_test_step = b.step("cypress-test", "Run Cypress E2E tests (starts dev server, requires browser)");
    cypress_test_step.dependOn(&cypress_direct.step);
    cypress_test_step.dependOn(&cypress_slots.step);

    const test_all_step = b.step("test-all", "Run all tests except Cypress (e2e + component + runtime)");
    test_all_step.dependOn(&run_tests.step);
    test_all_step.dependOn(&component_check.step);
    test_all_step.dependOn(&runtime_check.step);
}
