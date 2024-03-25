const std = @import("std");
const DSPState = @import("dsp.zig").DSPState;
const VoiceRegs = @import("dsp.zig").VoiceRegs;
const clamp16 = @import("dsp.zig").clamp16;
const c = @import("../../../c.zig");

const COUNTERS = @import("dsp.zig").COUNTERS;

pub const Voice = struct {
    const Self = @This();
    regs: []u8,

    mode: enum(u2) { release = 0, attack, decay, sustain },
    buffer: [12]i16 = [_]i16{0} ** 12,
    buffer_pos: u8,
    env_volume: i32 = 0,
    prev_calculated_env: i32 = 0,
    interpolation_pos: i32 = 0,
    brr_address: u16 = 0,
    brr_offset: u16 = 1,
    voice_index: u8 = 0,
    voice_bit: u8 = 0,
    key_on_delay: u8 = 0,
    env_out: u8 = 0,
    ram: []u8,
    state: *DSPState = undefined,

    pub fn decodeBrrSample(self: *Self) void {
        const next_brr_data: u8 = self.ram[self.brr_address +% self.brr_offset +% 1];
        const samples: [4]i16 = .{
            @as(i16, @bitCast((@as(u16, self.state.brr_data) & 0xf0) << 8)) >> 12,
            @as(i16, @bitCast((@as(u16, self.state.brr_data) & 0x0f) << 12)) >> 12,
            @as(i16, @bitCast((@as(u16, next_brr_data) & 0xf0) << 8)) >> 12,
            @as(i16, @bitCast((@as(u16, next_brr_data) & 0x0f) << 12)) >> 12,
        };

        const shift: u4 = @intCast(self.state.brr_header >> 4);
        const filter = self.state.brr_header & 0xc;

        var prev1: i32 = self.buffer[if (self.buffer_pos > 0) self.buffer_pos -% 1 else 11] >> 1;
        var prev2: i32 = self.buffer[if (self.buffer_pos > 1) self.buffer_pos -% 2 else 10] >> 1;

        for (0..4) |i| {
            var s: i32 = (@as(i32, samples[i]) << shift) >> 1;
            if (shift >= 0x0d) s = @as(i32, if (s < 0) -0x800 else 0);

            switch (filter) {
                0x04 => s +%= prev1 +% (-prev1 >> 4),
                0x08 => s +%= (prev1 << 1) +% ((-((prev1 << 1) +% prev1)) >> 5) -% prev2 +% (prev2 >> 4),
                0x0C => s +%= (prev1 << 1) +% ((-(prev1 +% (prev1 << 2) +% (prev1 << 3))) >> 6) -% prev2 +% (((prev2 << 1) +% prev2) >> 4),
                else => {},
            }

            self.buffer[self.buffer_pos +% i] = clamp16(s) *% 2;
            prev2 = prev1;
            prev1 = self.buffer[self.buffer_pos +% i] >> 1;
        }

        if (self.buffer_pos <= 4) {
            self.buffer_pos +%= 4;
        } else {
            self.buffer_pos = 0;
        }
    }

    pub fn processEnvelope(self: *Self) void {
        var env: i32 = self.env_volume;
        if (self.mode == .release) {
            env -%= 8;
            self.env_volume = if (env < 0) 0 else env;
        } else {
            var rate: usize = 0;
            var sustain: u8 = 0;

            if ((self.state.adsr1 & 0x80) > 0) {
                const adsr2 = self.regs[@intFromEnum(VoiceRegs.adsr2)];
                sustain = adsr2;
                switch (self.mode) {
                    .attack => {
                        if ((self.state.adsr1 & 0xf) == 0xf) {
                            rate = 31;
                            env += 1024;
                        } else {
                            rate = ((self.state.adsr1 & 0xf) << 1) | 0x01;
                            env += 32;
                        }
                    },

                    .decay => {
                        env -= ((env -% 1) >> 8) +% 1;
                        rate = ((self.state.adsr1 >> 3) & 0xe) | 0x10;
                    },

                    .sustain => {
                        env -= ((env -% 1) >> 8) +% 1;
                        rate = adsr2 & 0x1f;
                    },

                    .release => {},
                }
            } else {
                const gain = self.regs[@intFromEnum(VoiceRegs.gain)];
                sustain = gain;
                if ((gain & 0x80) > 0) {
                    rate = gain & 0x1f;
                    switch (gain & 0x60) {
                        0x00 => env -= 32,
                        0x20 => env -= ((env -% 1) >> 8) +% 1,
                        0x40 => env += 32,
                        0x60 => env += if (@as(u16, @truncate(@as(u32, @bitCast(self.prev_calculated_env)))) < 0x600) 32 else 8,
                        else => {},
                    }
                } else {
                    env = @as(u16, gain) << 4;
                    rate = 31;
                }
            }

            if (self.mode == .decay and (env >> 8) == (sustain >> 5)) {
                self.mode = .sustain;
            }

            self.prev_calculated_env = env;

            if (env < 0 or env > 0x7ff) {
                env = if (env < 0) 0 else 0x7ff;
                if (self.mode == .attack) {
                    self.mode = .decay;
                }
            }

            if (((self.state.counter +% COUNTERS.offsets[rate]) % COUNTERS.rates[rate]) == 0) {
                self.env_volume = env;
            }
        }
    }

    pub fn updateOutput(self: *Self, is_right: bool) void {
        var vol: i32 = 0;
        if (is_right) {
            vol = @as(i8, @bitCast(self.regs[@intFromEnum(VoiceRegs.vol_right)]));
        } else {
            vol = @as(i8, @bitCast(self.regs[@intFromEnum(VoiceRegs.vol_left)]));
        }

        const voice_out = (self.state.voice_output *% vol) >> 7;
        self.state.out_samples[if (is_right) 1 else 0] = clamp16(self.state.out_samples[if (is_right) 1 else 0] +% voice_out);
        if ((self.state.echo_on & self.voice_bit) > 0) {
            self.state.echo_out[if (is_right) 1 else 0] = clamp16(self.state.echo_out[if (is_right) 1 else 0] +% voice_out);
        }
    }

    pub fn step1(self: *Self) void {
        self.state.sample_address = (@as(u16, self.state.dir_sample_table_address) * 0x100) +% (@as(u16, self.state.source_number) * 4);
        self.state.source_number = self.regs[@intFromEnum(VoiceRegs.srcn)];
    }

    pub fn step2(self: *Self) void {
        var addr = self.state.sample_address;
        if (self.key_on_delay == 0) addr +%= 2;
        self.state.brr_next_address = (@as(u16, self.ram[addr +% 1]) << 8) | self.ram[addr];
        self.state.adsr1 = self.regs[@intFromEnum(VoiceRegs.adsr1)];
        self.state.pitch = self.regs[@intFromEnum(VoiceRegs.pitch_low)];
    }

    pub fn step3(self: *Self, flags: u8) void {
        self.step3a();
        self.step3b();
        self.step3c(flags);
    }

    pub fn step3a(self: *Self) void {
        self.state.pitch |= @as(u16, self.regs[@intFromEnum(VoiceRegs.pitch_high)] & 0x3f) << 8;
    }

    pub fn step3b(self: *Self) void {
        self.state.brr_header = self.ram[self.brr_address];
        self.state.brr_data = self.ram[self.brr_address +% self.brr_offset];
    }

    pub fn step3c(self: *Self, flags: u8) void {
        if ((self.state.pitch_modulation_on & self.voice_bit) > 0) {
            self.state.pitch += ((self.state.voice_output >> 5) *% self.state.pitch) >> 10;
        }

        if (self.key_on_delay > 0) {
            if (self.key_on_delay == 5) {
                self.brr_address = self.state.brr_next_address;
                self.brr_offset = 1;
                self.buffer_pos = 0;
                self.state.brr_header = 0;
            }

            self.env_volume = 0;
            self.prev_calculated_env = 0;
            self.key_on_delay -%= 1;
            self.interpolation_pos = if ((self.key_on_delay & 0x03) > 0) 0x4000 else 0;
            self.state.pitch = 0;
        }

        const pos: u8 = @truncate(@as(u32, @bitCast((self.interpolation_pos >> 12))) +% self.buffer_pos);
        const offset: u16 = @as(u8, @truncate(@as(u32, @bitCast((self.interpolation_pos >> 4))) & 0xff));

        var out: i32 = @as(i16, @truncate(((GAUSS_TABLE[255 - offset] * @as(i32, self.buffer[pos % 12])) >> 11) +
            ((GAUSS_TABLE[511 - offset] * @as(i32, self.buffer[(pos + 1) % 12])) >> 11) +
            ((GAUSS_TABLE[256 + offset] * @as(i32, self.buffer[(pos + 2) % 12])) >> 11)));
        out +%= (GAUSS_TABLE[offset] * @as(i32, self.buffer[(pos + 3) % 12])) >> 11;

        var output: i32 = clamp16(out) & ~@as(i16, 0x01);
        if ((self.state.noise_on & self.voice_bit) > 0) {
            output = @as(i16, @truncate(self.state.noise_lfsr *% 2));
        }

        self.state.voice_output = ((output *% self.env_volume) >> 11) & ~@as(i32, 0x01);
        self.env_out = @truncate(@as(u32, @bitCast(self.env_volume >> 4)));

        if (((flags & 0x80) > 0) or ((self.state.brr_header & 0x03) == 0x01)) {
            self.mode = .release;
            self.env_volume = 0;
        }

        if (self.state.every_other_sample) {
            if ((self.state.key_off & self.voice_bit) > 0) {
                self.mode = .release;
            }

            if ((self.state.key_on & self.voice_bit) > 0) {
                self.key_on_delay = 5;
                self.mode = .attack;
            }
        }

        if (self.key_on_delay == 0) {
            self.processEnvelope();
        }
    }

    pub fn step4(self: *Self) void {
        self.state.looped = 0;
        if (self.interpolation_pos >= 0x4000) {
            self.decodeBrrSample();
            if (self.brr_offset >= 7) {
                if ((self.state.brr_header & 0x01) > 0) {
                    self.brr_address = self.state.brr_next_address;
                    self.state.looped = self.voice_bit;
                } else {
                    self.brr_address +%= 9;
                }
                self.brr_offset = 1;
            } else {
                self.brr_offset +%= 2;
            }
        }

        self.interpolation_pos = (self.interpolation_pos & 0x3fff) +% self.state.pitch;
        if (self.interpolation_pos > 0x7fff) self.interpolation_pos = 0x7fff;
        self.updateOutput(false);
    }

    pub fn step5(self: *Self, voice_end: u8) void {
        self.updateOutput(true);
        var v = voice_end;
        v |= self.state.looped;
        if (self.key_on_delay == 5) v &= ~self.voice_bit;
        self.state.voice_end_buffer = v;
    }

    pub fn step6(self: *Self) void {
        self.state.out_reg_buffer = @truncate(@as(u32, @bitCast(self.state.voice_output >> 8)));
    }

    pub fn step7(self: *Self) u8 {
        self.state.env_reg_buffer = self.env_out;
        return self.state.voice_end_buffer;
    }

    pub fn step8(self: *Self) void {
        self.regs[@intFromEnum(VoiceRegs.outx)] = self.state.out_reg_buffer;
    }

    pub fn step9(self: *Self) void {
        self.regs[@intFromEnum(VoiceRegs.envx)] = self.state.env_reg_buffer;
    }

    pub fn serialize(self: *const Voice, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "buffer");
        c.mpack_build_array(pack);
        for (self.buffer) |v| c.mpack_write_i16(pack, v);
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "mode");
        c.mpack_write_u8(pack, @intFromEnum(self.mode));
        c.mpack_write_cstr(pack, "buffer_pos");
        c.mpack_write_u8(pack, self.buffer_pos);
        c.mpack_write_cstr(pack, "env_volume");
        c.mpack_write_i32(pack, self.env_volume);
        c.mpack_write_cstr(pack, "prev_calculated_env");
        c.mpack_write_i32(pack, self.prev_calculated_env);
        c.mpack_write_cstr(pack, "interpolation_pos");
        c.mpack_write_i32(pack, self.interpolation_pos);
        c.mpack_write_cstr(pack, "brr_address");
        c.mpack_write_u16(pack, self.brr_address);
        c.mpack_write_cstr(pack, "brr_offset");
        c.mpack_write_u16(pack, self.brr_offset);
        c.mpack_write_cstr(pack, "voice_index");
        c.mpack_write_u8(pack, self.voice_index);
        c.mpack_write_cstr(pack, "voice_bit");
        c.mpack_write_u8(pack, self.voice_bit);
        c.mpack_write_cstr(pack, "key_on_delay");
        c.mpack_write_u8(pack, self.key_on_delay);
        c.mpack_write_cstr(pack, "env_out");
        c.mpack_write_u8(pack, self.env_out);

        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *Voice, pack: c.mpack_node_t) void {
        @memset(&self.buffer, 0);
        for (0..self.buffer.len) |i| {
            self.buffer[i] = c.mpack_node_i16(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "buffer"), i));
        }

        self.mode = @enumFromInt(@as(u2, @truncate(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "mode")))));
        self.buffer_pos = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "buffer_pos"));
        self.env_volume = c.mpack_node_i32(c.mpack_node_map_cstr(pack, "env_volume"));
        self.prev_calculated_env = c.mpack_node_i32(c.mpack_node_map_cstr(pack, "prev_calculated_env"));
        self.interpolation_pos = c.mpack_node_i32(c.mpack_node_map_cstr(pack, "interpolation_pos"));
        self.brr_address = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "brr_address"));
        self.brr_offset = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "brr_offset"));
        self.voice_index = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "voice_index"));
        self.voice_bit = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "voice_bit"));
        self.key_on_delay = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "key_on_delay"));
        self.env_out = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "env_out"));
    }
};

