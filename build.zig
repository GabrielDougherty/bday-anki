const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create executable for bdays
    const exe = b.addExecutable(.{
        .name = "bdays",
        .root_source_file = b.path("bdays.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Check if we're in a nix environment
    const is_nix = std.process.getEnvVarOwned(b.allocator, "IN_NIX_SHELL") catch null;
    if (is_nix) |_| {
        // In nix, use the host system frameworks (impure build)
        std.debug.print("Building in nix environment - using host system frameworks\n", .{});
        
        // Add system framework search paths
        exe.addFrameworkPath(.{ .cwd_relative = "/System/Library/Frameworks" });
        exe.addFrameworkPath(.{ .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks" });
        
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
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Create test step
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("bdays.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
