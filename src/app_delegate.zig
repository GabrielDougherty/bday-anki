const std = @import("std");
const objc_helpers = @import("objc_helpers.zig");
const threading = @import("threading.zig");
const file_operations = @import("file_operations.zig");
const anki_generator = @import("anki_generator.zig");
const main = @import("../main.zig");

// Background thread function for card generation
pub fn backgroundCardGeneration(allocator: std.mem.Allocator) void {
    std.debug.print("Running card generation in background thread...\n", .{});
    
    // Show progress bar
    threading.showProgressBar();
    
    // Check for --debug flag
    const args = std.process.argsAlloc(allocator) catch {
        threading.hideProgressBar();
        threading.updateStatusLabel("Error: Failed to parse command line arguments.", allocator);
        return;
    };
    defer std.process.argsFree(allocator, args);

    var debug_mode = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--debug")) {
            debug_mode = true;
            break;
        }
    }
    
    // Run the card generation
    const result = anki_generator.fetchContactsData(allocator, debug_mode);
    
    // Hide progress bar when done
    threading.hideProgressBar();
    
    // Update status label with result
    if (result) |status_message| {
        threading.updateStatusLabel(status_message, allocator);
        // Show the "Open Location" button after successful generation
        threading.showOpenLocationButton();
        std.debug.print("Card generation completed successfully.\n", .{});
    } else {
        threading.updateStatusLabel("Error: Failed to generate cards. Please check permissions and try again.", allocator);
        std.debug.print("Card generation failed.\n", .{});
    }
}

// Create a custom class that can respond to button/menu actions
pub fn createCustomResponder(allocator: std.mem.Allocator) objc_helpers.objc.id {
    _ = allocator; // Suppress unused parameter warning
    // Get the NSObject class as our base
    const NSObject = objc_helpers.objc_getClass("NSObject");
    
    // Create a new class that inherits from NSObject
    const CustomResponder = objc_helpers.objc.objc_allocateClassPair(NSObject, "CustomResponder", 0);
    
    // Add our method to the class for generating cards
    const generateCards_sel = objc_helpers.sel_registerName("generateCards:");
    const method_impl = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.objc.id) callconv(.C) void, @ptrCast(&generateCardsImpl));
    
    const success1 = objc_helpers.objc.class_addMethod(CustomResponder, generateCards_sel, 
        @as(objc_helpers.objc.IMP, @ptrCast(method_impl)), "v@:@");
    
    if (!success1) {
        std.debug.print("Failed to add generateCards method to custom class\n", .{});
    }
    
    // Add method for choosing location
    const chooseLocation_sel = objc_helpers.sel_registerName("chooseLocation:");
    const location_method_impl = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.objc.id) callconv(.C) void, @ptrCast(&chooseLocationImpl));
    
    const success2 = objc_helpers.objc.class_addMethod(CustomResponder, chooseLocation_sel, 
        @as(objc_helpers.objc.IMP, @ptrCast(location_method_impl)), "v@:@");
    
    if (!success2) {
        std.debug.print("Failed to add chooseLocation method to custom class\n", .{});
    }
    
    // Add method for opening file location
    const openLocation_sel = objc_helpers.sel_registerName("openLocation:");
    const open_method_impl = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.objc.id) callconv(.C) void, @ptrCast(&openLocationImpl));
    
    const success3 = objc_helpers.objc.class_addMethod(CustomResponder, openLocation_sel, 
        @as(objc_helpers.objc.IMP, @ptrCast(open_method_impl)), "v@:@");
    
    if (!success3) {
        std.debug.print("Failed to add openLocation method to custom class\n", .{});
    }
    
    // Register the class
    objc_helpers.objc.objc_registerClassPair(CustomResponder);
    
    // Create an instance
    const alloc_sel = objc_helpers.sel_registerName("alloc");
    const init_sel = objc_helpers.sel_registerName("init");
    const instance_alloc = objc_helpers.objc_msgSend(CustomResponder, alloc_sel);
    const instance = objc_helpers.objc_msgSend(instance_alloc, init_sel);
    
    std.debug.print("Created custom responder class and instance\n", .{});
    return instance;
}

// Window delegate to handle window closing
export fn windowShouldClose(_: objc_helpers.objc.id, _: objc_helpers.objc.SEL) bool {
    std.debug.print("Window closing, terminating app...\n", .{});
    
    // Get NSApplication and terminate
    const NSApplication = objc_helpers.objc_getClass("NSApplication");
    const sharedApplication_sel = objc_helpers.sel_registerName("sharedApplication");
    const app = objc_helpers.objc_msgSend(NSApplication, sharedApplication_sel);
    
    const terminate_sel = objc_helpers.sel_registerName("terminate:");
    _ = objc_helpers.objc_msgSend_id(app, terminate_sel, null);
    
    return true;
}

// Implementation function that will be called by the Objective-C runtime
export fn generateCardsImpl(self: objc_helpers.objc.id, _cmd: objc_helpers.objc.SEL, sender: objc_helpers.objc.id) void {
    _ = self;
    _ = _cmd; 
    _ = sender;
    std.debug.print("Custom responder generateCards called!\n", .{});
    
    // Use the shared global allocator instead of creating a new one
    const allocator = main.allocator;
    
    // Create a background thread to run the card generation
    const thread = std.Thread.spawn(.{}, backgroundCardGenerationWrapper, .{allocator}) catch |err| {
        std.debug.print("Failed to create background thread: {}\n", .{err});
        return;
    };
    
    // Detach the thread so it cleans up automatically
    thread.detach();
}

fn backgroundCardGenerationWrapper(allocator: std.mem.Allocator) void {
    backgroundCardGeneration(allocator);
}

// Implementation function for location selection
export fn chooseLocationImpl(self: objc_helpers.objc.id, _cmd: objc_helpers.objc.SEL, sender: objc_helpers.objc.id) void {
    _ = self;
    _ = _cmd; 
    _ = sender;
    std.debug.print("Custom responder chooseLocation called!\n", .{});
    
    // Show the save panel
    file_operations.showSavePanel();
}

// Implementation function for opening file location
export fn openLocationImpl(self: objc_helpers.objc.id, _cmd: objc_helpers.objc.SEL, sender: objc_helpers.objc.id) void {
    _ = self;
    _ = _cmd; 
    _ = sender;
    std.debug.print("Custom responder openLocation called!\n", .{});
    
    // Open the file location
    file_operations.openFileLocation();
}
