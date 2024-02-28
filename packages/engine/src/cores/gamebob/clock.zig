const std = @import("std");
const Proxy = @import("../../proxy.zig").Proxy;

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

        pub fn jsonStringify(self: *const Self, jw: anytype) !void {
            try jw.beginObject();
            try jw.objectField("double_speed");
            try jw.write(self.double_speed);
            try jw.objectField("cpu_counter");
            try jw.write(self.cpu_counter);
            try jw.endObject();
        }

        pub fn jsonParse(self: *Self, value: std.json.Value) void {
            self.double_speed = value.object.get("double_speed").?.bool;
            self.cpu_counter = @intCast(value.object.get("cpu_counter").?.integer);
        }
    };
}
