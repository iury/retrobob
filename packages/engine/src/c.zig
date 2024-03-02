const std = @import("std");
const builtin = @import("builtin");

pub usingnamespace @cImport({
    @cInclude("mpack.h");
    @cInclude("raylib.h");
    @cInclude("blip_buf.h");
    if (builtin.os.tag == .emscripten) {
        @cInclude("emscripten/html5.h");
    }
});

pub const Event = enum(u32) {
    core_loaded = 1,
    game_loaded = 2,
    load_failed = 92,
    game_resumed = 3,
    game_paused = 4,
    game_reset = 5,
    region_changed = 8,
    core_unloaded = 9,
    slot_changed = 11,
    state_saved = 12,
    state_loaded = 13,
    battery_persisted = 14,
    ratio_changed = 22,
    zoom_changed = 23,
    has_battery = 73,
    region_support = 79,
    end_frame = 99,
};

var notifyEventFn: ?*const fn (u32, u32) void = null;

pub fn notifyEvent(event: Event, value: u32) void {
    if (event != .end_frame) {
        std.debug.print("Notification {s} with value {d} sent.\n", .{ std.enums.tagName(Event, event).?, value });
    }
    if (notifyEventFn) |f| f(@intFromEnum(event), value);
}

export fn setNotifyEventFn(fid: u32) void {
    notifyEventFn = @ptrFromInt(fid);
}
