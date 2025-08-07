const std = @import("std");
const c = @cImport({
    @cInclude("objc/objc.h");
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
    @cInclude("dispatch/dispatch.h");
    @cDefine("OBJC_OLD_DISPATCH_PROTOTYPES", "0");
});

// Objective-C runtime helpers
pub fn objc_getClass(name: [*:0]const u8) c.Class {
    return @as(c.Class, @ptrCast(c.objc_getClass(name)));
}

pub fn sel_registerName(name: [*:0]const u8) c.SEL {
    return @as(c.SEL, @ptrCast(c.sel_registerName(name)));
}

pub fn objc_msgSend(target: anytype, sel: c.SEL) c.id {
    const func = @as(*const fn (c.id, c.SEL) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    return func(@as(c.id, @alignCast(@ptrCast(target))), sel);
}

pub fn objc_msgSend_stret(target: anytype, sel: c.SEL, comptime RetType: type) RetType {
    const func = @as(*const fn (c.id, c.SEL) callconv(.C) RetType, @ptrCast(&c.objc_msgSend));
    return func(@as(c.id, @alignCast(@ptrCast(target))), sel);
}

pub fn objc_msgSend_id(target: anytype, sel: c.SEL, arg: c.id) c.id {
    const func = @as(*const fn (c.id, c.SEL, c.id) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    return func(@as(c.id, @alignCast(@ptrCast(target))), sel, arg);
}

pub fn objc_msgSend_ptr(target: anytype, sel: c.SEL, arg: ?*const anyopaque) c.id {
    const func = @as(*const fn (c.id, c.SEL, ?*const anyopaque) callconv(.C) c.id, @ptrCast(&c.objc_msgSend));
    return func(@as(c.id, @alignCast(@ptrCast(target))), sel, arg);
}

// Cocoa constants
pub const NSWindowStyleMaskTitled: c_ulong = 1 << 0;
pub const NSWindowStyleMaskClosable: c_ulong = 1 << 1;
pub const NSWindowStyleMaskResizable: c_ulong = 1 << 3;
pub const NSBackingStoreBuffered: c_ulong = 2;
pub const NSBezelStyleRounded: c_ulong = 1;

// NSRect structure
pub const NSRect = extern struct {
    origin: NSPoint,
    size: NSSize,
};

pub const NSPoint = extern struct {
    x: f64,
    y: f64,
};

pub const NSSize = extern struct {
    width: f64,
    height: f64,
};

pub fn NSMakeRect(x: f64, y: f64, w: f64, h: f64) NSRect {
    return NSRect{
        .origin = NSPoint{ .x = x, .y = y },
        .size = NSSize{ .width = w, .height = h },
    };
}

pub fn createNSString(text: [*:0]const u8) c.id {
    const NSString = objc_getClass("NSString");
    const alloc_sel = sel_registerName("alloc");
    const initWithUTF8String_sel = sel_registerName("initWithUTF8String:");
    
    const string_alloc = objc_msgSend(NSString, alloc_sel);
    return objc_msgSend_ptr(string_alloc, initWithUTF8String_sel, text);
}

// Helper function to cast dispatch queue
pub fn getMainQueue() c.dispatch_queue_t {
    return c.dispatch_get_main_queue();
}

// Re-export the c import for use by other modules
pub const objc = c;
