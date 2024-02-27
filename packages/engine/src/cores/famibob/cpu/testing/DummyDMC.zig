const Proxy = @import("../../../../proxy.zig").Proxy;

data: u8 = 0,

pub fn get(ctx: *anyopaque) u8 {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    return self.data;
}

pub fn set(ctx: *anyopaque, data: u8) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.data = data;
}

pub fn proxy(self: *@This()) Proxy(u8) {
    return .{
        .ptr = self,
        .vtable = &.{
            .get = get,
            .set = set,
        },
    };
}
