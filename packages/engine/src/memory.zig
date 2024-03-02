const std = @import("std");
const c = @import("c.zig");

pub fn Memory(comptime Address: anytype, comptime Value: anytype) type {
    return struct {
        const Self = @This();

        ptr: *anyopaque,
        vtable: *const VTable,

        pub const VTable = struct {
            read: *const fn (ctx: *anyopaque, address: Address) Value,
            write: *const fn (ctx: *anyopaque, address: Address, value: Value) void,
            deinit: *const fn (ctx: *anyopaque) void,
            serialize: ?*const fn (self: *const anyopaque, pack: *c.mpack_writer_t) void = null,
            deserialize: ?*const fn (self: *anyopaque, pack: c.mpack_node_t) void = null,
        };

        pub fn read(self: *Self, address: Address) Value {
            return self.vtable.read(self.ptr, address);
        }

        pub fn write(self: *Self, address: Address, value: Value) void {
            self.vtable.write(self.ptr, address, value);
        }

        pub fn deinit(self: *Self) void {
            self.vtable.deinit(self.ptr);
        }

        pub fn serialize(self: *const Self, pack: *c.mpack_writer_t) void {
            if (self.vtable.serialize) |f| f(self.ptr, pack);
        }

        pub fn deserialize(self: *Self, pack: c.mpack_node_t) void {
            if (self.vtable.deserialize) |f| f(self.ptr, pack);
        }
    };
}
