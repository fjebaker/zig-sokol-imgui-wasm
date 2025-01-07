const std = @import("std");
const sokol_build = @import("sokol");

// helper function to build a LazyPath from the emsdk root and provided path components
fn emSdkLazyPath(b: *std.Build, emsdk: *std.Build.Dependency) std.Build.LazyPath {
    return emsdk.path(b.pathJoin(
        &.{
            "upstream",
            "emscripten",
            "cache",
            "sysroot",
            "include",
        },
    ));
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const backend = sokol_build.resolveSokolBackend(
        .auto,
        target.result,
    );
    const backend_cflags = switch (backend) {
        .d3d11 => "-DSOKOL_D3D11",
        .metal => "-DSOKOL_METAL",
        .gl => "-DSOKOL_GLCORE",
        .gles3 => "-DSOKOL_GLES3",
        .wgpu => "-DSOKOL_WGPU",
        else => @panic("unknown sokol backend"),
    };

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const sokol_mod = sokol_dep.module("sokol");

    const imgui_dep = b.dependency("zig_imgui", .{
        .target = target,
        .optimize = optimize,
    });
    const imgui_include = imgui_dep.path("src");
    const imgui_lib = imgui_dep.artifact("imgui");
    const implot_lib = imgui_dep.artifact("implot");

    const name = "wgui";
    const root_source_file = b.path("src/main.zig");

    // module to be used by downstream projects
    const mod = b.addModule("zig-sokol-imgui-implot", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });
    mod.addIncludePath(sokol_dep.path("src/sokol/c"));
    mod.addIncludePath(imgui_include);
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFile(
        .{ .file = b.path("src/sokol_imgui.c"), .flags = &.{
            "-DSOKOL_IMGUI_IMPL",
            backend_cflags,
        } },
    );
    mod.linkLibrary(imgui_lib);
    mod.linkLibrary(implot_lib);
    mod.addImport("sokol", sokol_mod);

    var run: ?*std.Build.Step.Run = null;
    if (!target.result.isWasm()) {
        // for native platforms, build into a regular executable
        const example = b.addExecutable(.{
            .name = name,
            .root_source_file = root_source_file,
            .target = target,
            .optimize = optimize,
        });
        example.root_module.addImport("imzokol", mod);

        const install = b.addInstallArtifact(example, .{});
        run = b.addRunArtifact(example);
        run.?.step.dependOn(&install.step);
    } else {
        // for WASM, need to build the Zig code as static library, since
        // linking happens via emcc
        const emsdk = sokol_dep.builder.dependency("emsdk", .{});

        const example = b.addStaticLibrary(.{
            .name = name,
            .root_source_file = root_source_file,
            .target = target,
            .optimize = optimize,
        });

        imgui_lib.addSystemIncludePath(emSdkLazyPath(b, emsdk));
        implot_lib.addSystemIncludePath(emSdkLazyPath(b, emsdk));
        mod.addSystemIncludePath(emSdkLazyPath(b, emsdk));

        example.root_module.addImport("imzokol", mod);

        const shell_path = sokol_dep.path(
            "src/sokol/web/shell.html",
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
