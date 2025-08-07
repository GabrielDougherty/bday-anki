const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    
    const applescript = 
        \\try
        \\    tell application "Contacts"
        \\        activate
        \\        delay 1
        \\        set contactCount to count of people
        \\        if contactCount = 0 then
        \\            return "No contacts found or permission denied"
        \\        end if
        \\        set contactList to {}
        \\        repeat with aPerson in people
        \\            try
        \\                if birth date of aPerson is not missing value then
        \\                    set personName to name of aPerson as string
        \\                    set personBday to birth date of aPerson as string
        \\                    set end of contactList to personName & ":" & personBday
        \\                end if
        \\            end try
        \\        end repeat
        \\        return contactList as string
        \\    end tell
        \\on error errMsg number errNum
        \\    return "Error " & errNum & ": " & errMsg
        \\end try
    ;
    
    const argv = [_][]const u8{ "osascript", "-e", applescript };
    var child = std.process.Child.init(&argv, arena.allocator());
    child.stdout_behavior = .Pipe;
    try child.spawn();

    // Read stdout before waiting using buffered approach
    const stdout = child.stdout.?;
    var br = std.io.bufferedReaderSize(4096, stdout.reader());
    var dest_buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&dest_buf);
    
    // Read all available data
    br.reader().streamUntilDelimiter(fbs.writer(), 0, dest_buf.len) catch |err| switch (err) {
        error.EndOfStream => {}, // This is expected when we reach the end
        else => return err,
    };

    const exit_code = try child.wait();
    if (exit_code == .Exited and exit_code.Exited == 0) {
        std.debug.print("{s}", .{fbs.getWritten()});
    } else {
        std.log.info("Got an error", .{});
    }
}
