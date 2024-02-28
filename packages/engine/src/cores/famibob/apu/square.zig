const std = @import("std");
const APU = @import("apu.zig");
const AudioChannel = APU.AudioChannel;
const Envelope = APU.Envelope;
const Timer = APU.Timer;

pub const SquareChannel = enum { one, two };

pub fn Square(comptime channel: SquareChannel) type {
    return struct {
        const Self = @This();

        const duty_sequences: []const [8]i8 = &[_][8]i8{
            .{ 0, 0, 0, 0, 0, 0, 0, 1 },
            .{ 0, 0, 0, 0, 0, 0, 1, 1 },
            .{ 0, 0, 0, 0, 1, 1, 1, 1 },
            .{ 1, 1, 1, 1, 1, 1, 0, 0 },
        };

        channel: SquareChannel = channel,
        envelope: Envelope = .{},
        timer: Timer(if (channel == .one) .square1 else .square2) = .{},
        is_mmc5_square: bool = false,
        duty: u8 = 0,
        duty_pos: u8 = 0,
        sweep_enabled: bool = false,
        sweep_period: u8 = 0,
        sweep_negate: bool = false,
        sweep_shift: u4 = 0,
        reload_sweep: bool = false,
        sweep_divider: u8 = 0,
        sweep_target_period: u32 = 0,
        real_period: u16 = 0,

        pub fn initSweep(self: *Self, value: u8) void {
            self.sweep_enabled = (value & 0x80) == 0x80;
            self.sweep_negate = (value & 0x08) == 0x08;
            self.sweep_period = ((value & 0x70) >> 4) + 1;
            self.sweep_shift = @intCast(value & 0x07);
            self.updateTargetPeriod();
            self.reload_sweep = true;
        }

        pub fn updateTargetPeriod(self: *Self) void {
            const shift_result: u16 = (self.real_period >> self.sweep_shift);
            if (self.sweep_negate) {
                self.sweep_target_period = self.real_period - shift_result;
                if (self.channel == .one) {
                    self.sweep_target_period -%= 1;
                }
            } else {
                self.sweep_target_period = self.real_period + shift_result;
            }
        }

        pub fn updateOutput(self: *Self) void {
            if (self.isMuted()) {
                self.timer.addOutput(0);
            } else {
                self.timer.addOutput(duty_sequences[self.duty][self.duty_pos] * self.envelope.getVolume());
            }
        }

        pub fn setPeriod(self: *Self, new_period: u16) void {
            self.real_period = new_period;
            self.timer.period = self.real_period * 2 + 1;
            self.updateTargetPeriod();
        }

        pub fn isMuted(self: *Self) bool {
            return self.real_period < 8 or (!self.sweep_negate and self.sweep_target_period > 0x7FF);
        }

        pub fn setEnabled(self: *Self, is_enabled: bool) void {
            self.envelope.length_counter.setEnabled(is_enabled);
        }

        pub fn getStatus(self: *Self) bool {
            return self.envelope.length_counter.getStatus();
        }

        pub fn tickEnvelope(self: *Self) void {
            self.envelope.tickEnvelope();
        }

        pub fn tickLengthCounter(self: *Self) void {
            self.envelope.length_counter.tickLengthCounter();
        }

        pub fn tickSweep(self: *Self) void {
            self.sweep_divider -%= 1;
            if (self.sweep_divider == 0) {
                if (self.sweep_shift > 0 and self.sweep_enabled and self.real_period >= 8 and self.sweep_target_period <= 0x7FF) {
                    self.setPeriod(@intCast(self.sweep_target_period));
                }
                self.sweep_divider = self.sweep_period;
            }

            if (self.reload_sweep) {
                self.sweep_divider = self.sweep_period;
                self.reload_sweep = false;
            }
        }

        pub fn endFrame(self: *Self) void {
            self.timer.endFrame();
        }

        pub fn reloadLengthCounter(self: *Self) void {
            self.envelope.length_counter.reloadCounter();
        }

        pub fn run(self: *Self, cycle: u32) void {
            while (self.timer.run(cycle)) {
                self.duty_pos = (self.duty_pos -% 1) & 0x07;
                self.updateOutput();
            }
        }

        pub fn reset(self: *Self) void {
            self.envelope.reset();
            self.timer.reset();
            self.duty = 0;
            self.duty_pos = 0;
            self.real_period = 0;
            self.sweep_enabled = false;
            self.sweep_period = 0;
            self.sweep_negate = false;
            self.sweep_shift = 0;
            self.reload_sweep = false;
            self.sweep_divider = 0;
            self.sweep_target_period = 0;
            self.updateTargetPeriod();
        }

        pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
            try jw.beginObject();
            try jw.objectField("envelope");
            try jw.write(self.envelope);
            try jw.objectField("timer");
            try jw.write(self.timer);
            try jw.objectField("is_mmc5_square");
            try jw.write(self.is_mmc5_square);
            try jw.objectField("duty");
            try jw.write(self.duty);
            try jw.objectField("duty_pos");
            try jw.write(self.duty_pos);
            try jw.objectField("sweep_enabled");
            try jw.write(self.sweep_enabled);
            try jw.objectField("sweep_period");
            try jw.write(self.sweep_period);
            try jw.objectField("sweep_negate");
            try jw.write(self.sweep_negate);
            try jw.objectField("sweep_shift");
            try jw.write(self.sweep_shift);
            try jw.objectField("reload_sweep");
            try jw.write(self.reload_sweep);
            try jw.objectField("sweep_divider");
            try jw.write(self.sweep_divider);
            try jw.objectField("sweep_target_period");
            try jw.write(self.sweep_target_period);
            try jw.objectField("real_period");
            try jw.write(self.real_period);
            try jw.endObject();
        }

        pub fn jsonParse(self: *@This(), value: std.json.Value) void {
            self.envelope.jsonParse(value.object.get("envelope").?);
            self.timer.jsonParse(value.object.get("timer").?);
            self.is_mmc5_square = value.object.get("is_mmc5_square").?.bool;
            self.duty = @intCast(value.object.get("duty").?.integer);
            self.duty_pos = @intCast(value.object.get("duty_pos").?.integer);
            self.sweep_enabled = value.object.get("sweep_enabled").?.bool;
            self.sweep_period = @intCast(value.object.get("sweep_period").?.integer);
            self.sweep_negate = value.object.get("sweep_negate").?.bool;
            self.sweep_shift = @intCast(value.object.get("sweep_shift").?.integer);
            self.reload_sweep = value.object.get("reload_sweep").?.bool;
            self.sweep_divider = @intCast(value.object.get("sweep_divider").?.integer);
            self.sweep_target_period = @intCast(value.object.get("sweep_target_period").?.integer);
            self.real_period = @intCast(value.object.get("real_period").?.integer);
        }
    };
}
