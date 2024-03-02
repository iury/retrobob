const std = @import("std");
const APU = @import("apu.zig");
const LengthCounter = APU.LengthCounter;
const Timer = APU.Timer;
const c = @import("../../../c.zig");

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

    pub fn serialize(self: *const Triangle, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);
        c.mpack_write_cstr(pack, "length_counter");
        self.length_counter.serialize(pack);
        c.mpack_write_cstr(pack, "timer");
        self.timer.serialize(pack);
        c.mpack_write_cstr(pack, "linear_counter");
        c.mpack_write_u8(pack, self.linear_counter);
        c.mpack_write_cstr(pack, "linear_counter_reload");
        c.mpack_write_u8(pack, self.linear_counter_reload);
        c.mpack_write_cstr(pack, "linear_reload_flag");
        c.mpack_write_bool(pack, self.linear_reload_flag);
        c.mpack_write_cstr(pack, "linear_control_flag");
        c.mpack_write_bool(pack, self.linear_control_flag);
        c.mpack_write_cstr(pack, "sequence_position");
        c.mpack_write_u8(pack, self.sequence_position);
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *Triangle, pack: c.mpack_node_t) void {
        self.length_counter.deserialize(c.mpack_node_map_cstr(pack, "length_counter"));
        self.timer.deserialize(c.mpack_node_map_cstr(pack, "timer"));
        self.linear_counter = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "linear_counter"));
        self.linear_counter_reload = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "linear_counter_reload"));
        self.linear_reload_flag = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "linear_reload_flag"));
        self.linear_control_flag = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "linear_control_flag"));
        self.sequence_position = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "sequence_position"));
    }
};
