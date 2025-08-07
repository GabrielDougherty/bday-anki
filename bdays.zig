const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // Check for --debug flag
    const args = try std.process.argsAlloc(arena.allocator());
    defer std.process.argsFree(arena.allocator(), args);

    var debug_mode = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--debug")) {
            debug_mode = true;
            break;
        }
    }

    const applescript =
        \\try
        \\    tell application "Contacts"
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
        const raw_output = fbs.getWritten();
        if (debug_mode) {
            std.debug.print("Raw output: {s}\n\n", .{raw_output});
        }

        // Parse the birthday data and create Anki cards
        try createAnkiCards(arena.allocator(), raw_output, debug_mode);
    } else {
        std.log.info("Got an error", .{});
    }
}

fn createAnkiCards(allocator: std.mem.Allocator, raw_data: []const u8, debug_mode: bool) !void {
    // Split by colons to separate name:birthday pairs
    var it = std.mem.splitScalar(u8, raw_data, ':');

    var cards = std.ArrayList([]const u8).init(allocator);
    defer cards.deinit();

    var current_name: ?[]const u8 = null;

    while (it.next()) |segment| {
        if (current_name == null) {
            // This is a name
            current_name = std.mem.trim(u8, segment, " \t\n\r");
        } else {
            // This is a birthday - extract just the date part
            const birthday_full = std.mem.trim(u8, segment, " \t\n\r");

            // Find the next name (everything after the last space + time)
            var next_name_start: ?usize = null;
            var last_space_idx: usize = 0;

            for (birthday_full, 0..) |char, i| {
                if (char == ' ') {
                    last_space_idx = i;
                }
                // Look for pattern like "PMSomeName"
                if (i > 0 and birthday_full[i - 1] == 'M' and
                    (char >= 'A' and char <= 'Z'))
                {
                    next_name_start = i;
                    break;
                }
            }

            var birthday_clean: []const u8 = undefined;
            var next_name: ?[]const u8 = null;

            if (next_name_start) |start| {
                birthday_clean = birthday_full[0..start];
                next_name = birthday_full[start..];
            } else {
                birthday_clean = birthday_full;
            }

            // Extract month and day from birthday
            if (std.mem.indexOf(u8, birthday_clean, ",")) |first_comma_idx| {
                // Find the second comma to get the "Month Day" part
                const after_first_comma = birthday_clean[first_comma_idx + 1 ..];
                if (std.mem.indexOf(u8, after_first_comma, ",")) |second_comma_idx| {
                    // Extract "Month Day" (between first and second comma)
                    const month_day_full = std.mem.trim(u8, after_first_comma[0..second_comma_idx], " \t\n\r");

                    // Extract year (after second comma)
                    const after_second_comma = after_first_comma[second_comma_idx + 1 ..];
                    var year_part: []const u8 = "";

                    // Look for " at" to find where the year ends
                    if (std.mem.indexOf(u8, after_second_comma, " at")) |at_idx| {
                        year_part = std.mem.trim(u8, after_second_comma[0..at_idx], " \t\n\r");
                    } else if (std.mem.indexOf(u8, after_second_comma, " ")) |space_idx| {
                        year_part = std.mem.trim(u8, after_second_comma[0..space_idx], " \t\n\r");
                    }

                    if (debug_mode) {
                        std.debug.print("Debug - year_part: '{s}'\n", .{year_part});
                    }

                    // Create answer - include year unless it's 1604
                    var answer: []const u8 = undefined;
                    if (std.mem.eql(u8, year_part, "1604") or year_part.len == 0) {
                        answer = month_day_full;
                    } else {
                        answer = try std.fmt.allocPrint(allocator, "{s}, {s}", .{ month_day_full, year_part });
                    }

                    // Create Anki card
                    const card = try std.fmt.allocPrint(allocator, "When is {s}'s birthday?\t{s}\n", .{ current_name.?, answer });
                    try cards.append(card);

                    if (debug_mode) {
                        std.debug.print("Card: When is {s}'s birthday? -> {s}\n", .{ current_name.?, answer });
                    }
                }
            }

            current_name = next_name;
        }
    }

    // Write to TSV file for Anki import
    const file = try std.fs.cwd().createFile("birthdays.txt", .{});
    defer file.close();

    for (cards.items) |card| {
        try file.writeAll(card);
    }

    std.debug.print("\nCreated birthdays.txt with {} cards for Anki import.\n", .{cards.items.len});
    std.debug.print("In Anki: File -> Import -> Select birthdays.txt -> Set field separator to Tab\n", .{});
}
