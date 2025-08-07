const std = @import("std");
const threading = @import("threading.zig");
const file_operations = @import("file_operations.zig");

pub fn createAnkiCards(alloc: std.mem.Allocator, raw_data: []const u8, debug_mode: bool) ![]const u8 {
    // Split by colons to separate name:birthday pairs
    var it = std.mem.splitScalar(u8, raw_data, ':');

    var cards = std.ArrayList([]const u8).init(alloc);
    defer cards.deinit();

    var current_name: ?[]const u8 = null;
    var total_segments: usize = 0;
    var processed_segments: usize = 0;

    // First pass: count segments for progress tracking
    var count_it = std.mem.splitScalar(u8, raw_data, ':');
    while (count_it.next()) |_| {
        total_segments += 1;
    }

    std.debug.print("Processing {} segments for progress tracking...\n", .{total_segments});

    while (it.next()) |segment| {
        processed_segments += 1;
        
        // Update progress every few segments
        if (processed_segments % 5 == 0 or processed_segments == total_segments) {
            threading.setProgressValue(@as(f64, @floatFromInt(processed_segments)), @as(f64, @floatFromInt(total_segments)), alloc);
        }

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
                        answer = try std.fmt.allocPrint(alloc, "{s}, {s}", .{ month_day_full, year_part });
                    }

                    // Create Anki card
                    const card = try std.fmt.allocPrint(alloc, "When is {s}'s birthday?\t{s}\n", .{ current_name.?, answer });
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
    const output_path = if (file_operations.global_output_path) |path| 
        try std.fmt.allocPrint(alloc, "{s}/birthdays.txt", .{path})
    else blk: {
        // Default to ~/Downloads
        const home_dir = std.posix.getenv("HOME") orelse "/tmp";
        break :blk try std.fmt.allocPrint(alloc, "{s}/Downloads/birthdays.txt", .{home_dir});
    };
    defer alloc.free(output_path);
    
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    for (cards.items) |card| {
        try file.writeAll(card);
    }

    const status_message = try std.fmt.allocPrint(alloc, "Created {s} with {} cards for Anki import.\nIn Anki: File -> Import -> Select the file -> Set field separator to Tab", .{output_path, cards.items.len});
    
    std.debug.print("\nCreated {s} with {} cards for Anki import.\n", .{output_path, cards.items.len});
    std.debug.print("In Anki: File -> Import -> Select the file -> Set field separator to Tab\n", .{});
    
    return status_message;
}

pub fn fetchContactsData(allocator: std.mem.Allocator, debug_mode: bool) ?[]const u8 {
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
    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.spawn() catch return null;

    // Read stdout before waiting using buffered approach
    const stdout = child.stdout.?;
    var br = std.io.bufferedReaderSize(4096, stdout.reader());
    var dest_buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&dest_buf);

    // Read all available data
    br.reader().streamUntilDelimiter(fbs.writer(), 0, dest_buf.len) catch |err| switch (err) {
        error.EndOfStream => {}, // This is expected when we reach the end
        else => return null,
    };

    const exit_code = child.wait() catch return null;
    if (exit_code == .Exited and exit_code.Exited == 0) {
        const raw_output = fbs.getWritten();
        if (debug_mode) {
            std.debug.print("Raw output: {s}\n\n", .{raw_output});
        }

        // Parse the birthday data and create Anki cards
        return createAnkiCards(allocator, raw_output, debug_mode) catch null;
    } else {
        std.log.info("Got an error", .{});
        return null;
    }
}
