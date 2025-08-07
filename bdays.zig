const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const argv = [_][]const u8{ "echo", "Hello", "World" };
    var child = std.process.Child.init(&argv, arena.allocator());
    child.stdout_behavior = .Pipe;
    try child.spawn();

    // Read stdout before waiting
    const stdout_data = try child.stdout.?.readToEndAlloc(arena.allocator(), 1024);

    const exit_code = try child.wait();
    if (exit_code == .Exited and exit_code.Exited == 0) {
        std.debug.print("{s}", .{stdout_data});
    } else {
        std.log.info("Got an error", .{});
    }
}
