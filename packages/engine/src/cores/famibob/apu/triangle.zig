const std = @import("std");
const APU = @import("apu.zig");
const LengthCounter = APU.LengthCounter;
const Timer = APU.Timer;

pub const Triangle = struct {
    const sequence: []const i8 = &[_]i8{
        15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5,  4,  3,  2,  1,  0,
        0,  1,  2,  3,  4,  5,  6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    };

    length_counter: LengthCounter = .{},
    timer: Timer(.triangle) = .{},
    linear_counter: u8 = 0,
    linear_counter_reload: u8 = 0,
    linear_reload_flag: bool = false,
    linear_control_flag: bool = false,
    sequence_position: u8 = 0,

    pub fn setEnabled(self: *Triangle, is_enabled: bool) void {
        self.length_counter.setEnabled(is_enabled);
    }

    pub fn getStatus(self: *Triangle) bool {
        return self.length_counter.getStatus();
    }

    pub fn tickLinearCounter(self: *Triangle) void {
        if (self.linear_reload_flag) {
            self.linear_counter = self.linear_counter_reload;
        } else if (self.linear_counter > 0) {
            self.linear_counter -= 1;
        }
        if (!self.linear_control_flag) {
            self.linear_reload_flag = false;
        }
    }

    pub fn tickLengthCounter(self: *Triangle) void {
        self.length_counter.tickLengthCounter();
    }

    pub fn endFrame(self: *Triangle) void {
        self.timer.endFrame();
    }

    pub fn reloadLengthCounter(self: *Triangle) void {
        self.length_counter.reloadCounter();
    }

    pub fn run(self: *Triangle, cycle: u32) void {
        while (self.timer.run(cycle)) {
            if (self.length_counter.getStatus() and self.linear_counter > 0) {
                self.sequence_position = (self.sequence_position + 1) & 0x1f;
                if (self.timer.period >= 2) {
                    self.timer.addOutput(sequence[self.sequence_position]);
                }
            }
        }
    }

    pub fn reset(self: *Triangle) void {
        self.timer.reset();
        self.length_counter.reset();
        self.linear_counter = 0;
        self.linear_counter_reload = 0;
        self.linear_reload_flag = false;
        self.linear_control_flag = false;
        self.sequence_position = 0;
    }

    pub fn jsonStringify(self: *const Triangle, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("length_counter");
        try jw.write(self.length_counter);
        try jw.objectField("timer");
        try jw.write(self.timer);
        try jw.objectField("linear_counter");
        try jw.write(self.linear_counter);
        try jw.objectField("linear_counter_reload");
        try jw.write(self.linear_counter_reload);
        try jw.objectField("linear_reload_flag");
        try jw.write(self.linear_reload_flag);
        try jw.objectField("linear_control_flag");
        try jw.write(self.linear_control_flag);
        try jw.objectField("sequence_position");
        try jw.write(self.sequence_position);
        try jw.endObject();
    }

    pub fn jsonParse(self: *Triangle, value: std.json.Value) void {
        self.length_counter.jsonParse(value.object.get("length_counter").?);
        self.timer.jsonParse(value.object.get("timer").?);
        self.linear_counter = @intCast(value.object.get("linear_counter").?.integer);
        self.linear_counter_reload = @intCast(value.object.get("linear_counter_reload").?.integer);
        self.linear_reload_flag = value.object.get("linear_reload_flag").?.bool;
        self.linear_control_flag = value.object.get("linear_control_flag").?.bool;
        self.sequence_position = @intCast(value.object.get("sequence_position").?.integer);
    }
};
