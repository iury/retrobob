const std = @import("std");
const Region = @import("../core.zig").Region;
const c = @import("../../c.zig");

pub const RunOption = enum { frame, cycle };

pub fn Clock(comptime T: anytype) type {
    return struct {
        const Self = @This();

        handler: *T,
        region: Region = .ntsc,
        frame_cycles: f32 = 0,
        cycle_counter: f32 = 0,
        apu_divider: f32 = 0,
        apu_counter: f32 = 0,
        dma_offset_counter: u3 = 0,

        pub fn setRegion(self: *Self, new_region: Region) void {
            self.region = new_region;
            if (self.region == .ntsc) {
                const master_clock: f32 = 21_477_270.0;
                self.frame_cycles = master_clock / 60.0;
                self.apu_divider = master_clock / 1_024_000.0;
            } else {
                const master_clock: f32 = 17_734_475.0;
                self.frame_cycles = master_clock / 50.0;
                self.apu_divider = master_clock / 1_024_000.0;
            }
        }

        pub fn reset(self: *Self) void {
            self.cycle_counter = 0;
            self.apu_counter = 0;
            self.dma_offset_counter = 0;
        }

        fn runOnce(self: *Self) void {
            self.cycle_counter += 1;
            self.dma_offset_counter +%= 1;
            self.handler.handleCPUCycle();
            self.handler.handlePPUCycle();

            self.apu_counter += 1;
            if (self.apu_counter >= self.apu_divider) {
                self.apu_counter -= self.apu_divider;
                self.handler.handleAPUCycle();
            }
        }

        pub fn run(self: *Self, option: RunOption) void {
            if (option == .cycle) {
                self.runOnce();
            } else {
                while (self.cycle_counter < self.frame_cycles) {
                    self.runOnce();
                }
                self.cycle_counter -= self.frame_cycles;
            }
        }

        pub fn serialize(self: *const Self, pack: *c.mpack_writer_t) void {
            c.mpack_build_map(pack);
            c.mpack_write_cstr(pack, "cycle_counter");
            c.mpack_write_float(pack, self.cycle_counter);
            c.mpack_write_cstr(pack, "apu_counter");
            c.mpack_write_float(pack, self.apu_counter);
            c.mpack_write_cstr(pack, "dma_offset_counter");
            c.mpack_write_u8(pack, self.dma_offset_counter);
            c.mpack_complete_map(pack);
        }

        pub fn deserialize(self: *Self, pack: c.mpack_node_t) void {
            self.cycle_counter = c.mpack_node_float(c.mpack_node_map_cstr(pack, "cycle_counter"));
            self.apu_counter = c.mpack_node_float(c.mpack_node_map_cstr(pack, "apu_counter"));
            self.dma_offset_counter = @truncate(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "dma_offset_counter")));
        }
    };
}
