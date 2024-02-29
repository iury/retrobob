const std = @import("std");

pub const RTC = struct {
    const Self = @This();

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        tick: *const fn (ctx: *anyopaque) void,
    };

    pub fn tick(self: *Self) void {
        return self.vtable.tick(self.ptr);
    }
};
