const std = @import("std");
const objc_helpers = @import("objc_helpers.zig");
const threading = @import("threading.zig");

// Global reference to store the selected output path
pub var global_output_path: ?[]const u8 = null;

// Function to show save panel dialog
pub fn showSavePanel() void {
    const main_queue = objc_helpers.getMainQueue();
    objc_helpers.objc.dispatch_async_f(main_queue, null, showSavePanelOnMainThread);
}

// Function to open the file location in Finder
pub fn openFileLocation() void {
    const main_queue = objc_helpers.getMainQueue();
    objc_helpers.objc.dispatch_async_f(main_queue, null, openFileLocationOnMainThread);
}

export fn showSavePanelOnMainThread(context: ?*anyopaque) callconv(.C) void {
    _ = context; // Unused
    
    std.debug.print("Showing save panel on main thread...\n", .{});
    
    // Create NSSavePanel
    const NSSavePanel = objc_helpers.objc_getClass("NSSavePanel");
    const savePanel_sel = objc_helpers.sel_registerName("savePanel");
    const save_panel = objc_helpers.objc_msgSend(NSSavePanel, savePanel_sel);
    
    // Set default filename
    const setNameFieldStringValue_sel = objc_helpers.sel_registerName("setNameFieldStringValue:");
    const default_name = objc_helpers.createNSString("birthdays.txt");
    _ = objc_helpers.objc_msgSend_id(save_panel, setNameFieldStringValue_sel, default_name);
    
    // Set title
    const setTitle_sel = objc_helpers.sel_registerName("setTitle:");
    const title = objc_helpers.createNSString("Save Birthday Cards");
    _ = objc_helpers.objc_msgSend_id(save_panel, setTitle_sel, title);
    
    // Set message
    const setMessage_sel = objc_helpers.sel_registerName("setMessage:");
    const message = objc_helpers.createNSString("Choose where to save the birthday cards file:");
    _ = objc_helpers.objc_msgSend_id(save_panel, setMessage_sel, message);
    
    // Set default directory to Downloads
    const home_dir = std.posix.getenv("HOME") orelse "/tmp";
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
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
    
    const NSURL = objc_helpers.objc_getClass("NSURL");
    const fileURLWithPath_sel = objc_helpers.sel_registerName("fileURLWithPath:");
    const downloads_nsstring = objc_helpers.createNSString(downloads_path_z.ptr);
    const downloads_url = objc_helpers.objc_msgSend_id(NSURL, fileURLWithPath_sel, downloads_nsstring);
    
    const setDirectoryURL_sel = objc_helpers.sel_registerName("setDirectoryURL:");
    _ = objc_helpers.objc_msgSend_id(save_panel, setDirectoryURL_sel, downloads_url);
    
    // Run the panel modally
    const runModal_sel = objc_helpers.sel_registerName("runModal");
    const response_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL) callconv(.C) c_long, @ptrCast(&objc_helpers.objc.objc_msgSend));
    const response = response_func(save_panel, runModal_sel);
    
    // NSModalResponseOK = 1
    if (response == 1) {
        // Get the selected URL
        const URL_sel = objc_helpers.sel_registerName("URL");
        const selected_url = objc_helpers.objc_msgSend(save_panel, URL_sel);
        
        if (selected_url != null) {
            // Get the path from URL
            const path_sel = objc_helpers.sel_registerName("path");
            const path_nsstring = objc_helpers.objc_msgSend(selected_url, path_sel);
            
            // Convert NSString to C string
            const UTF8String_sel = objc_helpers.sel_registerName("UTF8String");
            const path_cstring_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL) callconv(.C) [*:0]const u8, @ptrCast(&objc_helpers.objc.objc_msgSend));
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
    const NSWorkspace = objc_helpers.objc_getClass("NSWorkspace");
    const sharedWorkspace_sel = objc_helpers.sel_registerName("sharedWorkspace");
    const workspace = objc_helpers.objc_msgSend(NSWorkspace, sharedWorkspace_sel);
    
    // Create NSURL for the directory
    const NSURL = objc_helpers.objc_getClass("NSURL");
    const fileURLWithPath_sel = objc_helpers.sel_registerName("fileURLWithPath:");
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Create null-terminated path
    const path_z = allocator.dupeZ(u8, path_to_open) catch {
        std.debug.print("Failed to create null-terminated path\n", .{});
        return;
    };
    defer allocator.free(path_z);
    
    const path_nsstring = objc_helpers.createNSString(path_z.ptr);
    const directory_url = objc_helpers.objc_msgSend_id(NSURL, fileURLWithPath_sel, path_nsstring);
    
    // Open the directory in Finder
    const openURL_sel = objc_helpers.sel_registerName("openURL:");
    const success_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.objc.id) callconv(.C) bool, @ptrCast(&objc_helpers.objc.objc_msgSend));
    const success = success_func(workspace, openURL_sel, directory_url);
    
    if (success) {
        std.debug.print("Successfully opened directory: {s}\n", .{path_to_open});
    } else {
        std.debug.print("Failed to open directory: {s}\n", .{path_to_open});
    }
}
