const std = @import("std");
const c = @cImport({
    @cInclude("objc/objc.h");
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
    @cDefine("OBJC_OLD_DISPATCH_PROTOTYPES", "0");
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Objective-C runtime helpers
fn objc_getClass(name: [*:0]const u8) c.Class {
    return @as(c.Class, @ptrCast(c.objc_getClass(name)));
}

fn sel_registerName(name: [*:0]const u8) c.SEL {
    return @as(c.SEL, @ptrCast(c.sel_registerName(name)));
}

fn objc_msgSend(target: anytype, sel: c.SEL) c.id {
    const func = @as(*const fn (c.id, c.SEL) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    return func(@as(c.id, @alignCast(@ptrCast(target))), sel);
}

fn objc_msgSend_stret(target: anytype, sel: c.SEL, comptime RetType: type) RetType {
    const func = @as(*const fn (c.id, c.SEL) callconv(.C) RetType, @ptrCast(&c.objc_msgSend));
    return func(@as(c.id, @alignCast(@ptrCast(target))), sel);
}

fn objc_msgSend_id(target: anytype, sel: c.SEL, arg: c.id) c.id {
    const func = @as(*const fn (c.id, c.SEL, c.id) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    return func(@as(c.id, @alignCast(@ptrCast(target))), sel, arg);
}

fn objc_msgSend_ptr(target: anytype, sel: c.SEL, arg: ?*const anyopaque) c.id {
    const func = @as(*const fn (c.id, c.SEL, ?*const anyopaque) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    return func(@as(c.id, @alignCast(@ptrCast(target))), sel, arg);
}

// Cocoa constants
const NSWindowStyleMaskTitled: c_ulong = 1 << 0;
const NSWindowStyleMaskClosable: c_ulong = 1 << 1;
const NSWindowStyleMaskResizable: c_ulong = 1 << 3;
const NSBackingStoreBuffered: c_ulong = 2;
const NSBezelStyleRounded: c_ulong = 1;

// NSRect structure
const NSRect = extern struct {
    origin: NSPoint,
    size: NSSize,
};

const NSPoint = extern struct {
    x: f64,
    y: f64,
};

const NSSize = extern struct {
    width: f64,
    height: f64,
};

fn NSMakeRect(x: f64, y: f64, w: f64, h: f64) NSRect {
    return NSRect{
        .origin = NSPoint{ .x = x, .y = y },
        .size = NSSize{ .width = w, .height = h },
    };
}

fn createAnkiCards(alloc: std.mem.Allocator, raw_data: []const u8, debug_mode: bool) !void {
    // Split by colons to separate name:birthday pairs
    var it = std.mem.splitScalar(u8, raw_data, ':');

    var cards = std.ArrayList([]const u8).init(alloc);
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
    const file = try std.fs.cwd().createFile("birthdays.txt", .{});
    defer file.close();

    for (cards.items) |card| {
        try file.writeAll(card);
    }

    std.debug.print("\nCreated birthdays.txt with {} cards for Anki import.\n", .{cards.items.len});
    std.debug.print("In Anki: File -> Import -> Select birthdays.txt -> Set field separator to Tab\n", .{});
}

fn callback() void {
    // Check for --debug flag
    const args = std.process.argsAlloc(allocator) catch return;
    defer std.process.argsFree(allocator, args);

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
    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.spawn() catch return;

    // Read stdout before waiting using buffered approach
    const stdout = child.stdout.?;
    var br = std.io.bufferedReaderSize(4096, stdout.reader());
    var dest_buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&dest_buf);

    // Read all available data
    br.reader().streamUntilDelimiter(fbs.writer(), 0, dest_buf.len) catch |err| switch (err) {
        error.EndOfStream => {}, // This is expected when we reach the end
        else => return,
    };

    const exit_code = child.wait() catch return;
    if (exit_code == .Exited and exit_code.Exited == 0) {
        const raw_output = fbs.getWritten();
        if (debug_mode) {
            std.debug.print("Raw output: {s}\n\n", .{raw_output});
        }

        // Parse the birthday data and create Anki cards
        createAnkiCards(allocator, raw_output, debug_mode) catch return;
    } else {
        std.log.info("Got an error", .{});
    }
}


// C-compatible wrapper function
export fn buttonClicked(_: c.id, _: c.SEL) void {
    std.debug.print("Button clicked! Running birthday card generator...\n", .{});
    callback();
}

fn createNSString(text: [*:0]const u8) c.id {
    const NSString = objc_getClass("NSString");
    const alloc_sel = sel_registerName("alloc");
    const initWithUTF8String_sel = sel_registerName("initWithUTF8String:");
    
    const string_alloc = objc_msgSend(NSString, alloc_sel);
    return objc_msgSend_ptr(string_alloc, initWithUTF8String_sel, text);
}

pub fn main() !void {
    std.debug.print("Starting GUI application...\n", .{});
    
    // Initialize NSApplication
    const NSApplication = objc_getClass("NSApplication");
    const sharedApplication_sel = sel_registerName("sharedApplication");
    const app = objc_msgSend(NSApplication, sharedApplication_sel);
    
    // Set app activation policy to regular app
    const setActivationPolicy_sel = sel_registerName("setActivationPolicy:");
    const policy_func = @as(*const fn (c.id, c.SEL, c_long) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    _ = policy_func(app, setActivationPolicy_sel, 0); // NSApplicationActivationPolicyRegular
    
    std.debug.print("Created NSApplication...\n", .{});
    
    // Create window with larger size and centered position
    const NSWindow = objc_getClass("NSWindow");
    const alloc_sel = sel_registerName("alloc");
    const window_alloc = objc_msgSend(NSWindow, alloc_sel);
    
    const initWithContentRect_sel = sel_registerName("initWithContentRect:styleMask:backing:defer:");
    const window_rect = NSMakeRect(200, 200, 500, 400); // Larger and more centered
    const style_mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
    
    // This is complex due to the function signature, let's use a simpler approach
    const func = @as(*const fn (c.id, c.SEL, NSRect, c_ulong, c_ulong, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    const window = func(window_alloc, initWithContentRect_sel, window_rect, style_mask, NSBackingStoreBuffered, false);
    
    std.debug.print("Created window...\n", .{});
    
    // Set window title
    const setTitle_sel = sel_registerName("setTitle:");
    const title = createNSString("Birthday Card Generator");
    _ = objc_msgSend_id(window, setTitle_sel, title);
    
    // Center the window
    const center_sel = sel_registerName("center");
    _ = objc_msgSend(window, center_sel);
    
    std.debug.print("Set window title and centered...\n", .{});
    
    // Create button with better positioning
    const NSButton = objc_getClass("NSButton");
    const button_alloc = objc_msgSend(NSButton, alloc_sel);
    
    const initWithFrame_sel = sel_registerName("initWithFrame:");
    const button_rect = NSMakeRect(200, 200, 120, 40); // Larger button, better positioned
    const button_func = @as(*const fn (c.id, c.SEL, NSRect) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    const button = button_func(button_alloc, initWithFrame_sel, button_rect);
    
    // Set button title
    const button_title = createNSString("Generate Cards");
    _ = objc_msgSend_id(button, setTitle_sel, button_title);
    
    // Set button style
    const setBezelStyle_sel = sel_registerName("setBezelStyle:");
    const bezel_func = @as(*const fn (c.id, c.SEL, c_ulong) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    _ = bezel_func(button, setBezelStyle_sel, NSBezelStyleRounded);
    
    std.debug.print("Created and configured button...\n", .{});
    
    // Set button target and action
    const setTarget_sel = sel_registerName("setTarget:");
    _ = objc_msgSend_id(button, setTarget_sel, null);
    
    const setAction_sel = sel_registerName("setAction:");
    const action = sel_registerName("buttonClicked:");
    const action_func = @as(*const fn (c.id, c.SEL, c.SEL) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    _ = action_func(button, setAction_sel, action);
    
    // Add button to window
    const contentView_sel = sel_registerName("contentView");
    const content_view = objc_msgSend(window, contentView_sel);
    const addSubview_sel = sel_registerName("addSubview:");
    _ = objc_msgSend_id(content_view, addSubview_sel, button);
    
    std.debug.print("Added button to window...\n", .{});
    
    // Make sure the app is active and window is visible
    const activateIgnoringOtherApps_sel = sel_registerName("activateIgnoringOtherApps:");
    const activate_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    _ = activate_func(app, activateIgnoringOtherApps_sel, true);
    
    // Show window
    const makeKeyAndOrderFront_sel = sel_registerName("makeKeyAndOrderFront:");
    _ = objc_msgSend_id(window, makeKeyAndOrderFront_sel, null);
    
    std.debug.print("Window should now be visible!\n", .{});
    
    // Run the application
    const run_sel = sel_registerName("run");
    _ = objc_msgSend(app, run_sel);
}