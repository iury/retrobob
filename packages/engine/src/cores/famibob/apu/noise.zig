const std = @import("std");
const APU = @import("apu.zig");
const Envelope = APU.Envelope;
const Timer = APU.Timer;

pub const Noise = struct {
    pub const lookup_table_ntsc: []const u16 = &[_]u16{ 4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068 };
    pub const lookup_table_pal: []const u16 = &[_]u16{ 4, 8, 14, 30, 60, 88, 118, 148, 188, 236, 354, 472, 708, 944, 1890, 3778 };

    envelope: Envelope = .{},
    timer: Timer(.noise) = .{},
    shift_register: u16 = 1,
    mode_flag: bool = false,
    lookup_table: []const u16 = lookup_table_ntsc,

    pub fn isMuted(self: *Noise) bool {
        return (self.shift_register & 0x01) == 0x01;
    }

    pub fn setEnabled(self: *Noise, is_enabled: bool) void {
        self.envelope.length_counter.setEnabled(is_enabled);
    }

    pub fn getStatus(self: *Noise) bool {
        return self.envelope.length_counter.getStatus();
    }

    pub fn tickEnvelope(self: *Noise) void {
        self.envelope.tickEnvelope();
    }

    pub fn tickLengthCounter(self: *Noise) void {
        self.envelope.length_counter.tickLengthCounter();
    }

    pub fn endFrame(self: *Noise) void {
        self.timer.endFrame();
    }

    pub fn reloadLengthCounter(self: *Noise) void {
        self.envelope.length_counter.reloadCounter();
    }

    pub fn run(self: *Noise, cycle: u32) void {
        while (self.timer.run(cycle)) {
            const feedback: u16 = (self.shift_register & 0x01) ^ ((self.shift_register >> @as(u3, if (self.mode_flag) 6 else 1)) & 0x01);
            self.shift_register >>= 1;
            self.shift_register |= (feedback << 14);
            if (self.isMuted()) {
                self.timer.addOutput(0);
            } else {
                self.timer.addOutput(self.envelope.getVolume());
            }
        }
    }

    pub fn reset(self: *Noise) void {
        self.envelope.reset();
        self.timer.reset();
        self.timer.period = self.lookup_table[0] - 1;
        self.shift_register = 1;
        self.mode_flag = false;
    }

    pub fn jsonStringify(self: *const Noise, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("envelope");
        try jw.write(self.envelope);
        try jw.objectField("timer");
        try jw.write(self.timer);
        try jw.objectField("shift_register");
        try jw.write(self.shift_register);
        try jw.objectField("mode_flag");
        try jw.write(self.mode_flag);
        try jw.endObject();
    }

    pub fn jsonParse(self: *Noise, value: std.json.Value) void {
        self.envelope.jsonParse(value.object.get("envelope").?);
        self.timer.jsonParse(value.object.get("timer").?);
        self.shift_register = @intCast(value.object.get("shift_register").?.integer);
        self.mode_flag = value.object.get("mode_flag").?.bool;
    }
};
