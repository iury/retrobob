const std = @import("std");
const Proxy = @import("../../proxy.zig").Proxy;
const c = @import("../../c.zig");

pub const RunOption = enum { frame, cpu_cycle, ppu_cycle };

pub fn Clock(comptime T: anytype) type {
    return struct {
        const Self = @This();

        handler: *T,
        double_speed: bool = false,
        frame_cycles: u32 = 70224,
        cpu_divider: u32 = 4,
        cpu_counter: u32 = 0,

        pub fn reset(self: *Self) void {
            Self.set(self, false);
            self.cpu_counter = 0;
        }

        pub fn run(self: *Self, option: RunOption) void {
            switch (option) {
                .frame => {
                    for (0..self.frame_cycles) |_| {
                        self.handler.handlePPUCycle();
                        self.handler.handleAPUCycle();
                        self.cpu_counter += 1;
                        if (self.cpu_counter == self.cpu_divider) {
                            self.cpu_counter = 0;
                            self.handler.handleCPUCycle();
                        }
                    }
                },

                .cpu_cycle => {
                    while (true) {
                        self.handler.handlePPUCycle();
                        self.handler.handleAPUCycle();
                        self.cpu_counter += 1;
                        if (self.cpu_counter == self.cpu_divider) {
                            self.cpu_counter = 0;
                            self.handler.handleCPUCycle();
                            break;
                        }
                    }
                },

                .ppu_cycle => {
                    self.handler.handlePPUCycle();
                    self.handler.handleAPUCycle();
                    self.cpu_counter += 1;
                    if (self.cpu_counter == self.cpu_divider) {
                        self.cpu_counter = 0;
                        self.handler.handleCPUCycle();
                    }
                },
            }
        }

        pub fn get(ctx: *anyopaque) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.double_speed;
        }

        pub fn set(ctx: *anyopaque, data: bool) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.double_speed = data;
            self.cpu_divider = if (self.double_speed) 2 else 4;
        }

        pub fn proxy(self: *Self) Proxy(bool) {
            return .{
                .ptr = self,
                .vtable = &.{
                    .get = get,
                    .set = set,
                },
            };
        }

        pub fn serialize(self: *const Self, pack: *c.mpack_writer_t) void {
            c.mpack_build_map(pack);
            c.mpack_write_cstr(pack, "double_speed");
            c.mpack_write_bool(pack, self.double_speed);
            c.mpack_write_cstr(pack, "cpu_counter");
            c.mpack_write_u32(pack, self.cpu_counter);
            c.mpack_complete_map(pack);
        }

        pub fn deserialize(self: *Self, pack: c.mpack_node_t) void {
            self.double_speed = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "double_speed"));
            self.cpu_counter = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "cpu_counter"));
        }
    };
}
