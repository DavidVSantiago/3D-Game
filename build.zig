const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Traduz os cabeçalhos C da Raylib (raylib.h, rlgl.h, raymath.h) para Zig
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c_headers.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(b.path("vendor/raylib/src"));
    const raylib_c_mod = translate_c.createModule();

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "raylib_c", .module = raylib_c_mod },
        },
    });

    // Inclui os cabeçalhos da Raylib 5.5 e GLFW embutido
    exe_mod.addIncludePath(b.path("vendor/raylib/src"));
    exe_mod.addIncludePath(b.path("vendor/raylib/src/external/glfw/include"));

    const os_tag = target.result.os.tag;

    if (os_tag == .macos) {
        exe_mod.addCSourceFiles(.{
            .root = b.path("vendor/raylib/src"),
            .files = &.{
                "rcore.c",
                "rshapes.c",
                "rtextures.c",
                "rtext.c",
                "rmodels.c",
                "utils.c",
                "raudio.c",
            },
            .flags = &.{
                "-std=gnu99",
                "-DPLATFORM_DESKTOP",
                "-DGRAPHICS_API_OPENGL_33",
                "-fno-sanitize=undefined",
            },
        });
        exe_mod.addCSourceFiles(.{
            .root = b.path("vendor/raylib/src"),
            .files = &.{"rglfw.c"},
            .flags = &.{
                "-DPLATFORM_DESKTOP",
                "-DGRAPHICS_API_OPENGL_33",
                "-fno-sanitize=undefined",
            },
            .language = .objective_c,
        });
        exe_mod.linkFramework("OpenGL", .{});
        exe_mod.linkFramework("Cocoa", .{});
        exe_mod.linkFramework("IOKit", .{});
        exe_mod.linkFramework("CoreAudio", .{});
        exe_mod.linkFramework("CoreVideo", .{});
    } else {
        const c_flags: []const []const u8 = if (os_tag == .linux)
            &.{
                "-std=gnu99",
                "-DPLATFORM_DESKTOP",
                "-DGRAPHICS_API_OPENGL_33",
                "-D_GNU_SOURCE",
                "-fno-sanitize=undefined",
            }
        else
            &.{
                "-std=gnu99",
                "-DPLATFORM_DESKTOP",
                "-DGRAPHICS_API_OPENGL_33",
                "-fno-sanitize=undefined",
            };

        exe_mod.addCSourceFiles(.{
            .root = b.path("vendor/raylib/src"),
            .files = &.{
                "rcore.c",
                "rshapes.c",
                "rtextures.c",
                "rtext.c",
                "rmodels.c",
                "utils.c",
                "raudio.c",
                "rglfw.c",
            },
            .flags = c_flags,
        });

        if (os_tag == .windows) {
            exe_mod.addCSourceFiles(.{
                .root = b.path("src"),
                .files = &.{"gpu_optimus.c"},
                .flags = &.{"-std=gnu99"},
            });
            exe_mod.linkSystemLibrary("winmm", .{});
            exe_mod.linkSystemLibrary("gdi32", .{});
            exe_mod.linkSystemLibrary("opengl32", .{});
            exe_mod.linkSystemLibrary("user32", .{});
            exe_mod.linkSystemLibrary("shell32", .{});
        } else if (os_tag == .linux) {
            exe_mod.linkSystemLibrary("GL", .{});
            exe_mod.linkSystemLibrary("m", .{});
            exe_mod.linkSystemLibrary("pthread", .{});
            exe_mod.linkSystemLibrary("dl", .{});
            exe_mod.linkSystemLibrary("rt", .{});
            exe_mod.linkSystemLibrary("X11", .{});
        }
    }

    const exe = b.addExecutable(.{
        .name = "retro_platformer",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the application");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
