const std = @import("std");
const Voice = @import("voice.zig").Voice;
const c = @import("../../../c.zig");

pub fn clamp16(v: i32) i16 {
    if (v > std.math.maxInt(i16)) return std.math.maxInt(i16);
    if (v < std.math.minInt(i16)) return std.math.minInt(i16);
    return @as(i16, @intCast(v));
}

pub const GlobalRegs = enum(u8) {
    master_vol_left = 0x0c,
    master_vol_right = 0x1c,
    echo_vol_left = 0x2c,
    echo_vol_right = 0x3c,
    key_on = 0x4c,
    key_off = 0x5c,
    flags = 0x6c,
    voice_end = 0x7c,
    echo_feedback_vol = 0x0d,
    pitch_modulation_on = 0x2d,
    noise_on = 0x3d,
    echo_on = 0x4d,
    dir_sample_table_address = 0x5d,
    echo_ring_buffer_address = 0x6d,
    echo_delay = 0x7d,
    echo_filter_coeff0 = 0x0f,
    echo_filter_coeff1 = 0x1f,
    echo_filter_coeff2 = 0x2f,
    echo_filter_coeff3 = 0x3f,
    echo_filter_coeff4 = 0x4f,
    echo_filter_coeff5 = 0x5f,
    echo_filter_coeff6 = 0x6f,
    echo_filter_coeff7 = 0x7f,
};

pub const VoiceRegs = enum(u8) {
    vol_left = 0,
    vol_right,
    pitch_low,
    pitch_high,
    srcn,
    adsr1,
    adsr2,
    gain,
    envx,
    outx,
};

