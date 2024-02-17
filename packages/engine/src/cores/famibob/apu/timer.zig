const APU = @import("apu.zig");
const AudioChannel = APU.AudioChannel;
const Mixer = APU.Mixer;

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

        pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
            try jw.beginObject();
            try jw.objectField("previous_cycle");
            try jw.write(self.previous_cycle);
            try jw.objectField("timer");
            try jw.write(self.timer);
            try jw.objectField("period");
            try jw.write(self.period);
            try jw.objectField("last_output");
            try jw.write(self.last_output);
            try jw.endObject();
        }
    };
}
