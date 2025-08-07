const std = @import("std");
const objc_helpers = @import("src/objc_helpers.zig");
const threading = @import("src/threading.zig");
const file_operations = @import("src/file_operations.zig");
const ui_components = @import("src/ui_components.zig");
const app_delegate = @import("src/app_delegate.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

pub fn main() !void {
    std.debug.print("Starting GUI application...\n", .{});
    
    // Initialize NSApplication
    const NSApplication = objc_helpers.objc_getClass("NSApplication");
    const sharedApplication_sel = objc_helpers.sel_registerName("sharedApplication");
    const app = objc_helpers.objc_msgSend(NSApplication, sharedApplication_sel);
    
    // Set app activation policy to regular app
    const setActivationPolicy_sel = objc_helpers.sel_registerName("setActivationPolicy:");
    const policy_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, c_long) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    _ = policy_func(app, setActivationPolicy_sel, 0); // NSApplicationActivationPolicyRegular
    
    std.debug.print("Created NSApplication...\n", .{});
    
    // Create window
    const window = ui_components.createWindow();
    
    // Create buttons
    const button = ui_components.createButton(objc_helpers.NSMakeRect(200, 200, 120, 40), "Generate Cards");
    const location_button = ui_components.createButton(objc_helpers.NSMakeRect(330, 200, 120, 40), "Choose Location");
    const open_location_button = ui_components.createButton(objc_helpers.NSMakeRect(200, 250, 120, 40), "Open Location");
    
    // Create instruction label
    const label = ui_components.createLabel(objc_helpers.NSMakeRect(50, 100, 400, 60), "Click 'Generate Cards' or press Cmd+G to create cards\nClick 'Choose Location' to select where to save (default: ~/Downloads)\nPress Cmd+Q to quit the application.");
    
    // Create status label (initially hidden)
    const status_label = ui_components.createLabel(objc_helpers.NSMakeRect(50, 40, 400, 50), "");
    
    // Create progress bar
    const progress_bar = ui_components.createProgressBar(objc_helpers.NSMakeRect(50, 180, 400, 30));
    
    // Store global references for background thread access
    threading.global_progress_bar = progress_bar;
    threading.global_status_label = status_label;
    threading.global_open_location_button = open_location_button;
    
    // Hide progress bar and status label initially
    const setHidden_sel = objc_helpers.sel_registerName("setHidden:");
    const hidden_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    _ = hidden_func(progress_bar, setHidden_sel, true);
    _ = hidden_func(status_label, setHidden_sel, true);
    _ = hidden_func(open_location_button, setHidden_sel, true);
    
    // Create our custom responder that can handle actions
    const responder = app_delegate.createCustomResponder(allocator);
    
    // Connect buttons to custom responder
    const setTarget_sel = objc_helpers.sel_registerName("setTarget:");
    const setAction_sel = objc_helpers.sel_registerName("setAction:");
    
    _ = objc_helpers.objc_msgSend_id(button, setTarget_sel, responder);
    const generateCards_action_sel = objc_helpers.sel_registerName("generateCards:");
    _ = objc_helpers.objc_msgSend_ptr(button, setAction_sel, @ptrCast(generateCards_action_sel));
    
    _ = objc_helpers.objc_msgSend_id(location_button, setTarget_sel, responder);
    const chooseLocation_action_sel = objc_helpers.sel_registerName("chooseLocation:");
    _ = objc_helpers.objc_msgSend_ptr(location_button, setAction_sel, @ptrCast(chooseLocation_action_sel));
    
    _ = objc_helpers.objc_msgSend_id(open_location_button, setTarget_sel, responder);
    const openLocation_action_sel = objc_helpers.sel_registerName("openLocation:");
    _ = objc_helpers.objc_msgSend_ptr(open_location_button, setAction_sel, @ptrCast(openLocation_action_sel));
    
    std.debug.print("Connected all buttons to custom responder...\n", .{});
    
    // Set the window to release when closed
    const setReleasedWhenClosed_sel = objc_helpers.sel_registerName("setReleasedWhenClosed:");
    const bool_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    _ = bool_func(window, setReleasedWhenClosed_sel, true);
    
    // Add UI elements to window
    const contentView_sel = objc_helpers.sel_registerName("contentView");
    const content_view = objc_helpers.objc_msgSend(window, contentView_sel);
    const addSubview_sel = objc_helpers.sel_registerName("addSubview:");
    _ = objc_helpers.objc_msgSend_id(content_view, addSubview_sel, button);
    _ = objc_helpers.objc_msgSend_id(content_view, addSubview_sel, location_button);
    _ = objc_helpers.objc_msgSend_id(content_view, addSubview_sel, label);
    _ = objc_helpers.objc_msgSend_id(content_view, addSubview_sel, progress_bar);
    _ = objc_helpers.objc_msgSend_id(content_view, addSubview_sel, status_label);
    _ = objc_helpers.objc_msgSend_id(content_view, addSubview_sel, open_location_button);
    
    std.debug.print("Added all UI elements to window...\n", .{});
    
    // Create and set up menu
    const main_menu = ui_components.createMenu(responder);
    const setMainMenu_sel = objc_helpers.sel_registerName("setMainMenu:");
    _ = objc_helpers.objc_msgSend_id(app, setMainMenu_sel, main_menu);
    
    // Make app active and show window
    const activateIgnoringOtherApps_sel = objc_helpers.sel_registerName("activateIgnoringOtherApps:");
    const activate_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    _ = activate_func(app, activateIgnoringOtherApps_sel, true);
    
    const makeKeyAndOrderFront_sel = objc_helpers.sel_registerName("makeKeyAndOrderFront:");
    _ = objc_helpers.objc_msgSend_id(window, makeKeyAndOrderFront_sel, null);
    
    std.debug.print("Window should now be visible!\n", .{});
    std.debug.print("Set up proper menu bar with Cmd+Q quit and Cmd+G generate functionality...\n", .{});
    
    // Run the application
    const run_sel = objc_helpers.sel_registerName("run");
    _ = objc_helpers.objc_msgSend(app, run_sel);
}
