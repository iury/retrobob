const std = @import("std");
const Region = @import("../core.zig").Region;

pub const RunOption = enum { frame, cpu_cycle, ppu_cycle };

pub fn Clock(comptime T: anytype, comptime region: Region) type {
    return struct {
        const Self = @This();

        handler: *T,
        region: Region = region,

        frame_cycles: u32 = if (region == .ntsc) 357_364 else 531_960,
        cpu_divider: u32 = if (region == .ntsc) 12 else 16,
        ppu_divider: u32 = if (region == .ntsc) 4 else 5,
        cpu_counter: u32 = 0,
        ppu_counter: u32 = 0,

        pub fn setRegion(self: *Self, new_region: Region) void {
            self.region = new_region;
            self.cpu_counter = 0;
            self.ppu_counter = 0;

            if (self.region == .ntsc) {
                self.frame_cycles = 357_364;
                self.cpu_divider = 12;
                self.ppu_divider = 4;
            } else {
                self.frame_cycles = 531_960;
                self.cpu_divider = 16;
                self.ppu_divider = 5;
            }
        }

        pub fn reset(self: *Self) void {
            self.cpu_counter = 0;
            self.ppu_counter = 0;
        }

        pub fn run(self: *Self, option: RunOption) void {
            switch (option) {
                .frame => {
                    for (0..self.frame_cycles) |_| {
                        self.cpu_counter += 1;
                        if (self.cpu_counter == self.cpu_divider) {
                            self.cpu_counter = 0;
                            self.handler.handleCPUCycle();
                        }
                        self.ppu_counter += 1;
                        if (self.ppu_counter == self.ppu_divider) {
                            self.ppu_counter = 0;
                            self.handler.handlePPUCycle();
                        }
                    }
                },

                .cpu_cycle => {
                    while (true) {
                        self.ppu_counter += 1;
                        if (self.ppu_counter == self.ppu_divider) {
                            self.ppu_counter = 0;
                            self.handler.handlePPUCycle();
                        }
                        self.cpu_counter += 1;
                        if (self.cpu_counter == self.cpu_divider) {
                            self.cpu_counter = 0;
                            self.handler.handleCPUCycle();
                            break;
                        }
                    }
                },

                .ppu_cycle => {
                    while (true) {
                        self.cpu_counter += 1;
                        if (self.cpu_counter == self.cpu_divider) {
                            self.cpu_counter = 0;
                            self.handler.handleCPUCycle();
                        }
                        self.ppu_counter += 1;
                        if (self.ppu_counter == self.ppu_divider) {
                            self.ppu_counter = 0;
                            self.handler.handlePPUCycle();
                            break;
                        }
                    }
                },
            }
        }

        pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
            try jw.beginObject();
            try jw.objectField("cpu_counter");
            try jw.write(self.cpu_counter);
            try jw.objectField("ppu_counter");
            try jw.write(self.ppu_counter);
            try jw.endObject();
        }

        pub fn jsonParse(self: *Self, value: std.json.Value) void {
            self.cpu_counter = @intCast(value.object.get("cpu_counter").?.integer);
            self.ppu_counter = @intCast(value.object.get("ppu_counter").?.integer);
        }
    };
}

test {
    _ = @import("clock.test.zig");
}
