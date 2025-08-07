const std = @import("std");
const c = @cImport({
    @cInclude("objc/objc.h");
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
    @cInclude("dispatch/dispatch.h");
    @cDefine("OBJC_OLD_DISPATCH_PROTOTYPES", "0");
});

// Helper function to cast dispatch queue
fn getMainQueue() c.dispatch_queue_t {
    return c.dispatch_get_main_queue();
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Global reference to progress bar for updating from background thread
var global_progress_bar: ?c.id = null;
// Global reference to status label for updating from background thread
var global_status_label: ?c.id = null;
// Global reference to store the selected output path
var global_output_path: ?[]const u8 = null;
// Global reference to the "Open Location" button
var global_open_location_button: ?c.id = null;

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

fn createAnkiCards(alloc: std.mem.Allocator, raw_data: []const u8, debug_mode: bool) ![]const u8 {
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
            setProgressValue(@as(f64, @floatFromInt(processed_segments)), @as(f64, @floatFromInt(total_segments)));
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
    const output_path = if (global_output_path) |path| 
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

fn callback() ?[]const u8 {
    // Check for --debug flag
    const args = std.process.argsAlloc(allocator) catch return null;
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


// C-compatible wrapper function that will be called by the button
export fn buttonClicked(sender: c.id, action: c.SEL) void {
    _ = sender; // Suppress unused parameter warning
    _ = action; // Suppress unused parameter warning
    std.debug.print("Button clicked! Starting background task...\n", .{});
    
    // Create a background thread to run the card generation
    const thread = std.Thread.spawn(.{}, backgroundCardGeneration, .{}) catch {
        std.debug.print("Failed to create background thread\n", .{});
        return;
    };
    
    // Detach the thread so it cleans up automatically
    thread.detach();
}

// Background thread function for card generation
fn backgroundCardGeneration() void {
    std.debug.print("Running card generation in background thread...\n", .{});
    
    // Show progress bar
    showProgressBar();
    
    // Run the card generation
    const result = callback();
    
    // Hide progress bar when done
    hideProgressBar();
    
    // Update status label with result
    if (result) |status_message| {
        updateStatusLabel(status_message);
        // Show the "Open Location" button after successful generation
        showOpenLocationButton();
        std.debug.print("Card generation completed successfully.\n", .{});
    } else {
        updateStatusLabel("Error: Failed to generate cards. Please check permissions and try again.");
        std.debug.print("Card generation failed.\n", .{});
    }
}

// Window delegate to handle window closing
export fn windowShouldClose(_: c.id, _: c.SEL) bool {
    std.debug.print("Window closing, terminating app...\n", .{});
    
    // Get NSApplication and terminate
    const NSApplication = objc_getClass("NSApplication");
    const sharedApplication_sel = sel_registerName("sharedApplication");
    const app = objc_msgSend(NSApplication, sharedApplication_sel);
    
    const terminate_sel = sel_registerName("terminate:");
    _ = objc_msgSend_id(app, terminate_sel, null);
    
    return true;
}

// Function to show save panel dialog
fn showSavePanel() void {
    const main_queue = getMainQueue();
    c.dispatch_async_f(main_queue, null, showSavePanelOnMainThread);
}

export fn showSavePanelOnMainThread(context: ?*anyopaque) callconv(.C) void {
    _ = context; // Unused
    
    std.debug.print("Showing save panel on main thread...\n", .{});
    
    // Create NSSavePanel
    const NSSavePanel = objc_getClass("NSSavePanel");
    const savePanel_sel = sel_registerName("savePanel");
    const save_panel = objc_msgSend(NSSavePanel, savePanel_sel);
    
    // Set default filename
    const setNameFieldStringValue_sel = sel_registerName("setNameFieldStringValue:");
    const default_name = createNSString("birthdays.txt");
    _ = objc_msgSend_id(save_panel, setNameFieldStringValue_sel, default_name);
    
    // Set title
    const setTitle_sel = sel_registerName("setTitle:");
    const title = createNSString("Save Birthday Cards");
    _ = objc_msgSend_id(save_panel, setTitle_sel, title);
    
    // Set message
    const setMessage_sel = sel_registerName("setMessage:");
    const message = createNSString("Choose where to save the birthday cards file:");
    _ = objc_msgSend_id(save_panel, setMessage_sel, message);
    
    // Set default directory to Downloads
    const home_dir = std.posix.getenv("HOME") orelse "/tmp";
    const downloads_path = std.fmt.allocPrint(allocator, "{s}/Downloads", .{home_dir}) catch {
        std.debug.print("Failed to create downloads path\n", .{});
        return;
    };
    defer allocator.free(downloads_path);
    
    const downloads_path_z = allocator.dupeZ(u8, downloads_path) catch {
        std.debug.print("Failed to create null-terminated downloads path\n", .{});
        return;
    };
    defer allocator.free(downloads_path_z);
    
    const NSURL = objc_getClass("NSURL");
    const fileURLWithPath_sel = sel_registerName("fileURLWithPath:");
    const downloads_nsstring = createNSString(downloads_path_z.ptr);
    const downloads_url = objc_msgSend_id(NSURL, fileURLWithPath_sel, downloads_nsstring);
    
    const setDirectoryURL_sel = sel_registerName("setDirectoryURL:");
    _ = objc_msgSend_id(save_panel, setDirectoryURL_sel, downloads_url);
    
    // Run the panel modally
    const runModal_sel = sel_registerName("runModal");
    const response_func = @as(*const fn (c.id, c.SEL) callconv(.C) c_long, @ptrCast(&c.objc_msgSend));
    const response = response_func(save_panel, runModal_sel);
    
    // NSModalResponseOK = 1
    if (response == 1) {
        // Get the selected URL
        const URL_sel = sel_registerName("URL");
        const selected_url = objc_msgSend(save_panel, URL_sel);
        
        if (selected_url != null) {
            // Get the path from URL
            const path_sel = sel_registerName("path");
            const path_nsstring = objc_msgSend(selected_url, path_sel);
            
            // Convert NSString to C string
            const UTF8String_sel = sel_registerName("UTF8String");
            const path_cstring_func = @as(*const fn (c.id, c.SEL) callconv(.C) [*:0]const u8, @ptrCast(&c.objc_msgSend));
            const path_cstring = path_cstring_func(path_nsstring, UTF8String_sel);
            
            // Get just the directory part (remove filename)
            const full_path = std.mem.span(path_cstring);
            if (std.fs.path.dirname(full_path)) |dir_path| {
                // Store the directory path globally
                if (global_output_path) |old_path| {
                    allocator.free(old_path);
                }
                global_output_path = allocator.dupe(u8, dir_path) catch {
                    std.debug.print("Failed to store output path\n", .{});
                    return;
                };
                std.debug.print("Selected output directory: {s}\n", .{global_output_path.?});
            }
        }
    } else {
        std.debug.print("Save panel was cancelled\n", .{});
    }
}

// Progress bar control functions (dispatch to main thread)
fn showProgressBar() void {
    const main_queue = getMainQueue();
    c.dispatch_async_f(main_queue, null, showProgressBarOnMainThread);
}

fn hideProgressBar() void {
    const main_queue = getMainQueue();
    c.dispatch_async_f(main_queue, null, hideProgressBarOnMainThread);
}

// Status label update function (dispatch to main thread)
fn updateStatusLabel(message: []const u8) void {
    // Allocate context on heap and store the message
    const context = allocator.dupe(u8, message) catch {
        std.debug.print("Failed to allocate context for status update\n", .{});
        return;
    };
    
    const main_queue = getMainQueue();
    c.dispatch_async_f(main_queue, context.ptr, updateStatusLabelOnMainThread);
}

// Function to show the "Open Location" button after generation completes
fn showOpenLocationButton() void {
    const main_queue = getMainQueue();
    c.dispatch_async_f(main_queue, null, showOpenLocationButtonOnMainThread);
}

export fn showOpenLocationButtonOnMainThread(context: ?*anyopaque) callconv(.C) void {
    _ = context; // Unused
    
    if (global_open_location_button) |open_button| {
        std.debug.print("Showing open location button on main thread...\n", .{});
        
        // Make the button visible
        const setHidden_sel = sel_registerName("setHidden:");
        const hidden_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
        _ = hidden_func(open_button, setHidden_sel, false);
    } else {
        std.debug.print("Global open location button is null!\n", .{});
    }
}

// Function to open the file location in Finder
fn openFileLocation() void {
    const main_queue = getMainQueue();
    c.dispatch_async_f(main_queue, null, openFileLocationOnMainThread);
}

export fn openFileLocationOnMainThread(context: ?*anyopaque) callconv(.C) void {
    _ = context; // Unused
    
    std.debug.print("Opening file location in Finder...\n", .{});
    
    // Determine the path to open
    const path_to_open = if (global_output_path) |path|
        path
    else blk: {
        const home_dir = std.posix.getenv("HOME") orelse "/tmp";
        break :blk home_dir;
    };
    
    // Create NSWorkspace and open the directory
    const NSWorkspace = objc_getClass("NSWorkspace");
    const sharedWorkspace_sel = sel_registerName("sharedWorkspace");
    const workspace = objc_msgSend(NSWorkspace, sharedWorkspace_sel);
    
    // Create NSURL for the directory
    const NSURL = objc_getClass("NSURL");
    const fileURLWithPath_sel = sel_registerName("fileURLWithPath:");
    
    // Create null-terminated path
    const path_z = allocator.dupeZ(u8, path_to_open) catch {
        std.debug.print("Failed to create null-terminated path\n", .{});
        return;
    };
    defer allocator.free(path_z);
    
    const path_nsstring = createNSString(path_z.ptr);
    const directory_url = objc_msgSend_id(NSURL, fileURLWithPath_sel, path_nsstring);
    
    // Open the directory in Finder
    const openURL_sel = sel_registerName("openURL:");
    const success_func = @as(*const fn (c.id, c.SEL, c.id) callconv(.C) bool, @ptrCast(&c.objc_msgSend));
    const success = success_func(workspace, openURL_sel, directory_url);
    
    if (success) {
        std.debug.print("Successfully opened directory: {s}\n", .{path_to_open});
    } else {
        std.debug.print("Failed to open directory: {s}\n", .{path_to_open});
    }
}

// Functions that actually update the UI (must run on main thread)
export fn showProgressBarOnMainThread(context: ?*anyopaque) callconv(.C) void {
    _ = context; // Unused
    if (global_progress_bar) |progress_bar| {
        std.debug.print("Showing progress bar on main thread...\n", .{});
        
        // Show progress bar
        const setHidden_sel = sel_registerName("setHidden:");
        const hidden_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
        _ = hidden_func(progress_bar, setHidden_sel, false);
        
        // Start animation for indeterminate progress
        const startAnimation_sel = sel_registerName("startAnimation:");
        _ = objc_msgSend_id(progress_bar, startAnimation_sel, null);
        
        std.debug.print("Started progress bar animation on main thread\n", .{});
    } else {
        std.debug.print("Global progress bar is null!\n", .{});
    }
}

export fn hideProgressBarOnMainThread(context: ?*anyopaque) callconv(.C) void {
    _ = context; // Unused
    if (global_progress_bar) |progress_bar| {
        std.debug.print("Hiding progress bar on main thread...\n", .{});
        
        // Stop animation
        const stopAnimation_sel = sel_registerName("stopAnimation:");
        _ = objc_msgSend_id(progress_bar, stopAnimation_sel, null);
        
        // Hide progress bar
        const setHidden_sel = sel_registerName("setHidden:");
        const hidden_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
        _ = hidden_func(progress_bar, setHidden_sel, true);
        
        std.debug.print("Stopped and hid progress bar on main thread\n", .{});
    } else {
        std.debug.print("Global progress bar is null!\n", .{});
    }
}

export fn updateStatusLabelOnMainThread(message_ptr: ?*anyopaque) callconv(.C) void {
    if (message_ptr) |ptr| {
        // Convert back to proper slice using the allocated memory
        const message_bytes = @as([*]u8, @ptrCast(ptr));
        
        // We need to find the length - for now assume it's null-terminated
        var len: usize = 0;
        while (message_bytes[len] != 0) {
            len += 1;
        }
        const message = message_bytes[0..len];
        
        if (global_status_label) |status_label| {
            std.debug.print("Updating status label on main thread: {s}\n", .{message});
            
            // Create NSString from message
            const null_terminated = allocator.dupeZ(u8, message) catch {
                std.debug.print("Failed to create null-terminated string\n", .{});
                return;
            };
            defer allocator.free(null_terminated);
            
            const status_string = createNSString(null_terminated.ptr);
            
            // Update the label text
            const setStringValue_sel = sel_registerName("setStringValue:");
            _ = objc_msgSend_id(status_label, setStringValue_sel, status_string);
            
            // Make the label visible
            const setHidden_sel = sel_registerName("setHidden:");
            const hidden_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
            _ = hidden_func(status_label, setHidden_sel, false);
            
        } else {
            std.debug.print("Global status label is null!\n", .{});
        }
        
        // Free the allocated message
        allocator.free(message);
    }
}

// Progress value setting (dispatch to main thread)
fn setProgressValue(value: f64, max_value: f64) void {
    const SetProgressValueContext = struct {
        value: f64,
        max_value: f64,
    };
    
    // Allocate context on heap and store the values
    const context = allocator.create(SetProgressValueContext) catch {
        std.debug.print("Failed to allocate context for progress update\n", .{});
        return;
    };
    context.value = value;
    context.max_value = max_value;
    
    const main_queue = getMainQueue();
    c.dispatch_async_f(main_queue, context, setProgressValueOnMainThread);
}

export fn setProgressValueOnMainThread(context_ptr: ?*anyopaque) callconv(.C) void {
    if (context_ptr) |ptr| {
        const SetProgressValueContext = struct {
            value: f64,
            max_value: f64,
        };
        const context = @as(*SetProgressValueContext, @ptrCast(@alignCast(ptr)));
        const value = context.value;
        const max_value = context.max_value;
        
        // Free the context
        allocator.destroy(context);
        
        if (global_progress_bar) |progress_bar| {
            // Switch to determinate mode if needed
            const setIndeterminate_sel = sel_registerName("setIndeterminate:");
            const indeterminate_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
            _ = indeterminate_func(progress_bar, setIndeterminate_sel, false);
            
            // Set max value
            const setMaxValue_sel = sel_registerName("setMaxValue:");
            const max_func = @as(*const fn (c.id, c.SEL, f64) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
            _ = max_func(progress_bar, setMaxValue_sel, max_value);
            
            // Set current value
            const setDoubleValue_sel = sel_registerName("setDoubleValue:");
            const value_func = @as(*const fn (c.id, c.SEL, f64) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
            _ = value_func(progress_bar, setDoubleValue_sel, value);
            
            std.debug.print("Set progress value to {}/{} on main thread\n", .{value, max_value});
        }
    }
}

fn createNSString(text: [*:0]const u8) c.id {
    const NSString = objc_getClass("NSString");
    const alloc_sel = sel_registerName("alloc");
    const initWithUTF8String_sel = sel_registerName("initWithUTF8String:");
    
    const string_alloc = objc_msgSend(NSString, alloc_sel);
    return objc_msgSend_ptr(string_alloc, initWithUTF8String_sel, text);
}

// Create a custom class that can respond to button/menu actions
fn createCustomResponder() c.id {
    // Get the NSObject class as our base
    const NSObject = objc_getClass("NSObject");
    
    // Create a new class that inherits from NSObject
    const CustomResponder = c.objc_allocateClassPair(NSObject, "CustomResponder", 0);
    
    // Add our method to the class for generating cards
    const generateCards_sel = sel_registerName("generateCards:");
    const method_impl = @as(*const fn (c.id, c.SEL, c.id) callconv(.C) void, @ptrCast(&generateCardsImpl));
    
    const success1 = c.class_addMethod(CustomResponder, generateCards_sel, 
        @as(c.IMP, @ptrCast(method_impl)), "v@:@");
    
    if (!success1) {
        std.debug.print("Failed to add generateCards method to custom class\n", .{});
    }
    
    // Add method for choosing location
    const chooseLocation_sel = sel_registerName("chooseLocation:");
    const location_method_impl = @as(*const fn (c.id, c.SEL, c.id) callconv(.C) void, @ptrCast(&chooseLocationImpl));
    
    const success2 = c.class_addMethod(CustomResponder, chooseLocation_sel, 
        @as(c.IMP, @ptrCast(location_method_impl)), "v@:@");
    
    if (!success2) {
        std.debug.print("Failed to add chooseLocation method to custom class\n", .{});
    }
    
    // Add method for opening file location
    const openLocation_sel = sel_registerName("openLocation:");
    const open_method_impl = @as(*const fn (c.id, c.SEL, c.id) callconv(.C) void, @ptrCast(&openLocationImpl));
    
    const success3 = c.class_addMethod(CustomResponder, openLocation_sel, 
        @as(c.IMP, @ptrCast(open_method_impl)), "v@:@");
    
    if (!success3) {
        std.debug.print("Failed to add openLocation method to custom class\n", .{});
    }
    
    // Register the class
    c.objc_registerClassPair(CustomResponder);
    
    // Create an instance
    const alloc_sel = sel_registerName("alloc");
    const init_sel = sel_registerName("init");
    const instance_alloc = objc_msgSend(CustomResponder, alloc_sel);
    const instance = objc_msgSend(instance_alloc, init_sel);
    
    std.debug.print("Created custom responder class and instance\n", .{});
    return instance;
}

// Implementation function that will be called by the Objective-C runtime
export fn generateCardsImpl(self: c.id, _cmd: c.SEL, sender: c.id) void {
    _ = self;
    _ = _cmd; 
    _ = sender;
    std.debug.print("Custom responder generateCards called!\n", .{});
    
    // Create a background thread to run the card generation
    const thread = std.Thread.spawn(.{}, backgroundCardGeneration, .{}) catch |err| {
        std.debug.print("Failed to create background thread: {}\n", .{err});
        return;
    };
    
    // Detach the thread so it cleans up automatically
    thread.detach();
}

// Implementation function for location selection
export fn chooseLocationImpl(self: c.id, _cmd: c.SEL, sender: c.id) void {
    _ = self;
    _ = _cmd; 
    _ = sender;
    std.debug.print("Custom responder chooseLocation called!\n", .{});
    
    // Show the save panel
    showSavePanel();
}

// Implementation function for opening file location
export fn openLocationImpl(self: c.id, _cmd: c.SEL, sender: c.id) void {
    _ = self;
    _ = _cmd; 
    _ = sender;
    std.debug.print("Custom responder openLocation called!\n", .{});
    
    // Open the file location
    openFileLocation();
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
    
    // Create "Choose Location" button
    const location_button_alloc = objc_msgSend(NSButton, alloc_sel);
    const location_button_rect = NSMakeRect(330, 200, 120, 40); // To the right of generate button
    const location_button_func = @as(*const fn (c.id, c.SEL, NSRect) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    const location_button = location_button_func(location_button_alloc, initWithFrame_sel, location_button_rect);
    
    // Set location button title
    const location_button_title = createNSString("Choose Location");
    _ = objc_msgSend_id(location_button, setTitle_sel, location_button_title);
    _ = bezel_func(location_button, setBezelStyle_sel, NSBezelStyleRounded);
    
    std.debug.print("Created location selection button...\n", .{});
    
    // Create "Open Location" button (initially hidden)
    const open_button_alloc = objc_msgSend(NSButton, alloc_sel);
    const open_button_rect = NSMakeRect(200, 250, 120, 40); // Above the generate button
    const open_button_func = @as(*const fn (c.id, c.SEL, NSRect) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    const open_location_button = open_button_func(open_button_alloc, initWithFrame_sel, open_button_rect);
    
    // Set open location button title
    const open_button_title = createNSString("Open Location");
    _ = objc_msgSend_id(open_location_button, setTitle_sel, open_button_title);
    _ = bezel_func(open_location_button, setBezelStyle_sel, NSBezelStyleRounded);
    
    std.debug.print("Created open location button (hidden until generation completes)...\n", .{});
    
    // Store global reference for background thread access
    global_open_location_button = open_location_button;
    
    // Instead of trying to get the button action to work immediately,
    // let's add a label that shows instructions
    const NSTextField = objc_getClass("NSTextField");
    const label_alloc = objc_msgSend(NSTextField, alloc_sel);
    const initWithFrame_label_sel = sel_registerName("initWithFrame:");
    const label_rect = NSMakeRect(50, 100, 400, 60);
    const label_func = @as(*const fn (c.id, c.SEL, NSRect) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    const label = label_func(label_alloc, initWithFrame_label_sel, label_rect);
    
    // Set label properties
    const setStringValue_sel = sel_registerName("setStringValue:");
    const instructions = createNSString("Click 'Generate Cards' or press Cmd+G to create cards\nClick 'Choose Location' to select where to save (default: ~/Downloads)\nPress Cmd+Q to quit the application.");
    _ = objc_msgSend_id(label, setStringValue_sel, instructions);
    
    const setBezeled_sel = sel_registerName("setBezeled:");
    const bezeled_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    _ = bezeled_func(label, setBezeled_sel, false);
    
    const setEditable_sel = sel_registerName("setEditable:");
    const editable_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    _ = editable_func(label, setEditable_sel, false);
    
    std.debug.print("Created instruction label...\n", .{});
    
    // Create status label (initially hidden)
    const status_label_alloc = objc_msgSend(NSTextField, alloc_sel);
    const status_label_rect = NSMakeRect(50, 40, 400, 50); // Below the instruction label
    const status_label_func = @as(*const fn (c.id, c.SEL, NSRect) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    const status_label = status_label_func(status_label_alloc, initWithFrame_label_sel, status_label_rect);
    
    // Set status label properties
    const empty_status = createNSString("");
    _ = objc_msgSend_id(status_label, setStringValue_sel, empty_status);
    _ = bezeled_func(status_label, setBezeled_sel, false);
    _ = editable_func(status_label, setEditable_sel, false);
    
    // Note: We'll set hidden status later using the same selector as progress bar
    
    std.debug.print("Created status label (hidden until generation completes)...\n", .{});
    
    // Store global reference for background thread access
    global_status_label = status_label;
    
    // Create progress bar
    const NSProgressIndicator = objc_getClass("NSProgressIndicator");
    const progress_alloc = objc_msgSend(NSProgressIndicator, alloc_sel);
    const progress_rect = NSMakeRect(50, 180, 400, 30); // Bigger and higher position
    const progress_func = @as(*const fn (c.id, c.SEL, NSRect) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    const progress_bar = progress_func(progress_alloc, initWithFrame_label_sel, progress_rect);
    
    // Configure progress bar
    const setStyle_sel = sel_registerName("setStyle:");
    const style_func = @as(*const fn (c.id, c.SEL, c_ulong) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    _ = style_func(progress_bar, setStyle_sel, 0); // NSProgressIndicatorStyleBar
    
    const setIndeterminate_sel = sel_registerName("setIndeterminate:");
    const indeterminate_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    _ = indeterminate_func(progress_bar, setIndeterminate_sel, true);
    
    const setHidden_sel = sel_registerName("setHidden:");
    const hidden_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    _ = hidden_func(progress_bar, setHidden_sel, true); // Start hidden
    _ = hidden_func(status_label, setHidden_sel, true); // Start hidden
    
    std.debug.print("Created progress bar (hidden until generation starts)...\n", .{});
    
    // Store global reference for background thread access
    global_progress_bar = progress_bar;
    
    // Create our custom responder that can handle actions
    const responder = createCustomResponder();
    
    // Connect button to our custom responder
    const setTarget_sel = sel_registerName("setTarget:");
    _ = objc_msgSend_id(button, setTarget_sel, responder);
    
    const setAction_sel = sel_registerName("setAction:");
    const generateCards_action_sel = sel_registerName("generateCards:");
    _ = objc_msgSend_ptr(button, setAction_sel, @ptrCast(generateCards_action_sel));
    
    // Connect location button to our custom responder
    _ = objc_msgSend_id(location_button, setTarget_sel, responder);
    const chooseLocation_action_sel = sel_registerName("chooseLocation:");
    _ = objc_msgSend_ptr(location_button, setAction_sel, @ptrCast(chooseLocation_action_sel));
    
    // Connect open location button to our custom responder
    _ = objc_msgSend_id(open_location_button, setTarget_sel, responder);
    const openLocation_action_sel = sel_registerName("openLocation:");
    _ = objc_msgSend_ptr(open_location_button, setAction_sel, @ptrCast(openLocation_action_sel));
    
    std.debug.print("Connected all buttons to custom responder...\n", .{});
    
    // Set the window to release when closed, which will terminate the app
    const setReleasedWhenClosed_sel = sel_registerName("setReleasedWhenClosed:");
    const bool_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    _ = bool_func(window, setReleasedWhenClosed_sel, true);
    
    std.debug.print("Set window to release when closed...\n", .{});
    
    // Add button to window
    const contentView_sel = sel_registerName("contentView");
    const content_view = objc_msgSend(window, contentView_sel);
    const addSubview_sel = sel_registerName("addSubview:");
    _ = objc_msgSend_id(content_view, addSubview_sel, button);
    _ = objc_msgSend_id(content_view, addSubview_sel, location_button);
    _ = objc_msgSend_id(content_view, addSubview_sel, label);
    _ = objc_msgSend_id(content_view, addSubview_sel, progress_bar);
    _ = objc_msgSend_id(content_view, addSubview_sel, status_label);
    _ = objc_msgSend_id(content_view, addSubview_sel, open_location_button);
    
    // Hide open location button initially (reuse existing hidden_func)
    _ = hidden_func(open_location_button, setHidden_sel, true);
    
    std.debug.print("Added all buttons, label, progress bar, and status label to window...\n", .{});
    
    // Make sure the app is active and window is visible
    const activateIgnoringOtherApps_sel = sel_registerName("activateIgnoringOtherApps:");
    const activate_func = @as(*const fn (c.id, c.SEL, bool) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    _ = activate_func(app, activateIgnoringOtherApps_sel, true);
    
    // Show window
    const makeKeyAndOrderFront_sel = sel_registerName("makeKeyAndOrderFront:");
    _ = objc_msgSend_id(window, makeKeyAndOrderFront_sel, null);
    
    std.debug.print("Window should now be visible!\n", .{});
    
    // Set up a proper menu bar with Quit functionality
    const NSMenu = objc_getClass("NSMenu");
    const NSMenuItem = objc_getClass("NSMenuItem");
    const menu_alloc = objc_msgSend(NSMenu, alloc_sel);
    const init_sel = sel_registerName("init");
    const main_menu = objc_msgSend(menu_alloc, init_sel);
    
    // Create App menu
    const app_menu_item_alloc = objc_msgSend(NSMenuItem, alloc_sel);
    const app_menu_item = objc_msgSend(app_menu_item_alloc, init_sel);
    
    const app_submenu_alloc = objc_msgSend(NSMenu, alloc_sel);
    const app_submenu = objc_msgSend(app_submenu_alloc, init_sel);
    
    // Create Generate Cards menu item using proper target/action
    const generate_item_alloc = objc_msgSend(NSMenuItem, alloc_sel);
    const initWithTitle_sel = sel_registerName("initWithTitle:action:keyEquivalent:");
    const generate_title = createNSString("Generate Birthday Cards");
    const generateCards_sel = sel_registerName("generateCards:");
    const cmd_g = createNSString("g");
    
    const generate_func = @as(*const fn (c.id, c.SEL, c.id, c.SEL, c.id) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    const generate_item = generate_func(generate_item_alloc, initWithTitle_sel, generate_title, generateCards_sel, cmd_g);
    
    // Set the target to our custom responder (reuse the same one from button)
    const setTarget_gen_sel = sel_registerName("setTarget:");
    _ = objc_msgSend_id(generate_item, setTarget_gen_sel, responder);
    
    std.debug.print("Created menu item with proper target/action...\n", .{});
    
    // Add generate item to app submenu
    const addItem_sel = sel_registerName("addItem:");
    _ = objc_msgSend_id(app_submenu, addItem_sel, generate_item);
    
    // Add separator
    const separatorItem_sel = sel_registerName("separatorItem");
    const separator = objc_msgSend(NSMenuItem, separatorItem_sel);
    _ = objc_msgSend_id(app_submenu, addItem_sel, separator);
    
    // Create Quit menu item with Cmd+Q
    const quit_item_alloc = objc_msgSend(NSMenuItem, alloc_sel);
    const quit_title = createNSString("Quit Birthday Generator");
    const terminate_sel = sel_registerName("terminate:");
    const cmd_q = createNSString("q");
    
    const quit_func = @as(*const fn (c.id, c.SEL, c.id, c.SEL, c.id) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    const quit_item = quit_func(quit_item_alloc, initWithTitle_sel, quit_title, terminate_sel, cmd_q);
    
    // Set the target for quit to be the application
    const setTarget_quit_sel = sel_registerName("setTarget:");
    _ = objc_msgSend_id(quit_item, setTarget_quit_sel, app);
    
    // Add quit item to app submenu
    _ = objc_msgSend_id(app_submenu, addItem_sel, quit_item);
    
    // Set the submenu
    const setSubmenu_sel = sel_registerName("setSubmenu:");
    _ = objc_msgSend_id(app_menu_item, setSubmenu_sel, app_submenu);
    
    // Add app menu item to main menu
    _ = objc_msgSend_id(main_menu, addItem_sel, app_menu_item);
    
    // Set main menu
    const setMainMenu_sel = sel_registerName("setMainMenu:");
    _ = objc_msgSend_id(app, setMainMenu_sel, main_menu);
    
    std.debug.print("Set up proper menu bar with Cmd+Q quit and Cmd+G generate functionality...\n", .{});
    
    // Run the application
    const run_sel = sel_registerName("run");
    _ = objc_msgSend(app, run_sel);
}