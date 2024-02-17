pub fn Proxy(comptime T: anytype) type {
    return struct {
        const Self = @This();

        ptr: *anyopaque,
        vtable: *const VTable,

        pub const VTable = struct {
            get: *const fn (ctx: *anyopaque) T,
            set: *const fn (ctx: *anyopaque, value: T) void,
        };

        pub fn get(self: *Self) T {
            return self.vtable.get(self.ptr);
        }

        pub fn set(self: *Self, value: T) void {
            self.vtable.set(self.ptr, value);
        }
    };
}