pub const DSPState = struct {
    regs: [128]u8,
    noise_lfsr: i32 = 0x4000,
    counter: u16 = 0,
    step: u8 = 0,
    out_reg_buffer: u8 = 0,
    env_reg_buffer: u8 = 0,
    voice_end_buffer: u8 = 0,
    voice_output: i32 = 0,
    out_samples: [2]i32 = .{ 0, 0 },
    pitch: i32 = 0,
    sample_address: u16 = 0,
    brr_next_address: u16 = 0,
    dir_sample_table_address: u8 = 0,
    noise_on: u8 = 0,
    pitch_modulation_on: u8 = 0,
    key_on: u8 = 0,
    new_key_on: u8 = 0,
    key_off: u8 = 0,
    every_other_sample: bool = true,
    source_number: u8 = 0,
    brr_header: u8 = 0,
    brr_data: u8 = 0,
    looped: u8 = 0,
    adsr1: u8 = 0,
    echo_in: [2]i32 = .{ 0, 0 },
    echo_out: [2]i32 = .{ 0, 0 },
    echo_history: [8][2]i16 = std.mem.zeroes([8][2]i16),
    echo_pointer: u16 = 0,
    echo_length: u16 = 0,
    echo_offset: u16 = 0,
    echo_history_pos: u8 = 0,
    echo_ring_buffer_address: u8 = 0,
    echo_on: u8 = 0,
    echo_enabled: bool = false,

    pub fn serialize(self: *const DSPState, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "regs");
        c.mpack_start_bin(pack, @intCast(self.regs.len));
        c.mpack_write_bytes(pack, &self.regs, self.regs.len);
        c.mpack_finish_bin(pack);

        c.mpack_write_cstr(pack, "out_samples");
        c.mpack_build_array(pack);
        for (self.out_samples) |v| c.mpack_write_i32(pack, v);
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "echo_in");
        c.mpack_build_array(pack);
        for (self.echo_in) |v| c.mpack_write_i32(pack, v);
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "echo_out");
        c.mpack_build_array(pack);
        for (self.echo_out) |v| c.mpack_write_i32(pack, v);
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "echo_history");
        c.mpack_build_array(pack);
        for (self.echo_history) |k| {
            c.mpack_build_array(pack);
            for (k) |v| c.mpack_write_i16(pack, v);
            c.mpack_complete_array(pack);
        }
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "noise_lfsr");
        c.mpack_write_i32(pack, self.noise_lfsr);
        c.mpack_write_cstr(pack, "counter");
        c.mpack_write_u16(pack, self.counter);
        c.mpack_write_cstr(pack, "step");
        c.mpack_write_u8(pack, self.step);
        c.mpack_write_cstr(pack, "out_reg_buffer");
        c.mpack_write_u8(pack, self.out_reg_buffer);
        c.mpack_write_cstr(pack, "env_reg_buffer");
        c.mpack_write_u8(pack, self.env_reg_buffer);
        c.mpack_write_cstr(pack, "voice_end_buffer");
        c.mpack_write_u8(pack, self.voice_end_buffer);
        c.mpack_write_cstr(pack, "voice_output");
        c.mpack_write_i32(pack, self.voice_output);
        c.mpack_write_cstr(pack, "pitch");
        c.mpack_write_i32(pack, self.pitch);
        c.mpack_write_cstr(pack, "sample_address");
        c.mpack_write_u16(pack, self.sample_address);
        c.mpack_write_cstr(pack, "brr_next_address");
        c.mpack_write_u16(pack, self.brr_next_address);
        c.mpack_write_cstr(pack, "dir_sample_table_address");
        c.mpack_write_u8(pack, self.dir_sample_table_address);
        c.mpack_write_cstr(pack, "noise_on");
        c.mpack_write_u8(pack, self.noise_on);
        c.mpack_write_cstr(pack, "pitch_modulation_on");
        c.mpack_write_u8(pack, self.pitch_modulation_on);
        c.mpack_write_cstr(pack, "key_on");
        c.mpack_write_u8(pack, self.key_on);
        c.mpack_write_cstr(pack, "new_key_on");
        c.mpack_write_u8(pack, self.new_key_on);
        c.mpack_write_cstr(pack, "key_off");
        c.mpack_write_u8(pack, self.key_off);
        c.mpack_write_cstr(pack, "every_other_sample");
        c.mpack_write_bool(pack, self.every_other_sample);
        c.mpack_write_cstr(pack, "source_number");
        c.mpack_write_u8(pack, self.source_number);
        c.mpack_write_cstr(pack, "brr_header");
        c.mpack_write_u8(pack, self.brr_header);
        c.mpack_write_cstr(pack, "brr_data");
        c.mpack_write_u8(pack, self.brr_data);
        c.mpack_write_cstr(pack, "looped");
        c.mpack_write_u8(pack, self.looped);
        c.mpack_write_cstr(pack, "adsr1");
        c.mpack_write_u8(pack, self.adsr1);
        c.mpack_write_cstr(pack, "echo_pointer");
        c.mpack_write_u16(pack, self.echo_pointer);
        c.mpack_write_cstr(pack, "echo_length");
        c.mpack_write_u16(pack, self.echo_length);
        c.mpack_write_cstr(pack, "echo_offset");
        c.mpack_write_u16(pack, self.echo_offset);
        c.mpack_write_cstr(pack, "echo_history_pos");
        c.mpack_write_u8(pack, self.echo_history_pos);
        c.mpack_write_cstr(pack, "echo_ring_buffer_address");
        c.mpack_write_u8(pack, self.echo_ring_buffer_address);
        c.mpack_write_cstr(pack, "echo_on");
        c.mpack_write_u8(pack, self.echo_on);
        c.mpack_write_cstr(pack, "echo_enabled");
        c.mpack_write_bool(pack, self.echo_enabled);

        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *DSPState, pack: c.mpack_node_t) void {
        @memset(&self.regs, 0);
        @memset(&self.out_samples, 0);
        @memset(&self.echo_in, 0);
        @memset(&self.echo_out, 0);
        @memset(&self.echo_history, std.mem.zeroes([2]i16));

        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "regs"), &self.regs, self.regs.len);

        for (0..self.out_samples.len) |i| {
            self.out_samples[i] = c.mpack_node_i32(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "out_samples"), i));
        }

        for (0..self.echo_in.len) |i| {
            self.echo_in[i] = c.mpack_node_i32(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "echo_in"), i));
        }

        for (0..self.echo_out.len) |i| {
            self.echo_out[i] = c.mpack_node_i32(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "echo_out"), i));
        }

        for (0..self.echo_history.len) |j| {
            const arr = c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "echo_history"), j);
            for (0..c.mpack_node_array_length(arr)) |i| {
                self.echo_history[j][i] = c.mpack_node_i16(c.mpack_node_array_at(arr, i));
            }
        }

        self.noise_lfsr = c.mpack_node_i32(c.mpack_node_map_cstr(pack, "noise_lfsr"));
        self.counter = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "counter"));
        self.step = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "step"));
        self.out_reg_buffer = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "out_reg_buffer"));
        self.env_reg_buffer = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "env_reg_buffer"));
        self.voice_end_buffer = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "voice_end_buffer"));
        self.voice_output = c.mpack_node_i32(c.mpack_node_map_cstr(pack, "voice_output"));
        self.pitch = c.mpack_node_i32(c.mpack_node_map_cstr(pack, "pitch"));
        self.sample_address = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "sample_address"));
        self.brr_next_address = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "brr_next_address"));
        self.dir_sample_table_address = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "dir_sample_table_address"));
        self.noise_on = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "noise_on"));
        self.pitch_modulation_on = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "pitch_modulation_on"));
        self.key_on = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "key_on"));
        self.new_key_on = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "new_key_on"));
        self.key_off = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "key_off"));
        self.every_other_sample = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "every_other_sample"));
        self.source_number = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "source_number"));
        self.brr_header = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "brr_header"));
        self.brr_data = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "brr_data"));
        self.looped = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "looped"));
        self.adsr1 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "adsr1"));
        self.echo_pointer = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "echo_pointer"));
        self.echo_length = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "echo_length"));
        self.echo_offset = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "echo_offset"));
        self.echo_history_pos = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "echo_history_pos"));
        self.echo_ring_buffer_address = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "echo_ring_buffer_address"));
        self.echo_on = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "echo_on"));
        self.echo_enabled = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "echo_enabled"));
    }
};

