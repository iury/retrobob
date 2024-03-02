const std = @import("std");
const c = @import("../../../c.zig");

pub const LengthCounter = struct {
    const lookup_table: []const u8 = &[_]u8{ 10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14, 12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30 };

    new_halt_value: bool = false,
    enabled: bool = false,
    halt: bool = false,
    counter: u8 = 0,
    reload_value: u8 = 0,
    previous_value: u8 = 0,

    pub fn initLengthCounter(self: *LengthCounter, halt_flag: bool) void {
        self.new_halt_value = halt_flag;
    }

    pub fn loadLengthCounter(self: *LengthCounter, value: u8) void {
        if (self.enabled) {
            self.reload_value = lookup_table[value];
            self.previous_value = self.counter;
        }
    }

    pub fn reloadCounter(self: *LengthCounter) void {
        if (self.reload_value > 0) {
            if (self.counter == self.previous_value) {
                self.counter = self.reload_value;
            }
            self.reload_value = 0;
        }
        self.halt = self.new_halt_value;
    }

    pub fn tickLengthCounter(self: *LengthCounter) void {
        if (self.counter > 0 and !self.halt) {
            self.counter -= 1;
        }
    }

    pub fn getStatus(self: *LengthCounter) bool {
        return self.counter > 0;
    }

    pub fn setEnabled(self: *LengthCounter, is_enabled: bool) void {
        if (!is_enabled) self.counter = 0;
        self.enabled = is_enabled;
    }

    pub fn reset(self: *LengthCounter) void {
        self.enabled = false;
        self.halt = false;
        self.counter = 0;
        self.new_halt_value = false;
        self.reload_value = 0;
        self.previous_value = 0;
    }

    pub fn serialize(self: *const LengthCounter, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);
        c.mpack_write_cstr(pack, "new_halt_value");
        c.mpack_write_bool(pack, self.new_halt_value);
        c.mpack_write_cstr(pack, "enabled");
        c.mpack_write_bool(pack, self.enabled);
        c.mpack_write_cstr(pack, "halt");
        c.mpack_write_bool(pack, self.halt);
        c.mpack_write_cstr(pack, "counter");
        c.mpack_write_u8(pack, self.counter);
        c.mpack_write_cstr(pack, "reload_value");
        c.mpack_write_u8(pack, self.reload_value);
        c.mpack_write_cstr(pack, "previous_value");
        c.mpack_write_u8(pack, self.previous_value);
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *LengthCounter, pack: c.mpack_node_t) void {
        self.new_halt_value = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "new_halt_value"));
        self.enabled = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "enabled"));
        self.halt = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "halt"));
        self.counter = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "counter"));
        self.reload_value = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "reload_value"));
        self.previous_value = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "previous_value"));
    }
};
