const std = @import("std");

const BackendPlatform = enum {
    allegro5,
    glfw,
    glut,
    osx,
    sdl2,
    sdl3,
    win32,

    pub inline fn default(target: std.zig.CrossTarget) BackendPlatform {
        return switch (target.getOs().tag) {
            .linux => .glfw,
            .ios, .macos, .tvos, .watchos => .osx,
            .windows => .win32,
            else => .glfw,
        };
    }

    pub inline fn supportFile(self: BackendPlatform) []const u8 {
        return switch (self) {
            .allegro5 => thisDir() ++ "/backends/imgui_impl_allegro5.cpp",
            .glfw => thisDir() ++ "/backends/imgui_impl_glfw.cpp",
            .glut => thisDir() ++ "/backends/imgui_impl_glut.cpp",
            .osx => thisDir() ++ "/backends/imgui_impl_osx.mm",
            .sdl2 => thisDir() ++ "/backends/imgui_impl_sdl2.cpp",
            .sdl3 => thisDir() ++ "/backends/imgui_impl_sdl3.cpp",
            .win32 => thisDir() ++ "/backends/imgui_impl_win32.cpp",
        };
    }

    pub inline fn linkDependencies(self: BackendPlatform, b: *std.Build, step: *std.Build.CompileStep) void {
        const build_options = .{ .target = step.target, .optimize = step.optimize };
        switch (self) {
            .glfw => {
                const glfw_dep = b.dependency("glfw", build_options);
                step.linkLibrary(glfw_dep.artifact("glfw"));
                step.defineCMacro("GLFW_INCLUDE_NONE", null);
            },
            else => {},
        }
    }
};

const BackendRenderer = enum {
    dx9,
    dx10,
    dx11,
    dx12,
    metal,
    opengl2,
    opengl3,
    sdl2,
    sdl3,
    vulkan,
    wgpu,

    pub inline fn default(target: std.zig.CrossTarget) BackendRenderer {
        return switch (target.getOs().tag) {
            .linux => .opengl3,
            .ios, .macos, .tvos, .watchos => .metal,
            // TODO(Corendos): Make use of directx12-headers if we want to have dx12 by default.
            .windows => .dx11,
            else => .opengl3,
        };
    }

    pub inline fn supportFile(self: BackendRenderer) []const u8 {
        return switch (self) {
            .dx9 => thisDir() ++ "/backends/imgui_impl_dx9.cpp",
            .dx10 => thisDir() ++ "/backends/imgui_impl_dx10.cpp",
            .dx11 => thisDir() ++ "/backends/imgui_impl_dx11.cpp",
            .dx12 => thisDir() ++ "/backends/imgui_impl_dx12.cpp",
            .metal => thisDir() ++ "/backends/imgui_impl_metal.mm",
            .opengl2 => thisDir() ++ "/backends/imgui_impl_opengl2.cpp",
            .opengl3 => thisDir() ++ "/backends/imgui_impl_opengl3.cpp",
            .sdl2 => thisDir() ++ "/backends/imgui_impl_sdlrenderer2.cpp",
            .sdl3 => thisDir() ++ "/backends/imgui_impl_sdlrenderer3.cpp",
            .vulkan => thisDir() ++ "/backends/imgui_impl_vulkan.cpp",
            .wgpu => thisDir() ++ "/backends/imgui_impl_wgpu.cpp",
        };
    }

    pub inline fn linkDependencies(self: BackendRenderer, b: *std.Build, step: *std.Build.CompileStep) void {
        const build_options = .{ .target = step.target, .optimize = step.optimize };
        _ = build_options;

        switch (self) {
            .metal => {
                step.defineCMacro("__kernel_ptr_semantics", "");
                xcode_frameworks.addPaths(b, step);
            },
            else => {},
        }
    }
};

