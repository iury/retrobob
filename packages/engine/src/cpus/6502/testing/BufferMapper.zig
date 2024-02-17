const Memory = @import("../../../memory.zig").Memory;

data: [0x10000]u8 = [_]u8{0} ** 0x10000,

pub fn read(ctx: *anyopaque, address: u16) u8 {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    return self.data[address];
}

pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
    const self: *@This() = @ptrCast(@alignCast(ctx));
    self.data[address] = value;
}

pub fn deinit(ctx: *anyopaque) void {
    _ = ctx;
}

pub fn memory(self: *@This()) Memory(u16, u8) {
    return .{
        .ptr = self,
        .vtable = &.{
            .read = read,
            .write = write,
            .deinit = deinit,
        },
    };
}
