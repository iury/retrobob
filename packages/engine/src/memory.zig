const std = @import("std");

pub fn Memory(comptime Address: anytype, comptime Value: anytype) type {
    return struct {
        const Self = @This();

        ptr: *anyopaque,
        vtable: *const VTable,

        pub const VTable = struct {
            read: *const fn (ctx: *anyopaque, address: Address) Value,
            write: *const fn (ctx: *anyopaque, address: Address, value: Value) void,
            deinit: *const fn (ctx: *anyopaque) void,
            jsonStringify: ?*const fn (ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!std.json.Value = null,
            jsonParse: ?*const fn (ctx: *anyopaque, allocator: std.mem.Allocator, value: std.json.Value) anyerror!void = null,
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

        pub fn jsonStringify(self: *const Self, allocator: std.mem.Allocator) !std.json.Value {
            if (self.vtable.jsonStringify) |f| return try f(self.ptr, allocator);
            return .null;
        }

        pub fn jsonParse(self: *Self, allocator: std.mem.Allocator, value: std.json.Value) !void {
            if (self.vtable.jsonParse) |f| try f(self.ptr, allocator, value);
        }
    };
}