const Backend = struct {
    platform: BackendPlatform,
    renderer: BackendRenderer,

    pub fn from(platform: BackendPlatform, renderer: BackendRenderer) !Backend {
        const b = Backend{
            .platform = platform,
            .renderer = renderer,
        };
        return if (b.check()) b else error.InvalidBackend;
    }

    pub inline fn check(self: Backend) bool {
        _ = self;
        return true;
    }

    pub fn linkDependencies(self: Backend, b: *std.Build, step: *std.Build.CompileStep) void {
        self.platform.linkDependencies(b, step);
        self.renderer.linkDependencies(b, step);
    }
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const backend = try Backend.from(
        b.option(BackendPlatform, "backend_platform", "Imgui backend platform") orelse BackendPlatform.default(target),
        b.option(BackendRenderer, "backend_renderer", "Imgui backend renderer") orelse BackendRenderer.default(target),
    );

    const imgui = b.addStaticLibrary(std.Build.StaticLibraryOptions{
        .name = "imgui",
        .target = target,
        .optimize = optimize,
    });
    imgui.linkLibCpp();
    imgui.linkLibC();
    imgui.addCSourceFiles(&.{
        thisDir() ++ "/imgui.cpp",
        thisDir() ++ "/imgui_demo.cpp",
        thisDir() ++ "/imgui_draw.cpp",
        thisDir() ++ "/imgui_tables.cpp",
        thisDir() ++ "/imgui_widgets.cpp",
    }, &.{});
    imgui.addCSourceFile(backend.platform.supportFile(), &.{});
    imgui.addCSourceFile(backend.renderer.supportFile(), &.{});
    imgui.addIncludePath(thisDir());
    imgui.addIncludePath(thisDir() ++ "/backends");
    imgui.installHeader("imgui.h", "imgui/imgui.h");
    imgui.installHeader("imgui_internal.h", "imgui/imgui_internal.h");
    imgui.installHeader("imstb_rectpack.h", "imgui/imstb_rectpack.h");
    imgui.installHeader("imstb_textedit.h", "imgui/imstb_textedit.h");
    imgui.installHeader("imstb_truetype.h", "imgui/imstb_truetype.h");
    imgui.installHeader("imconfig.h", "imgui/imconfig.h");
    imgui.installHeader("misc/freetype/imgui_freetype.h", "imgui/misc/freetype/imgui_freetype.h");
    backend.linkDependencies(b, imgui);

    b.installArtifact(imgui);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

// TODO(build-system): This is a workaround that we copy anywhere xcode_frameworks needs to be used.
// With the Zig package manager, it should be possible to remove this entirely and instead just
// write:
//
// ```
// step.linkLibrary(b.dependency("xcode_frameworks", .{
//     .target = step.target,
//     .optimize = step.optimize,
// }).artifact("xcode-frameworks"));
// @import("xcode_frameworks").addPaths(step);
// ```
//
// However, today this package cannot be imported with the Zig package manager due to `error: TarUnsupportedFileType`
// which would be fixed by https://github.com/ziglang/zig/pull/15382 - so instead for now you must
// copy+paste this struct into your `build.zig` and write:
//
// ```
// try xcode_frameworks.addPaths(b, step);
// ```
const xcode_frameworks = struct {
    pub fn addPaths(b: *std.Build, step: *std.build.CompileStep) void {
        // branch: mach
        xEnsureGitRepoCloned(b.allocator, "https://github.com/hexops/xcode-frameworks", "723aa55e9752c8c6c25d3413722b5fe13d72ac4f", xSdkPath("/zig-cache/xcode_frameworks")) catch |err| @panic(@errorName(err));

        step.addFrameworkPath(xSdkPath("/zig-cache/xcode_frameworks/Frameworks"));
        step.addSystemIncludePath(xSdkPath("/zig-cache/xcode_frameworks/include"));
        step.addLibraryPath(xSdkPath("/zig-cache/xcode_frameworks/lib"));
    }

    fn xEnsureGitRepoCloned(allocator: std.mem.Allocator, clone_url: []const u8, revision: []const u8, dir: []const u8) !void {
        if (xIsEnvVarTruthy(allocator, "NO_ENSURE_SUBMODULES") or xIsEnvVarTruthy(allocator, "NO_ENSURE_GIT")) {
            return;
        }

        xEnsureGit(allocator);

        if (std.fs.openDirAbsolute(dir, .{})) |_| {
            const current_revision = try xGetCurrentGitRevision(allocator, dir);
            if (!std.mem.eql(u8, current_revision, revision)) {
                // Reset to the desired revision
                xExec(allocator, &[_][]const u8{ "git", "fetch" }, dir) catch |err| std.debug.print("warning: failed to 'git fetch' in {s}: {s}\n", .{ dir, @errorName(err) });
                try xExec(allocator, &[_][]const u8{ "git", "checkout", "--quiet", "--force", revision }, dir);
                try xExec(allocator, &[_][]const u8{ "git", "submodule", "update", "--init", "--recursive" }, dir);
            }
            return;
        } else |err| return switch (err) {
            error.FileNotFound => {
                std.log.info("cloning required dependency..\ngit clone {s} {s}..\n", .{ clone_url, dir });

                try xExec(allocator, &[_][]const u8{ "git", "clone", "-c", "core.longpaths=true", clone_url, dir }, ".");
                try xExec(allocator, &[_][]const u8{ "git", "checkout", "--quiet", "--force", revision }, dir);
                try xExec(allocator, &[_][]const u8{ "git", "submodule", "update", "--init", "--recursive" }, dir);
                return;
            },
            else => err,
        };
    }

    fn xExec(allocator: std.mem.Allocator, argv: []const []const u8, cwd: []const u8) !void {
        var child = std.ChildProcess.init(argv, allocator);
        child.cwd = cwd;
        _ = try child.spawnAndWait();
    }

    fn xGetCurrentGitRevision(allocator: std.mem.Allocator, cwd: []const u8) ![]const u8 {
        const result = try std.ChildProcess.exec(.{ .allocator = allocator, .argv = &.{ "git", "rev-parse", "HEAD" }, .cwd = cwd });
        allocator.free(result.stderr);
        if (result.stdout.len > 0) return result.stdout[0 .. result.stdout.len - 1]; // trim newline
        return result.stdout;
    }

    fn xEnsureGit(allocator: std.mem.Allocator) void {
        const argv = &[_][]const u8{ "git", "--version" };
        const result = std.ChildProcess.exec(.{
            .allocator = allocator,
            .argv = argv,
            .cwd = ".",
        }) catch { // e.g. FileNotFound
            std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
            std.process.exit(1);
        };
        defer {
            allocator.free(result.stderr);
            allocator.free(result.stdout);
        }
        if (result.term.Exited != 0) {
            std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
            std.process.exit(1);
        }
    }

    fn xIsEnvVarTruthy(allocator: std.mem.Allocator, name: []const u8) bool {
        if (std.process.getEnvVarOwned(allocator, name)) |truthy| {
            defer allocator.free(truthy);
            if (std.mem.eql(u8, truthy, "true")) return true;
            return false;
        } else |_| {
            return false;
        }
    }

    fn xSdkPath(comptime suffix: []const u8) []const u8 {
        if (suffix[0] != '/') @compileError("suffix must be an absolute path");
        return comptime blk: {
            const root_dir = std.fs.path.dirname(@src().file) orelse ".";
            break :blk root_dir ++ suffix;
        };
    }
};
