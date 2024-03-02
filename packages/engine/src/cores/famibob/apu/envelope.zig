const std = @import("std");
const LengthCounter = @import("apu.zig").LengthCounter;
const c = @import("../../../c.zig");

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

    pub fn serialize(self: *const Envelope, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);
        c.mpack_write_cstr(pack, "length_counter");
        self.length_counter.serialize(pack);
        c.mpack_write_cstr(pack, "constant_volume");
        c.mpack_write_bool(pack, self.constant_volume);
        c.mpack_write_cstr(pack, "volume");
        c.mpack_write_i8(pack, self.volume);
        c.mpack_write_cstr(pack, "start");
        c.mpack_write_bool(pack, self.start);
        c.mpack_write_cstr(pack, "divider");
        c.mpack_write_i8(pack, self.divider);
        c.mpack_write_cstr(pack, "counter");
        c.mpack_write_i8(pack, self.counter);
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *Envelope, pack: c.mpack_node_t) void {
        self.length_counter.deserialize(c.mpack_node_map_cstr(pack, "length_counter"));
        self.constant_volume = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "constant_volume"));
        self.volume = c.mpack_node_i8(c.mpack_node_map_cstr(pack, "volume"));
        self.start = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "start"));
        self.divider = c.mpack_node_i8(c.mpack_node_map_cstr(pack, "divider"));
        self.counter = c.mpack_node_i8(c.mpack_node_map_cstr(pack, "counter"));
    }
};
