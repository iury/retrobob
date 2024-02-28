const std = @import("std");
const LengthCounter = @import("apu.zig").LengthCounter;

pub const Envelope = struct {
    length_counter: LengthCounter = .{},
    constant_volume: bool = false,
    volume: i8 = 0,
    start: bool = false,
    divider: i8 = 0,
    counter: i8 = 0,

    pub fn initEnvelope(self: *Envelope, value: u8) void {
        self.length_counter.initLengthCounter((value & 0x20) == 0x20);
        self.constant_volume = (value & 0x10) == 0x10;
        self.volume = @intCast(value & 0x0F);
    }

    pub fn resetEnvelope(self: *Envelope) void {
        self.start = true;
    }

    pub fn getVolume(self: *Envelope) i8 {
        if (self.length_counter.getStatus()) {
            return if (self.constant_volume) self.volume else self.counter;
        } else {
            return 0;
        }
    }

    pub fn tickEnvelope(self: *Envelope) void {
        if (!self.start) {
            self.divider -= 1;
            if (self.divider < 0) {
                self.divider = self.volume;
                if (self.counter > 0) {
                    self.counter -= 1;
                } else if (self.length_counter.halt) {
                    self.counter = 15;
                }
            }
        } else {
            self.start = false;
            self.counter = 15;
            self.divider = self.volume;
        }
    }

    pub fn reset(self: *Envelope) void {
        self.length_counter.reset();
        self.constant_volume = false;
        self.volume = 0;
        self.start = false;
        self.divider = 0;
        self.counter = 0;
    }

    pub fn jsonStringify(self: *const Envelope, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("length_counter");
        try jw.write(self.length_counter);
        try jw.objectField("constant_volume");
        try jw.write(self.constant_volume);
        try jw.objectField("volume");
        try jw.write(self.volume);
        try jw.objectField("start");
        try jw.write(self.start);
        try jw.objectField("divider");
        try jw.write(self.divider);
        try jw.objectField("counter");
        try jw.write(self.counter);
        try jw.endObject();
    }

    pub fn jsonParse(self: *Envelope, value: std.json.Value) void {
        self.length_counter.jsonParse(value.object.get("length_counter").?);
        self.constant_volume = value.object.get("constant_volume").?.bool;
        self.volume = @intCast(value.object.get("volume").?.integer);
        self.start = value.object.get("start").?.bool;
        self.divider = @intCast(value.object.get("divider").?.integer);
        self.counter = @intCast(value.object.get("counter").?.integer);
    }
};
