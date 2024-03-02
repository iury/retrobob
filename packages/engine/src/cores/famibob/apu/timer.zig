const std = @import("std");
const APU = @import("apu.zig");
const AudioChannel = APU.AudioChannel;
const Mixer = APU.Mixer;
const c = @import("../../../c.zig");

pub fn Timer(comptime channel: AudioChannel) type {
    return struct {
        const Self = @This();

        mixer: ?*Mixer = null,

        previous_cycle: u32 = 0,
        timer: u16 = 0,
        period: u16 = 0,
        last_output: i8 = 0,
        channel: AudioChannel = channel,

        pub fn addOutput(self: *Self, output: i8) void {
            if (output != self.last_output) {
                if (self.mixer) |mixer| mixer.addDelta(self.channel, self.previous_cycle, output - self.last_output);
                self.last_output = output;
            }
        }

        pub fn run(self: *Self, target_cycle: u32) bool {
            const cycles_to_run: i32 = @intCast(target_cycle - self.previous_cycle);

            if (cycles_to_run > self.timer) {
                self.previous_cycle += self.timer + 1;
                self.timer = self.period;
                return true;
            }

            self.timer -= @intCast(cycles_to_run);
            self.previous_cycle = target_cycle;
            return false;
        }

        pub fn endFrame(self: *Self) void {
            self.previous_cycle = 0;
        }

        pub fn reset(self: *Self) void {
            self.timer = 0;
            self.period = 0;
            self.previous_cycle = 0;
            self.last_output = 0;
        }

        pub fn serialize(self: *const @This(), pack: *c.mpack_writer_t) void {
            c.mpack_build_map(pack);
            c.mpack_write_cstr(pack, "previous_cycle");
            c.mpack_write_u32(pack, self.previous_cycle);
            c.mpack_write_cstr(pack, "timer");
            c.mpack_write_u16(pack, self.timer);
            c.mpack_write_cstr(pack, "period");
            c.mpack_write_u16(pack, self.period);
            c.mpack_write_cstr(pack, "last_output");
            c.mpack_write_i8(pack, self.last_output);
            c.mpack_complete_map(pack);
        }

        pub fn deserialize(self: *@This(), pack: c.mpack_node_t) void {
            self.previous_cycle = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "previous_cycle"));
            self.timer = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "timer"));
            self.period = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "period"));
            self.last_output = c.mpack_node_i8(c.mpack_node_map_cstr(pack, "last_output"));
        }
    };
}
