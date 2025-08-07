const std = @import("std");
const objc_helpers = @import("objc_helpers.zig");

pub fn createWindow() objc_helpers.objc.id {
    std.debug.print("Creating window...\n", .{});
    
    // Create window with larger size and centered position
    const NSWindow = objc_helpers.objc_getClass("NSWindow");
    const alloc_sel = objc_helpers.sel_registerName("alloc");
    const window_alloc = objc_helpers.objc_msgSend(NSWindow, alloc_sel);
    
    const initWithContentRect_sel = objc_helpers.sel_registerName("initWithContentRect:styleMask:backing:defer:");
    const window_rect = objc_helpers.NSMakeRect(200, 200, 500, 400); // Larger and more centered
    const style_mask = objc_helpers.NSWindowStyleMaskTitled | objc_helpers.NSWindowStyleMaskClosable | objc_helpers.NSWindowStyleMaskResizable;
    
    // This is complex due to the function signature, let's use a simpler approach
    const func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.NSRect, c_ulong, c_ulong, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    const window = func(window_alloc, initWithContentRect_sel, window_rect, style_mask, objc_helpers.NSBackingStoreBuffered, false);
    
    // Set window title
    const setTitle_sel = objc_helpers.sel_registerName("setTitle:");
    const title = objc_helpers.createNSString("Birthday Card Generator");
    _ = objc_helpers.objc_msgSend_id(window, setTitle_sel, title);
    
    // Center the window
    const center_sel = objc_helpers.sel_registerName("center");
    _ = objc_helpers.objc_msgSend(window, center_sel);
    
    std.debug.print("Window created and configured...\n", .{});
    
    return window;
}

pub fn createButton(frame: objc_helpers.NSRect, title: [*:0]const u8) objc_helpers.objc.id {
    const NSButton = objc_helpers.objc_getClass("NSButton");
    const alloc_sel = objc_helpers.sel_registerName("alloc");
    const button_alloc = objc_helpers.objc_msgSend(NSButton, alloc_sel);
    
    const initWithFrame_sel = objc_helpers.sel_registerName("initWithFrame:");
    const button_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.NSRect) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    const button = button_func(button_alloc, initWithFrame_sel, frame);
    
    // Set button title
    const setTitle_sel = objc_helpers.sel_registerName("setTitle:");
    const button_title = objc_helpers.createNSString(title);
    _ = objc_helpers.objc_msgSend_id(button, setTitle_sel, button_title);
    
    // Set button style
    const setBezelStyle_sel = objc_helpers.sel_registerName("setBezelStyle:");
    const bezel_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, c_ulong) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    _ = bezel_func(button, setBezelStyle_sel, objc_helpers.NSBezelStyleRounded);
    
    return button;
}

pub fn createLabel(frame: objc_helpers.NSRect, text: [*:0]const u8) objc_helpers.objc.id {
    const NSTextField = objc_helpers.objc_getClass("NSTextField");
    const alloc_sel = objc_helpers.sel_registerName("alloc");
    const label_alloc = objc_helpers.objc_msgSend(NSTextField, alloc_sel);
    
    const initWithFrame_sel = objc_helpers.sel_registerName("initWithFrame:");
    const label_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.NSRect) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    const label = label_func(label_alloc, initWithFrame_sel, frame);
    
    // Set label properties
    const setStringValue_sel = objc_helpers.sel_registerName("setStringValue:");
    const label_text = objc_helpers.createNSString(text);
    _ = objc_helpers.objc_msgSend_id(label, setStringValue_sel, label_text);
    
    const setBezeled_sel = objc_helpers.sel_registerName("setBezeled:");
    const bezeled_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    _ = bezeled_func(label, setBezeled_sel, false);
    
    const setEditable_sel = objc_helpers.sel_registerName("setEditable:");
    const editable_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    _ = editable_func(label, setEditable_sel, false);
    
    return label;
}

pub fn createProgressBar(frame: objc_helpers.NSRect) objc_helpers.objc.id {
    const NSProgressIndicator = objc_helpers.objc_getClass("NSProgressIndicator");
    const alloc_sel = objc_helpers.sel_registerName("alloc");
    const progress_alloc = objc_helpers.objc_msgSend(NSProgressIndicator, alloc_sel);
    
    const initWithFrame_sel = objc_helpers.sel_registerName("initWithFrame:");
    const progress_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.NSRect) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    const progress_bar = progress_func(progress_alloc, initWithFrame_sel, frame);
    
    // Configure progress bar
    const setStyle_sel = objc_helpers.sel_registerName("setStyle:");
    const style_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, c_ulong) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    _ = style_func(progress_bar, setStyle_sel, 0); // NSProgressIndicatorStyleBar
    
    const setIndeterminate_sel = objc_helpers.sel_registerName("setIndeterminate:");
    const indeterminate_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, bool) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    _ = indeterminate_func(progress_bar, setIndeterminate_sel, true);
    
    return progress_bar;
}