const GAUSS_TABLE: [512]i32 = [_]i32{
    0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, //
    0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x001, 0x002, 0x002, 0x002, 0x002, 0x002, //
    0x002, 0x002, 0x003, 0x003, 0x003, 0x003, 0x003, 0x004, 0x004, 0x004, 0x004, 0x004, 0x005, 0x005, 0x005, 0x005, //
    0x006, 0x006, 0x006, 0x006, 0x007, 0x007, 0x007, 0x008, 0x008, 0x008, 0x009, 0x009, 0x009, 0x00a, 0x00a, 0x00a, //
    0x00b, 0x00b, 0x00b, 0x00c, 0x00c, 0x00d, 0x00d, 0x00e, 0x00e, 0x00f, 0x00f, 0x00f, 0x010, 0x010, 0x011, 0x011, //
    0x012, 0x013, 0x013, 0x014, 0x014, 0x015, 0x015, 0x016, 0x017, 0x017, 0x018, 0x018, 0x019, 0x01a, 0x01b, 0x01b, //
    0x01c, 0x01d, 0x01d, 0x01e, 0x01f, 0x020, 0x020, 0x021, 0x022, 0x023, 0x024, 0x024, 0x025, 0x026, 0x027, 0x028, //
    0x029, 0x02a, 0x02b, 0x02c, 0x02d, 0x02e, 0x02f, 0x030, 0x031, 0x032, 0x033, 0x034, 0x035, 0x036, 0x037, 0x038, //
    0x03a, 0x03b, 0x03c, 0x03d, 0x03e, 0x040, 0x041, 0x042, 0x043, 0x045, 0x046, 0x047, 0x049, 0x04a, 0x04c, 0x04d, //
    0x04e, 0x050, 0x051, 0x053, 0x054, 0x056, 0x057, 0x059, 0x05a, 0x05c, 0x05e, 0x05f, 0x061, 0x063, 0x064, 0x066, //
    0x068, 0x06a, 0x06b, 0x06d, 0x06f, 0x071, 0x073, 0x075, 0x076, 0x078, 0x07a, 0x07c, 0x07e, 0x080, 0x082, 0x084, //
    0x086, 0x089, 0x08b, 0x08d, 0x08f, 0x091, 0x093, 0x096, 0x098, 0x09a, 0x09c, 0x09f, 0x0a1, 0x0a3, 0x0a6, 0x0a8, //
    0x0ab, 0x0ad, 0x0af, 0x0b2, 0x0b4, 0x0b7, 0x0ba, 0x0bc, 0x0bf, 0x0c1, 0x0c4, 0x0c7, 0x0c9, 0x0cc, 0x0cf, 0x0d2, //
    0x0d4, 0x0d7, 0x0da, 0x0dd, 0x0e0, 0x0e3, 0x0e6, 0x0e9, 0x0ec, 0x0ef, 0x0f2, 0x0f5, 0x0f8, 0x0fb, 0x0fe, 0x101, //
    0x104, 0x107, 0x10b, 0x10e, 0x111, 0x114, 0x118, 0x11b, 0x11e, 0x122, 0x125, 0x129, 0x12c, 0x130, 0x133, 0x137, //
    0x13a, 0x13e, 0x141, 0x145, 0x148, 0x14c, 0x150, 0x153, 0x157, 0x15b, 0x15f, 0x162, 0x166, 0x16a, 0x16e, 0x172, //
    0x176, 0x17a, 0x17d, 0x181, 0x185, 0x189, 0x18d, 0x191, 0x195, 0x19a, 0x19e, 0x1a2, 0x1a6, 0x1aa, 0x1ae, 0x1b2, //
    0x1b7, 0x1bb, 0x1bf, 0x1c3, 0x1c8, 0x1cc, 0x1d0, 0x1d5, 0x1d9, 0x1dd, 0x1e2, 0x1e6, 0x1eb, 0x1ef, 0x1f3, 0x1f8, //
    0x1fc, 0x201, 0x205, 0x20a, 0x20f, 0x213, 0x218, 0x21c, 0x221, 0x226, 0x22a, 0x22f, 0x233, 0x238, 0x23d, 0x241, //
    0x246, 0x24b, 0x250, 0x254, 0x259, 0x25e, 0x263, 0x267, 0x26c, 0x271, 0x276, 0x27b, 0x280, 0x284, 0x289, 0x28e, //
    0x293, 0x298, 0x29d, 0x2a2, 0x2a6, 0x2ab, 0x2b0, 0x2b5, 0x2ba, 0x2bf, 0x2c4, 0x2c9, 0x2ce, 0x2d3, 0x2d8, 0x2dc, //
    0x2e1, 0x2e6, 0x2eb, 0x2f0, 0x2f5, 0x2fa, 0x2ff, 0x304, 0x309, 0x30e, 0x313, 0x318, 0x31d, 0x322, 0x326, 0x32b, //
    0x330, 0x335, 0x33a, 0x33f, 0x344, 0x349, 0x34e, 0x353, 0x357, 0x35c, 0x361, 0x366, 0x36b, 0x370, 0x374, 0x379, //
    0x37e, 0x383, 0x388, 0x38c, 0x391, 0x396, 0x39b, 0x39f, 0x3a4, 0x3a9, 0x3ad, 0x3b2, 0x3b7, 0x3bb, 0x3c0, 0x3c5, //
    0x3c9, 0x3ce, 0x3d2, 0x3d7, 0x3dc, 0x3e0, 0x3e5, 0x3e9, 0x3ed, 0x3f2, 0x3f6, 0x3fb, 0x3ff, 0x403, 0x408, 0x40c, //
    0x410, 0x415, 0x419, 0x41d, 0x421, 0x425, 0x42a, 0x42e, 0x432, 0x436, 0x43a, 0x43e, 0x442, 0x446, 0x44a, 0x44e, //
    0x452, 0x455, 0x459, 0x45d, 0x461, 0x465, 0x468, 0x46c, 0x470, 0x473, 0x477, 0x47a, 0x47e, 0x481, 0x485, 0x488, //
    0x48c, 0x48f, 0x492, 0x496, 0x499, 0x49c, 0x49f, 0x4a2, 0x4a6, 0x4a9, 0x4ac, 0x4af, 0x4b2, 0x4b5, 0x4b7, 0x4ba, //
    0x4bd, 0x4c0, 0x4c3, 0x4c5, 0x4c8, 0x4cb, 0x4cd, 0x4d0, 0x4d2, 0x4d5, 0x4d7, 0x4d9, 0x4dc, 0x4de, 0x4e0, 0x4e3, //
    0x4e5, 0x4e7, 0x4e9, 0x4eb, 0x4ed, 0x4ef, 0x4f1, 0x4f3, 0x4f5, 0x4f6, 0x4f8, 0x4fa, 0x4fb, 0x4fd, 0x4ff, 0x500, //
    0x502, 0x503, 0x504, 0x506, 0x507, 0x508, 0x50a, 0x50b, 0x50c, 0x50d, 0x50e, 0x50f, 0x510, 0x511, 0x511, 0x512, //
    0x513, 0x514, 0x514, 0x515, 0x516, 0x516, 0x517, 0x517, 0x517, 0x518, 0x518, 0x518, 0x518, 0x518, 0x519, 0x519, //
};
