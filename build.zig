const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zlexer_dep = b.dependency("zlexer", .{ .target = target, .optimize = optimize });
    const zlexer_module = zlexer_dep.module("zlexer");

    const zparser_dep = b.dependency("zparser", .{ .target = target, .optimize = optimize });
    const zparser_module = zparser_dep.module("zparser");

    const zstatements_module = b.addModule("zstatements", .{
        .root_source_file = b.path("src/zstatements.zig"),
    });
    zstatements_module.addImport("zparser", zparser_module);
    zstatements_module.addImport("zlexer", zlexer_module);

    const test_step = b.step("test", "Run all tests");

    const test_files = [_][]const u8{
        "tests/block_test.zig",
        "tests/variable_test.zig",
        "tests/destructuring_test.zig",
        "tests/if_test.zig",
        "tests/loop_test.zig",
        "tests/break_continue_test.zig",
        "tests/labelled_test.zig",
        "tests/try_switch_test.zig",
        "tests/asi_test.zig",
        "tests/misc_test.zig",
    };

    inline for (test_files) |test_file| {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
            }),
        });

        unit_tests.root_module.addImport("zstatements", zstatements_module);
        unit_tests.root_module.addImport("zparser", zparser_module);
        unit_tests.root_module.addImport("zlexer", zlexer_module);

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    const src_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zstatements.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    src_tests.root_module.addImport("zparser", zparser_module);
    src_tests.root_module.addImport("zlexer", zlexer_module);
    const run_src_tests = b.addRunArtifact(src_tests);
    test_step.dependOn(&run_src_tests.step);

    b.default_step = test_step;
}