pub fn createMenu(responder: objc_helpers.objc.id) objc_helpers.objc.id {
    // Set up a proper menu bar with Quit functionality
    const NSMenu = objc_helpers.objc_getClass("NSMenu");
    const NSMenuItem = objc_helpers.objc_getClass("NSMenuItem");
    const alloc_sel = objc_helpers.sel_registerName("alloc");
    const init_sel = objc_helpers.sel_registerName("init");
    const menu_alloc = objc_helpers.objc_msgSend(NSMenu, alloc_sel);
    const main_menu = objc_helpers.objc_msgSend(menu_alloc, init_sel);
    
    // Create App menu
    const app_menu_item_alloc = objc_helpers.objc_msgSend(NSMenuItem, alloc_sel);
    const app_menu_item = objc_helpers.objc_msgSend(app_menu_item_alloc, init_sel);
    
    const app_submenu_alloc = objc_helpers.objc_msgSend(NSMenu, alloc_sel);
    const app_submenu = objc_helpers.objc_msgSend(app_submenu_alloc, init_sel);
    
    // Create Generate Cards menu item using proper target/action
    const generate_item_alloc = objc_helpers.objc_msgSend(NSMenuItem, alloc_sel);
    const initWithTitle_sel = objc_helpers.sel_registerName("initWithTitle:action:keyEquivalent:");
    const generate_title = objc_helpers.createNSString("Generate Birthday Cards");
    const generateCards_sel = objc_helpers.sel_registerName("generateCards:");
    const cmd_g = objc_helpers.createNSString("g");
    
    const generate_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.objc.id) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    const generate_item = generate_func(generate_item_alloc, initWithTitle_sel, generate_title, generateCards_sel, cmd_g);
    
    // Set the target to our custom responder
    const setTarget_sel = objc_helpers.sel_registerName("setTarget:");
    _ = objc_helpers.objc_msgSend_id(generate_item, setTarget_sel, responder);
    
    // Add generate item to app submenu
    const addItem_sel = objc_helpers.sel_registerName("addItem:");
    _ = objc_helpers.objc_msgSend_id(app_submenu, addItem_sel, generate_item);
    
    // Add separator
    const separatorItem_sel = objc_helpers.sel_registerName("separatorItem");
    const separator = objc_helpers.objc_msgSend(NSMenuItem, separatorItem_sel);
    _ = objc_helpers.objc_msgSend_id(app_submenu, addItem_sel, separator);
    
    // Create Quit menu item with Cmd+Q
    const quit_item_alloc = objc_helpers.objc_msgSend(NSMenuItem, alloc_sel);
    const quit_title = objc_helpers.createNSString("Quit Birthday Generator");
    const terminate_sel = objc_helpers.sel_registerName("terminate:");
    const cmd_q = objc_helpers.createNSString("q");
    
    const quit_func = @as(*const fn (objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.objc.id, objc_helpers.objc.SEL, objc_helpers.objc.id) callconv(.C) objc_helpers.objc.id, @ptrCast(&objc_helpers.objc.objc_msgSend));
    const quit_item = quit_func(quit_item_alloc, initWithTitle_sel, quit_title, terminate_sel, cmd_q);
    
    // Set the target for quit to be the application
    const NSApplication = objc_helpers.objc_getClass("NSApplication");
    const sharedApplication_sel = objc_helpers.sel_registerName("sharedApplication");
    const app = objc_helpers.objc_msgSend(NSApplication, sharedApplication_sel);
    _ = objc_helpers.objc_msgSend_id(quit_item, setTarget_sel, app);
    
    // Add quit item to app submenu
    _ = objc_helpers.objc_msgSend_id(app_submenu, addItem_sel, quit_item);
    
    // Set the submenu
    const setSubmenu_sel = objc_helpers.sel_registerName("setSubmenu:");
    _ = objc_helpers.objc_msgSend_id(app_menu_item, setSubmenu_sel, app_submenu);
    
    // Add app menu item to main menu
    _ = objc_helpers.objc_msgSend_id(main_menu, addItem_sel, app_menu_item);
    
    return main_menu;
}
