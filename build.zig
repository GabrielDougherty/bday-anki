const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create executable for bdays
    const exe = b.addExecutable(.{
        .name = "bdays",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Check if we're in a nix environment
    const is_nix = b.graph.env_map.get("IN_NIX_SHELL") != null;
    if (is_nix) {
        // In nix, use the host system frameworks (impure build)
        std.debug.print("Building in nix environment - using host system frameworks\n", .{});

        // Add system framework search paths
        exe.root_module.addFrameworkPath(b.path("/System/Library/Frameworks"));
        exe.root_module.addFrameworkPath(b.path("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks"));

        // Don't link objc explicitly - it's provided by the frameworks on modern macOS
        std.debug.print("Added system framework paths (objc provided by frameworks)\n", .{});
    } else {
        // Normal system build
        exe.linkSystemLibrary("objc");
    }

    exe.linkFramework("Cocoa");
    exe.linkFramework("Foundation");

    b.installArtifact(exe);

    // Create run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        for (args) |arg| {
            run_cmd.addArg(arg);
        }
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