pub const COUNTERS = struct {
    pub var rates: [32]u16 = [_]u16{
        std.math.maxInt(u16), 2048, 1536, 1280, 1024, 768, 640, 512, //
        384, 320, 256, 192, 160, 128, 96, 80, //
        64, 48, 40, 32, 24, 20, 16, 12, //
        10, 8, 6, 5, 4, 3, 2, 1, //
    };

    pub var offsets: [32]u16 = [_]u16{
        1, 0, 1040, 536, 0, 1040, 536, 0, //
        1040, 536, 0, 1040, 536, 0, 1040, 536, //
        0, 1040, 536, 0, 1040, 536, 0, 1040, //
        536, 0, 1040, 536, 0, 1040, 0, 0, //
    };
};

const blip_t = extern struct {
    factor: usize,
    offset: usize,
    avail: c_int,
    size: c_int,
    integrator: c_int,
};

pub const DSP = struct {
    allocator: std.mem.Allocator,
    ram: []u8,
    state: DSPState,
    voices: [8]Voice = [_]Voice{std.mem.zeroInit(Voice, .{ .state = undefined })} ** 8,

    samples: u32 = 0,
    left_buf: *blip_t,
    right_buf: *blip_t,
    previous_left_output: i32 = 0,
    previous_right_output: i32 = 0,

    pub fn init(allocator: std.mem.Allocator, ram: []u8) !*DSP {
        const left_buf = c.blip_new(882) orelse return error.BlipError;
        const right_buf = c.blip_new(882) orelse return error.BlipError;
        c.blip_set_rates(left_buf, 32000, 44100);
        c.blip_set_rates(right_buf, 32000, 44100);

        const instance = try allocator.create(DSP);
        instance.* = .{
            .allocator = allocator,
            .left_buf = @as(*blip_t, @ptrCast(@alignCast(left_buf))),
            .right_buf = @as(*blip_t, @ptrCast(@alignCast(right_buf))),
            .ram = ram,
            .state = std.mem.zeroes(DSPState),
        };

        for (0..8) |i| {
            var voice = &instance.voices[i];
            voice.ram = ram;
            voice.state = &instance.state;
            voice.regs = instance.state.regs[i * 0x10 .. (i + 1) * 0x10];
            voice.voice_index = @intCast(i);
            voice.voice_bit = @as(u8, 1) << @as(u3, @intCast(i));
        }

        instance.reset();
        return instance;
    }

    pub fn deinit(self: *DSP) void {
        const left_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.left_buf)));
        const right_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.right_buf)));
        c.blip_delete(left_buf);
        c.blip_delete(right_buf);
        self.allocator.destroy(self);
    }

    pub fn read(self: *DSP, address: u8) u8 {
        return self.state.regs[address];
    }

    pub fn write(self: *DSP, address: u8, value: u8) void {
        self.state.regs[address] = value;
        switch (address & 0xf) {
            @intFromEnum(VoiceRegs.envx) => self.state.env_reg_buffer = value,
            @intFromEnum(VoiceRegs.outx) => self.state.out_reg_buffer = value,
            0x0c => switch (address) {
                @intFromEnum(GlobalRegs.key_on) => {
                    self.state.new_key_on = value;
                },
                @intFromEnum(GlobalRegs.voice_end) => {
                    self.state.voice_end_buffer = 0;
                    self.state.regs[@intFromEnum(GlobalRegs.voice_end)] = 0;
                },
                else => {},
            },
            else => {},
        }
    }

    pub fn process(self: *DSP) void {
        self.state.step = (self.state.step + 1) & 0x1f;
        switch (self.state.step) {
            0 => {
                self.voices[0].step5(self.state.regs[@intFromEnum(GlobalRegs.voice_end)]);
                self.voices[1].step2();
            },
            1 => {
                self.voices[0].step6();
                self.voices[1].step3(self.state.regs[@intFromEnum(GlobalRegs.flags)]);
            },
            2 => {
                self.state.regs[@intFromEnum(GlobalRegs.voice_end)] = self.voices[0].step7();
                self.voices[1].step4();
                self.voices[3].step1();
            },
            3 => {
                self.voices[0].step8();
                self.voices[1].step5(self.state.regs[@intFromEnum(GlobalRegs.voice_end)]);
                self.voices[2].step2();
            },
            4 => {
                self.voices[0].step9();
                self.voices[1].step6();
                self.voices[2].step3(self.state.regs[@intFromEnum(GlobalRegs.flags)]);
            },
            5 => {
                self.state.regs[@intFromEnum(GlobalRegs.voice_end)] = self.voices[1].step7();
                self.voices[2].step4();
                self.voices[4].step1();
            },
            6 => {
                self.voices[1].step8();
                self.voices[2].step5(self.state.regs[@intFromEnum(GlobalRegs.voice_end)]);
                self.voices[3].step2();
            },
            7 => {
                self.voices[1].step9();
                self.voices[2].step6();
                self.voices[3].step3(self.state.regs[@intFromEnum(GlobalRegs.flags)]);
            },
            8 => {
                self.state.regs[@intFromEnum(GlobalRegs.voice_end)] = self.voices[2].step7();
                self.voices[3].step4();
                self.voices[5].step1();
            },
            9 => {
                self.voices[2].step8();
                self.voices[3].step5(self.state.regs[@intFromEnum(GlobalRegs.voice_end)]);
                self.voices[4].step2();
            },
            10 => {
                self.voices[2].step9();
                self.voices[3].step6();
                self.voices[4].step3(self.state.regs[@intFromEnum(GlobalRegs.flags)]);
            },
            11 => {
                self.state.regs[@intFromEnum(GlobalRegs.voice_end)] = self.voices[3].step7();
                self.voices[4].step4();
                self.voices[6].step1();
            },
            12 => {
                self.voices[3].step8();
                self.voices[4].step5(self.state.regs[@intFromEnum(GlobalRegs.voice_end)]);
                self.voices[5].step2();
            },
            13 => {
                self.voices[3].step9();
                self.voices[4].step6();
                self.voices[5].step3(self.state.regs[@intFromEnum(GlobalRegs.flags)]);
            },
            14 => {
                self.state.regs[@intFromEnum(GlobalRegs.voice_end)] = self.voices[4].step7();
                self.voices[5].step4();
                self.voices[7].step1();
            },
            15 => {
                self.voices[4].step8();
                self.voices[5].step5(self.state.regs[@intFromEnum(GlobalRegs.voice_end)]);
                self.voices[6].step2();
            },
            16 => {
                self.voices[4].step9();
                self.voices[5].step6();
                self.voices[6].step3(self.state.regs[@intFromEnum(GlobalRegs.flags)]);
            },
            17 => {
                self.voices[0].step1();
                self.state.regs[@intFromEnum(GlobalRegs.voice_end)] = self.voices[5].step7();
                self.voices[6].step4();
            },
            18 => {
                self.voices[5].step8();
                self.voices[6].step5(self.state.regs[@intFromEnum(GlobalRegs.voice_end)]);
                self.voices[7].step2();
            },
            19 => {
                self.voices[5].step9();
                self.voices[6].step6();
                self.voices[7].step3(self.state.regs[@intFromEnum(GlobalRegs.flags)]);
            },
            20 => {
                self.voices[1].step1();
                self.state.regs[@intFromEnum(GlobalRegs.voice_end)] = self.voices[6].step7();
                self.voices[7].step4();
            },
            21 => {
                self.voices[6].step8();
                self.voices[7].step5(self.state.regs[@intFromEnum(GlobalRegs.voice_end)]);
                self.voices[0].step2();
            },
            22 => {
                self.voices[0].step3a();
                self.voices[6].step9();
                self.voices[7].step6();
                self.echoStep22();
            },
            23 => {
                self.state.regs[@intFromEnum(GlobalRegs.voice_end)] = self.voices[7].step7();
                self.echoStep23();
            },
            24 => {
                self.voices[7].step8();
                self.echoStep24();
            },
            25 => {
                self.voices[0].step3b();
                self.voices[7].step9();
                self.echoStep25();
            },
            26 => {
                self.echoStep26();
            },
            27 => {
                self.state.pitch_modulation_on = self.state.regs[@intFromEnum(GlobalRegs.pitch_modulation_on)] & 0xfe;
                self.echoStep27();
                if ((self.state.regs[@intFromEnum(GlobalRegs.flags)] & 0x40) > 0) {
                    const left_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.left_buf)));
                    if (self.previous_left_output != 0) {
                        c.blip_add_delta(left_buf, self.samples, -self.previous_left_output);
                        self.previous_left_output = 0;
                    }
                    const right_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.right_buf)));
                    if (self.previous_right_output != 0) {
                        c.blip_add_delta(right_buf, self.samples, -self.previous_right_output);
                        self.previous_right_output = 0;
                    }
                } else {
                    const left: i32 = @as(i16, @truncate(self.state.out_samples[0]));
                    const right: i32 = @as(i16, @truncate(self.state.out_samples[1]));
                    const left_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.left_buf)));
                    if (self.previous_left_output != left) {
                        c.blip_add_delta(left_buf, self.samples, left - self.previous_left_output);
                        self.previous_left_output = left;
                    }
                    const right_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.right_buf)));
                    if (self.previous_right_output != right) {
                        c.blip_add_delta(right_buf, self.samples, right - self.previous_right_output);
                        self.previous_right_output = right;
                    }
                }
                self.state.out_samples[0] = 0;
                self.state.out_samples[1] = 0;
                self.samples += 1;
            },
            28 => {
                self.state.dir_sample_table_address = self.state.regs[@intFromEnum(GlobalRegs.dir_sample_table_address)];
                self.state.noise_on = self.state.regs[@intFromEnum(GlobalRegs.noise_on)];
                self.state.echo_on = self.state.regs[@intFromEnum(GlobalRegs.echo_on)];
                self.echoStep28();
            },
            29 => {
                self.state.every_other_sample = !self.state.every_other_sample;
                if (self.state.every_other_sample) self.state.new_key_on &= ~self.state.key_on;
                self.echoStep29();
            },
            30 => {
                if (self.state.every_other_sample) {
                    self.state.key_on = self.state.new_key_on;
                    self.state.key_off = self.state.regs[@intFromEnum(GlobalRegs.key_off)];
                }
                if (self.state.counter == 0) {
                    self.state.counter = 0x77ff;
                } else {
                    self.state.counter -%= 1;
                }
                const rate = self.state.regs[@intFromEnum(GlobalRegs.flags)] & 0x1f;
                if (((self.state.counter + COUNTERS.offsets[rate]) % COUNTERS.rates[rate]) == 0) {
                    const new_bit = ((self.state.noise_lfsr << 14) ^ (self.state.noise_lfsr << 13)) & 0x4000;
                    self.state.noise_lfsr = new_bit ^ (self.state.noise_lfsr >> 1);
                }
                self.voices[0].step3c(self.state.regs[@intFromEnum(GlobalRegs.flags)]);
                self.echoStep30();
            },
            31 => {
                self.voices[0].step4();
                self.voices[2].step1();
            },
            else => {},
        }
    }

    fn calculateFir(self: *DSP, index: usize, ch: usize) i32 {
        return (@as(i32, self.state.echo_history[(self.state.echo_history_pos + index + 1) & 0x07][ch]) *
            @as(i8, @bitCast(self.state.regs[@intFromEnum(GlobalRegs.echo_filter_coeff0) + (index << 4)]))) >> 6;
    }

    fn echoStep22(self: *DSP) void {
        self.state.echo_history_pos = (self.state.echo_history_pos + 1) & 0x07;
        self.state.echo_pointer = (@as(u16, self.state.echo_ring_buffer_address) << 8) + self.state.echo_offset;
        const s: i16 = @bitCast(@as(u16, self.ram[self.state.echo_pointer + 1]) << 8 | self.ram[self.state.echo_pointer]);
        self.state.echo_history[self.state.echo_history_pos][0] = s >> 1;
        self.state.echo_in[0] = self.calculateFir(0, 0);
        self.state.echo_in[1] = self.calculateFir(0, 1);
    }

    fn echoStep23(self: *DSP) void {
        const s: i16 = @bitCast(@as(u16, self.ram[self.state.echo_pointer + 3]) << 8 | self.ram[self.state.echo_pointer + 2]);
        self.state.echo_history[self.state.echo_history_pos][1] = s >> 1;
        self.state.echo_in[0] += self.calculateFir(1, 0) + self.calculateFir(2, 0);
        self.state.echo_in[1] += self.calculateFir(1, 1) + self.calculateFir(2, 1);
    }

    fn echoStep24(self: *DSP) void {
        self.state.echo_in[0] += self.calculateFir(3, 0) + self.calculateFir(4, 0) + self.calculateFir(5, 0);
        self.state.echo_in[1] += self.calculateFir(3, 1) + self.calculateFir(4, 1) + self.calculateFir(5, 1);
    }

    fn echoStep25(self: *DSP) void {
        const left: i32 = @as(i16, @truncate(self.state.echo_in[0] + self.calculateFir(6, 0)));
        const right: i32 = @as(i16, @truncate(self.state.echo_in[1] + self.calculateFir(6, 1)));
        self.state.echo_in[0] = clamp16(left + @as(i16, @truncate(self.calculateFir(7, 0)))) & ~@as(i16, 0x01);
        self.state.echo_in[1] = clamp16(right + @as(i16, @truncate(self.calculateFir(7, 1)))) & ~@as(i16, 0x01);
    }

    fn echoStep26(self: *DSP) void {
        self.state.out_samples[0] = clamp16(((self.state.out_samples[0] * @as(i8, @bitCast(self.state.regs[@intFromEnum(GlobalRegs.master_vol_left)]))) >> 7) +
            ((self.state.echo_in[0] * @as(i8, @bitCast(self.state.regs[@intFromEnum(GlobalRegs.echo_vol_left)]))) >> 7));

        const left_echo: i32 = self.state.echo_out[0] + @as(i16, @truncate((self.state.echo_in[0] * @as(i8, @bitCast(self.state.regs[@intFromEnum(GlobalRegs.echo_feedback_vol)]))) >> 7));
        const right_echo: i32 = self.state.echo_out[1] + @as(i16, @truncate((self.state.echo_in[1] * @as(i8, @bitCast(self.state.regs[@intFromEnum(GlobalRegs.echo_feedback_vol)]))) >> 7));
        self.state.echo_out[0] = clamp16(left_echo) & ~@as(i16, 0x01);
        self.state.echo_out[1] = clamp16(right_echo) & ~@as(i16, 0x01);
    }

    fn echoStep27(self: *DSP) void {
        self.state.out_samples[1] = clamp16(((self.state.out_samples[1] * @as(i8, @bitCast(self.state.regs[@intFromEnum(GlobalRegs.master_vol_right)]))) >> 7) +
            ((self.state.echo_in[1] * @as(i8, @bitCast(self.state.regs[@intFromEnum(GlobalRegs.echo_vol_right)]))) >> 7));
    }

    fn echoStep28(self: *DSP) void {
        self.state.echo_enabled = (self.state.regs[@intFromEnum(GlobalRegs.flags)] & 0x20) == 0;
    }

    fn echoStep29(self: *DSP) void {
        if (self.state.echo_offset == 0) {
            self.state.echo_length = @as(u16, self.state.regs[@intFromEnum(GlobalRegs.echo_delay)] & 0x0f) << 11;
        }

        self.state.echo_offset += 4;
        if (self.state.echo_offset >= self.state.echo_length) self.state.echo_offset = 0;

        if (self.state.echo_enabled) {
            self.ram[self.state.echo_pointer] = @as(u8, @truncate(@as(u32, @bitCast(self.state.echo_out[0]))));
            self.ram[self.state.echo_pointer + 1] = @as(u8, @truncate(@as(u32, @bitCast(self.state.echo_out[0] >> 8))));
        }

        self.state.echo_out[0] = 0;
        self.state.echo_ring_buffer_address = self.state.regs[@intFromEnum(GlobalRegs.echo_ring_buffer_address)];
        self.state.echo_enabled = (self.state.regs[@intFromEnum(GlobalRegs.flags)] & 0x20) == 0;
    }

    fn echoStep30(self: *DSP) void {
        if (self.state.echo_enabled) {
            self.ram[self.state.echo_pointer + 2] = @as(u8, @truncate(@as(u32, @bitCast(self.state.echo_out[1]))));
            self.ram[self.state.echo_pointer + 3] = @as(u8, @truncate(@as(u32, @bitCast(self.state.echo_out[1] >> 8))));
        }
        self.state.echo_out[1] = 0;
    }

    pub fn reset(self: *DSP) void {
        const left_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.left_buf)));
        const right_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.right_buf)));
        c.blip_clear(left_buf);
        c.blip_clear(right_buf);
        self.samples = 0;

        self.state.regs[@intFromEnum(GlobalRegs.flags)] = 0xe0;
        self.state.counter = 0;
        self.state.echo_history_pos = 0;
        self.state.echo_offset = 0;
        self.state.every_other_sample = true;
        self.state.noise_lfsr = 0x4000;
        self.state.step = 0;
    }

    pub fn serialize(self: *const DSP, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "voices");
        c.mpack_build_array(pack);
        for (self.voices) |v| {
            v.serialize(pack);
        }
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "left_buf");
        c.mpack_build_map(pack);
        if (@sizeOf(usize) == 8) {
            c.mpack_write_cstr(pack, "factor");
            c.mpack_write_u64(pack, self.left_buf.factor);
            c.mpack_write_cstr(pack, "offset");
            c.mpack_write_u64(pack, self.left_buf.offset);
        } else {
            c.mpack_write_cstr(pack, "factor");
            c.mpack_write_u32(pack, self.left_buf.factor);
            c.mpack_write_cstr(pack, "offset");
            c.mpack_write_u32(pack, self.left_buf.offset);
        }
        c.mpack_write_cstr(pack, "avail");
        c.mpack_write_i32(pack, self.left_buf.avail);
        c.mpack_write_cstr(pack, "size");
        c.mpack_write_i32(pack, self.left_buf.size);
        c.mpack_write_cstr(pack, "integrator");
        c.mpack_write_i32(pack, self.left_buf.integrator);
        c.mpack_complete_map(pack);

        c.mpack_write_cstr(pack, "right_buf");
        c.mpack_build_map(pack);
        if (@sizeOf(usize) == 8) {
            c.mpack_write_cstr(pack, "factor");
            c.mpack_write_u64(pack, self.right_buf.factor);
            c.mpack_write_cstr(pack, "offset");
            c.mpack_write_u64(pack, self.right_buf.offset);
        } else {
            c.mpack_write_cstr(pack, "factor");
            c.mpack_write_u32(pack, self.right_buf.factor);
            c.mpack_write_cstr(pack, "offset");
            c.mpack_write_u32(pack, self.right_buf.offset);
        }
        c.mpack_write_cstr(pack, "avail");
        c.mpack_write_i32(pack, self.right_buf.avail);
        c.mpack_write_cstr(pack, "size");
        c.mpack_write_i32(pack, self.right_buf.size);
        c.mpack_write_cstr(pack, "integrator");
        c.mpack_write_i32(pack, self.right_buf.integrator);
        c.mpack_complete_map(pack);

        c.mpack_write_cstr(pack, "state");
        self.state.serialize(pack);

        c.mpack_write_cstr(pack, "samples");
        c.mpack_write_u32(pack, self.samples);
        c.mpack_write_cstr(pack, "previous_left_output");
        c.mpack_write_i32(pack, self.previous_left_output);
        c.mpack_write_cstr(pack, "previous_right_output");
        c.mpack_write_i32(pack, self.previous_right_output);
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *DSP, pack: c.mpack_node_t) void {
        for (0..self.voices.len) |i| {
            self.voices[i].deserialize(c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "voices"), i));
        }

        const left_buf = c.mpack_node_map_cstr(pack, "left_buf");
        if (@sizeOf(usize) == 8) {
            self.left_buf.factor = c.mpack_node_u64(c.mpack_node_map_cstr(left_buf, "factor"));
            self.left_buf.offset = c.mpack_node_u64(c.mpack_node_map_cstr(left_buf, "offset"));
        } else {
            self.left_buf.factor = c.mpack_node_u32(c.mpack_node_map_cstr(left_buf, "factor"));
            self.left_buf.offset = c.mpack_node_u32(c.mpack_node_map_cstr(left_buf, "offset"));
        }
        self.left_buf.avail = c.mpack_node_i32(c.mpack_node_map_cstr(left_buf, "avail"));
        self.left_buf.size = c.mpack_node_i32(c.mpack_node_map_cstr(left_buf, "size"));
        self.left_buf.integrator = c.mpack_node_i32(c.mpack_node_map_cstr(left_buf, "integrator"));

        const right_buf = c.mpack_node_map_cstr(pack, "right_buf");
        if (@sizeOf(usize) == 8) {
            self.right_buf.factor = c.mpack_node_u64(c.mpack_node_map_cstr(right_buf, "factor"));
            self.right_buf.offset = c.mpack_node_u64(c.mpack_node_map_cstr(right_buf, "offset"));
        } else {
            self.right_buf.factor = c.mpack_node_u32(c.mpack_node_map_cstr(right_buf, "factor"));
            self.right_buf.offset = c.mpack_node_u32(c.mpack_node_map_cstr(right_buf, "offset"));
        }
        self.right_buf.avail = c.mpack_node_i32(c.mpack_node_map_cstr(right_buf, "avail"));
        self.right_buf.size = c.mpack_node_i32(c.mpack_node_map_cstr(right_buf, "size"));
        self.right_buf.integrator = c.mpack_node_i32(c.mpack_node_map_cstr(right_buf, "integrator"));

        self.state.deserialize(c.mpack_node_map_cstr(pack, "state"));

        self.samples = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "samples"));
        self.previous_left_output = c.mpack_node_i32(c.mpack_node_map_cstr(pack, "previous_left_output"));
        self.previous_right_output = c.mpack_node_i32(c.mpack_node_map_cstr(pack, "previous_right_output"));
    }
};
