const std = @import("std");
const objc_helpers = @import("objc_helpers.zig");
const main = @import("../main.zig");

// Global references for UI updates
pub var global_progress_bar: ?objc_helpers.objc.id = null;
pub var global_status_label: ?objc_helpers.objc.id = null;
pub var global_open_location_button: ?objc_helpers.objc.id = null;

// Progress bar control functions (dispatch to main thread)
pub fn showProgressBar() void {
    const main_queue = objc_helpers.getMainQueue();
    objc_helpers.objc.dispatch_async_f(main_queue, null, showProgressBarOnMainThread);
}

pub fn hideProgressBar() void {
    const main_queue = objc_helpers.getMainQueue();
    objc_helpers.objc.dispatch_async_f(main_queue, null, hideProgressBarOnMainThread);
}

// Status label update function (dispatch to main thread)
pub fn updateStatusLabel(message: []const u8, allocator: std.mem.Allocator) void {
    // Allocate context on heap and store the message
    const context = allocator.dupe(u8, message) catch {
        std.debug.print("Failed to allocate context for status update\n", .{});
        return;
    };
    
    const main_queue = objc_helpers.getMainQueue();
    objc_helpers.objc.dispatch_async_f(main_queue, context.ptr, updateStatusLabelOnMainThread);
}

// Function to show the "Open Location" button after generation completes
pub fn showOpenLocationButton() void {
    const main_queue = objc_helpers.getMainQueue();
    objc_helpers.objc.dispatch_async_f(main_queue, null, showOpenLocationButtonOnMainThread);
}

// Progress value setting (dispatch to main thread)
pub fn setProgressValue(value: f64, max_value: f64, allocator: std.mem.Allocator) void {
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
    
    const main_queue = objc_helpers.getMainQueue();
    objc_helpers.objc.dispatch_async_f(main_queue, context, setProgressValueOnMainThread);
}

// Functions that actually update the UI (must run on main thread)
export fn showProgressBarOnMainThread(context: ?*anyopaque) callconv(.C) void {
    _ = context; // Unused
    if (global_progress_bar) |progress_bar| {
        std.debug.print("Showing progress bar on main thread...\n", .{});
        
        // Show progress bar
        const setHidden_sel = objc_helpers.sel_registerName("setHidden:");
        const hidden_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
        _ = hidden_func(progress_bar, setHidden_sel, false);
        
        // Start animation for indeterminate progress
        const startAnimation_sel = objc_helpers.sel_registerName("startAnimation:");
        _ = objc_helpers.objc_msgSend_id(progress_bar, startAnimation_sel, null);
        
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
        const stopAnimation_sel = objc_helpers.sel_registerName("stopAnimation:");
        _ = objc_helpers.objc_msgSend_id(progress_bar, stopAnimation_sel, null);
        
        // Hide progress bar
        const setHidden_sel = objc_helpers.sel_registerName("setHidden:");
        const hidden_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
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
            // We need an allocator here - using a page allocator for this specific case
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            const allocator = gpa.allocator();
            
            const null_terminated = allocator.dupeZ(u8, message) catch {
                std.debug.print("Failed to create null-terminated string\n", .{});
                return;
            };
            defer allocator.free(null_terminated);
            
            const status_string = objc_helpers.createNSString(null_terminated.ptr);
            
            // Update the label text
            const setStringValue_sel = objc_helpers.sel_registerName("setStringValue:");
            _ = objc_helpers.objc_msgSend_id(status_label, setStringValue_sel, status_string);
            
            // Make the label visible
            const setHidden_sel = objc_helpers.sel_registerName("setHidden:");
            const hidden_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
            _ = hidden_func(status_label, setHidden_sel, false);
            
        } else {
            std.debug.print("Global status label is null!\n", .{});
        }
        
        // Free the allocated message using the same allocator that was used to create it
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        allocator.free(message);
    }
}

export fn showOpenLocationButtonOnMainThread(context: ?*anyopaque) callconv(.C) void {
    _ = context; // Unused
    
    if (global_open_location_button) |open_button| {
        std.debug.print("Showing open location button on main thread...\n", .{});
        
        // Make the button visible
        const setHidden_sel = objc_helpers.sel_registerName("setHidden:");
        const hidden_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
        _ = hidden_func(open_button, setHidden_sel, false);
    } else {
        std.debug.print("Global open location button is null!\n", .{});
    }
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
        
        // Free the context using the shared allocator
        main.allocator.destroy(context);
        
        if (global_progress_bar) |progress_bar| {
            // Switch to determinate mode if needed
            const setIndeterminate_sel = objc_helpers.sel_registerName("setIndeterminate:");
            const indeterminate_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
            _ = indeterminate_func(progress_bar, setIndeterminate_sel, false);
            
            // Set max value
            const setMaxValue_sel = objc_helpers.sel_registerName("setMaxValue:");
            const max_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, f64) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
            _ = max_func(progress_bar, setMaxValue_sel, max_value);
            
            // Set current value
            const setDoubleValue_sel = objc_helpers.sel_registerName("setDoubleValue:");
            const value_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, f64) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
            _ = value_func(progress_bar, setDoubleValue_sel, value);
            
            std.debug.print("Set progress value to {}/{} on main thread\n", .{value, max_value});
        }
    }
}
