const std = @import("std");
const sokol_build = @import("sokol");

// helper function to build a LazyPath from the emsdk root and provided path components
fn emSdkLazyPath(b: *std.Build, emsdk: *std.Build.Dependency, subPaths: []const []const u8) std.Build.LazyPath {
    return emsdk.path(b.pathJoin(subPaths));
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const sokol_mod = sokol_dep.module("sokol");

    const name = "wgui";
    const root_source_file = b.path("src/main.zig");

    var run: ?*std.Build.Step.Run = null;
    if (!target.result.isWasm()) {
        // for native platforms, build into a regular executable
        const example = b.addExecutable(.{
            .name = name,
            .root_source_file = root_source_file,
            .target = target,
            .optimize = optimize,
        });
        example.addIncludePath(sokol_dep.path("src/sokol/c"));
        example.addIncludePath(sokol_dep.path("src/cimgui/"));
        example.root_module.addImport("sokol", sokol_mod);
        b.installArtifact(example);
        run = b.addRunArtifact(example);
    } else {
        // for WASM, need to build the Zig code as static library, since linking happens via emcc
        const emsdk = sokol_dep.builder.dependency("emsdk", .{});

        const example = b.addStaticLibrary(.{
            .name = name,
            .root_source_file = root_source_file,
            .target = target,
            .optimize = optimize,
        });
        example.addIncludePath(sokol_dep.path("src/sokol/c"));
        example.addIncludePath(sokol_dep.path("src/cimgui/"));
        example.root_module.addImport("sokol", sokol_mod);

        example.addSystemIncludePath(emSdkLazyPath(b, emsdk, &.{
            "upstream",
            "emscripten",
            "cache",
            "sysroot",
            "include",
        }));

        const shell_path = sokol_dep.path("src/sokol/web/shell.html").getPath(sokol_dep.builder);
        const backend = sokol_build.resolveSokolBackend(
            .auto,
            target.result,
        );

        const link_step = try sokol_build.emLinkStep(b, .{
            .lib_main = example,
            .target = target,
            .optimize = optimize,
            .emsdk = emsdk,
            .use_webgpu = backend == .wgpu,
            .use_webgl2 = backend != .wgpu,
            .use_emmalloc = true,
            .use_filesystem = false,
            // NOTE: when sokol-zig is used as package, this path needs to be absolute!
            .shell_file_path = shell_path,
        });
        // ...and a special run step to run the build result via emrun
        run = sokol_build.emRunStep(b, .{ .name = name, .emsdk = emsdk });
        run.?.step.dependOn(&link_step.step);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run.?.step);
}
