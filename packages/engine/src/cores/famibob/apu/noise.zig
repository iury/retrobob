const std = @import("std");
const APU = @import("apu.zig");
const Envelope = APU.Envelope;
const Timer = APU.Timer;
const c = @import("../../../c.zig");

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

    pub fn serialize(self: *const Noise, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);
        c.mpack_write_cstr(pack, "envelope");
        self.envelope.serialize(pack);
        c.mpack_write_cstr(pack, "timer");
        self.timer.serialize(pack);
        c.mpack_write_cstr(pack, "shift_register");
        c.mpack_write_u16(pack, self.shift_register);
        c.mpack_write_cstr(pack, "mode_flag");
        c.mpack_write_bool(pack, self.mode_flag);
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *Noise, pack: c.mpack_node_t) void {
        self.envelope.deserialize(c.mpack_node_map_cstr(pack, "envelope"));
        self.timer.deserialize(c.mpack_node_map_cstr(pack, "timer"));
        self.shift_register = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "shift_register"));
        self.mode_flag = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "mode_flag"));
    }
};
