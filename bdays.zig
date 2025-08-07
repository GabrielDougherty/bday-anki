const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const argv = [_][]const u8{ "echo", "Hello", "World" };
    var child = std.process.Child.init(&argv, arena.allocator());
    child.stdout_behavior = .Pipe;
    try child.spawn();

    const exit_code = child.wait();
    if (exit_code == 0) {
        const stdout = child.stdout;

        // create the buffered reader that will read from our file
        var br = std.io.bufferedReaderSize(64, stdout.reader());

        // set up our destination buffer
        var dest_buf: [br.buf.len]u8 = undefined;

        // wrap our destination buffer with a stream interface
        var fbs = std.io.fixedBufferStream(&dest_buf);

        // read our data
        try br.reader().streamUntilDelimiter(fbs.writer(), '\n', br.buf.len);

        // print
        std.debug.print("{s}\n", .{fbs.getWritten()});
    } else {
        std.debug.print("Got an error");
    }
}
