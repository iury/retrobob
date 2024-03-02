const std = @import("std");
const Timer = @import("apu.zig").Timer;
const Proxy = @import("../../../proxy.zig").Proxy;
const c = @import("../../../c.zig");

pub const DMC = struct {
    pub const lookup_table_ntsc: []const u16 = &[_]u16{ 428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54 };
    pub const lookup_table_pal: []const u16 = &[_]u16{ 398, 354, 316, 298, 276, 236, 210, 198, 176, 148, 132, 118, 98, 78, 66, 50 };

    irq_requested: bool = false,
    timer: Timer(.dmc) = .{},
    sample_addr: u16 = 0,
    sample_length: u16 = 0,
    output_level: u8 = 0,
    irq_enabled: bool = false,
    loop_flag: bool = false,
    current_addr: u16 = 0,
    bytes_remaining: u16 = 0,
    read_buffer: u8 = 0,
    buffer_empty: bool = true,
    shift_register: u8 = 0,
    bits_remaining: u8 = 0,
    silence_flag: bool = true,
    needs_to_run: bool = false,
    needs_init: u8 = 0,
    lookup_table: []const u16 = lookup_table_ntsc,
    transfer_requested: bool = false,

    pub fn initSample(self: *DMC) void {
        self.current_addr = self.sample_addr;
        self.bytes_remaining = self.sample_length;
        self.needs_to_run = self.bytes_remaining > 0;
    }

    pub fn startDMCTransfer(self: *DMC) void {
        if (self.buffer_empty and self.bytes_remaining > 0) {
            self.transfer_requested = true;
        }
    }

    pub fn setDMCReadBuffer(self: *DMC, value: u8) void {
        if (self.bytes_remaining > 0) {
            self.read_buffer = value;
            self.buffer_empty = false;
            self.current_addr +%= 1;
            if (self.current_addr == 0) self.current_addr = 0x8000;
            self.bytes_remaining -= 1;
            if (self.bytes_remaining == 0) {
                self.needs_to_run = false;
                if (self.loop_flag) {
                    self.initSample();
                } else if (self.irq_enabled) {
                    self.irq_requested = true;
                }
            }
        }
    }

    pub fn setEnabled(self: *DMC, is_enabled: bool) void {
        if (!is_enabled) {
            self.bytes_remaining = 0;
            self.needs_to_run = false;
        } else if (self.bytes_remaining == 0) {
            self.initSample();
            self.needs_init = 2;
        }
    }

    pub fn getStatus(self: *DMC) bool {
        return self.bytes_remaining > 0;
    }

    pub fn needsToRun(self: *DMC) bool {
        if (self.needs_init > 0) {
            self.needs_init -= 1;
            if (self.needs_init == 0) {
                self.startDMCTransfer();
            }
        }
        return self.needs_to_run;
    }

    pub fn irqPending(self: *DMC, cycles_to_run: u32) bool {
        if (self.irq_enabled and self.bytes_remaining > 0) {
            const cycles_to_empty_buffer: u32 = (self.bits_remaining + (self.bytes_remaining - 1) * 8) * self.timer.period;
            if (cycles_to_run >= cycles_to_empty_buffer) return true;
        }
        return false;
    }

    pub fn endFrame(self: *DMC) void {
        self.timer.endFrame();
    }

    pub fn run(self: *DMC, cycle: u32) void {
        while (self.timer.run(cycle)) {
            if (!self.silence_flag) {
                if ((self.shift_register & 0x01) > 0) {
                    if (self.output_level <= 125) {
                        self.output_level += 2;
                    }
                } else {
                    if (self.output_level >= 2) {
                        self.output_level -= 2;
                    }
                }
                self.shift_register >>= 1;
            }

            self.bits_remaining -= 1;
            if (self.bits_remaining == 0) {
                self.bits_remaining = 8;
                if (self.buffer_empty) {
                    self.silence_flag = true;
                } else {
                    self.silence_flag = false;
                    self.shift_register = self.read_buffer;
                    self.buffer_empty = true;
                    self.startDMCTransfer();
                }
            }

            self.timer.addOutput(@intCast(self.output_level));
        }
    }

    pub fn reset(self: *DMC) void {
        self.irq_requested = false;
        self.timer.reset();
        self.sample_addr = 0xC000;
        self.sample_length = 1;
        self.output_level = 0;
        self.irq_enabled = false;
        self.loop_flag = false;
        self.current_addr = 0;
        self.bytes_remaining = 0;
        self.read_buffer = 0;
        self.buffer_empty = true;
        self.shift_register = 0;
        self.bits_remaining = 8;
        self.silence_flag = true;
        self.needs_to_run = false;
        self.needs_init = 0;
        self.transfer_requested = false;
        self.timer.period = self.lookup_table[0] - 1;
        self.timer.timer = self.timer.period;
    }

    pub fn get(ctx: *anyopaque) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return self.read_buffer;
    }

    pub fn set(ctx: *anyopaque, data: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.setDMCReadBuffer(data);
    }

    pub fn proxy(self: *@This()) Proxy(u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .get = get,
                .set = set,
            },
        };
    }

    pub fn serialize(self: *const DMC, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);
        c.mpack_write_cstr(pack, "timer");
        self.timer.serialize(pack);
        c.mpack_write_cstr(pack, "irq_requested");
        c.mpack_write_bool(pack, self.irq_requested);
        c.mpack_write_cstr(pack, "sample_addr");
        c.mpack_write_u16(pack, self.sample_addr);
        c.mpack_write_cstr(pack, "sample_length");
        c.mpack_write_u16(pack, self.sample_length);
        c.mpack_write_cstr(pack, "output_level");
        c.mpack_write_u8(pack, self.output_level);
        c.mpack_write_cstr(pack, "irq_enabled");
        c.mpack_write_bool(pack, self.irq_enabled);
        c.mpack_write_cstr(pack, "loop_flag");
        c.mpack_write_bool(pack, self.loop_flag);
        c.mpack_write_cstr(pack, "current_addr");
        c.mpack_write_u16(pack, self.current_addr);
        c.mpack_write_cstr(pack, "bytes_remaining");
        c.mpack_write_u16(pack, self.bytes_remaining);
        c.mpack_write_cstr(pack, "read_buffer");
        c.mpack_write_u8(pack, self.read_buffer);
        c.mpack_write_cstr(pack, "buffer_empty");
        c.mpack_write_bool(pack, self.buffer_empty);
        c.mpack_write_cstr(pack, "shift_register");
        c.mpack_write_u8(pack, self.shift_register);
        c.mpack_write_cstr(pack, "bits_remaining");
        c.mpack_write_u8(pack, self.bits_remaining);
        c.mpack_write_cstr(pack, "silence_flag");
        c.mpack_write_bool(pack, self.silence_flag);
        c.mpack_write_cstr(pack, "needs_to_run");
        c.mpack_write_bool(pack, self.needs_to_run);
        c.mpack_write_cstr(pack, "needs_init");
        c.mpack_write_u8(pack, self.needs_init);
        c.mpack_write_cstr(pack, "transfer_requested");
        c.mpack_write_bool(pack, self.transfer_requested);
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *DMC, pack: c.mpack_node_t) void {
        self.timer.deserialize(c.mpack_node_map_cstr(pack, "timer"));
        self.irq_requested = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "irq_requested"));
        self.sample_addr = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "sample_addr"));
        self.sample_length = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "sample_length"));
        self.output_level = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "output_level"));
        self.irq_enabled = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "irq_enabled"));
        self.loop_flag = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "loop_flag"));
        self.current_addr = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "current_addr"));
        self.bytes_remaining = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "bytes_remaining"));
        self.read_buffer = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "read_buffer"));
        self.buffer_empty = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "buffer_empty"));
        self.shift_register = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "shift_register"));
        self.bits_remaining = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "bits_remaining"));
        self.silence_flag = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "silence_flag"));
        self.needs_to_run = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "needs_to_run"));
        self.needs_init = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "needs_init"));
        self.transfer_requested = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "transfer_requested"));
    }
};
