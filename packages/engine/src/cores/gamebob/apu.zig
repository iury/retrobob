const std = @import("std");
const IO = @import("io.zig").IO;
const Memory = @import("../../memory.zig").Memory;
const c = @import("../../c.zig");

const DUTY_TABLE: [4][8]u1 = [_][8]u1{
    .{ 0, 0, 0, 0, 0, 0, 0, 1 },
    .{ 1, 0, 0, 0, 0, 0, 0, 1 },
    .{ 1, 0, 0, 0, 0, 1, 1, 1 },
    .{ 0, 1, 1, 1, 1, 1, 1, 0 },
};

const CTRL = packed struct {
    ch1_on: bool,
    ch2_on: bool,
    ch3_on: bool,
    ch4_on: bool,
    unused: u3,
    enable: bool,
};

const Panning = packed struct {
    ch1_right: bool,
    ch2_right: bool,
    ch3_right: bool,
    ch4_right: bool,
    ch1_left: bool,
    ch2_left: bool,
    ch3_left: bool,
    ch4_left: bool,
};

const Volume = packed struct {
    right: u3,
    vin_right: u1,
    left: u3,
    vin_left: u1,
};

const PeriodSweep = packed struct {
    step: u3,
    direction: enum(u1) { add = 0, sub = 1 },
    pace: u3,
    unused: u1,
    current_pace: u3,

    pub fn tick(self: *@This(), period: *u11) bool {
        if (self.step != 0 or self.pace != 0) {
            const period_modifier: u11 = period.* >> self.step;
            if (self.current_pace <= 1) {
                self.current_pace = self.pace;
                if (self.direction == .add) {
                    const new_period = @addWithOverflow(period.*, period_modifier);
                    if (self.current_pace != 0) period.* = new_period.@"0";
                    if (new_period.@"1" == 1) return true;
                } else if (self.current_pace != 0) {
                    period.* -= period_modifier;
                }
            } else {
                self.current_pace -= 1;
            }
        }
        return false;
    }
};

const LengthTimer = packed struct {
    length: u6,
    duty: u2,
    duty_step: u3,

    pub fn tick(self: *@This()) bool {
        if (self.length == 0x3f) {
            self.length = 0;
            return true;
        } else {
            self.length += 1;
            return false;
        }
    }

    pub fn sample(self: *@This()) u1 {
        const v = DUTY_TABLE[self.duty][self.duty_step];
        self.duty_step +%= 1;
        return v;
    }
};

const Envelope = packed struct {
    pace: u3,
    direction: enum(u1) { sub = 0, add = 1 },
    initial_volume: u4,
    current_pace: u3,
    volume: u4,

    pub fn tick(self: *@This()) void {
        if (self.current_pace == 1) {
            self.current_pace = self.pace;
            if (self.direction == .add) {
                self.volume +|= 1;
            } else {
                self.volume -|= 1;
            }
        } else {
            self.current_pace -|= 1;
        }
    }
};

const ChannelControl = packed struct {
    period_high: u3,
    unused: u3,
    length_enable: bool,
    trigger: bool,
};

const NoiseFrequency = packed struct {
    divider: u3,
    lfsr_width: enum(u1) { b15 = 0, b7 = 1 },
    shift: u4,
    lfsr: u16,
};

const blip_t = extern struct {
    factor: usize,
    offset: usize,
    avail: c_int,
    size: c_int,
    integrator: c_int,
};

pub const APU = struct {
    allocator: std.mem.Allocator,
    dmg_mode: bool = false,

    apu_clock: usize = 0,
    left_buf: *blip_t,
    right_buf: *blip_t,
    previous_left_output: i32 = 0,
    previous_right_output: i32 = 0,

    div: u8 = 0,
    ctrl: CTRL = @bitCast(@as(u8, 0xf1)),
    panning: Panning = @bitCast(@as(u8, 0xf3)),
    volume: Volume = @bitCast(@as(u8, 0x77)),

    ch1_sweep: PeriodSweep = @bitCast(@as(u11, 0x480)),
    ch1_length_timer: LengthTimer = @bitCast(@as(u11, 0xbf)),
    ch1_envelope: Envelope = @bitCast(@as(u15, 0x7bf3)),
    ch1_control: ChannelControl = @bitCast(@as(u8, 0xbf)),
    ch1_period_low: u8 = 0xff,
    ch1_period: u11 = 0x7ff,
    ch1_out: u4 = 0,

    ch2_length_timer: LengthTimer = @bitCast(@as(u11, 0x3f)),
    ch2_envelope: Envelope = @bitCast(@as(u15, 0)),
    ch2_control: ChannelControl = @bitCast(@as(u8, 0xbf)),
    ch2_period_low: u8 = 0xff,
    ch2_period: u11 = 0x7ff,
    ch2_out: u4 = 0,

    ch3_enable: bool = false,
    ch3_length_timer: u8 = 0xff,
    ch3_output: enum(u2) { mute = 0, p100, p50, p25 } = .mute,
    ch3_control: ChannelControl = @bitCast(@as(u8, 0xbf)),
    ch3_period_low: u8 = 0xff,
    ch3_period: u11 = 0x7ff,
    ch3_out: u4 = 0,

    wave: [16]u8 = [_]u8{0} ** 16,
    wave_index: usize = 1,
    next_wave: u4 = 0,

    ch4_length_timer: LengthTimer = @bitCast(@as(u11, 0xff)),
    ch4_envelope: Envelope = @bitCast(@as(u15, 0)),
    ch4_control: ChannelControl = @bitCast(@as(u8, 0xbf)),
    ch4_frequency: NoiseFrequency = @bitCast(@as(u24, 0)),
    ch4_out: u4 = 0,

    pub fn init(allocator: std.mem.Allocator) !*APU {
        const left_buf = c.blip_new(735) orelse return error.BlipError;
        const right_buf = c.blip_new(735) orelse return error.BlipError;
        c.blip_set_rates(left_buf, 4213440, 44100);
        c.blip_set_rates(right_buf, 4213440, 44100);

        const instance = try allocator.create(APU);
        instance.* = .{
            .allocator = allocator,
            .left_buf = @as(*blip_t, @ptrCast(@alignCast(left_buf))),
            .right_buf = @as(*blip_t, @ptrCast(@alignCast(right_buf))),
        };

        return instance;
    }

    pub fn deinit(self: *APU) void {
        const left_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.left_buf)));
        const right_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.right_buf)));
        c.blip_delete(left_buf);
        c.blip_delete(right_buf);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return switch (address) {
            @intFromEnum(IO.NR10) => @truncate(@as(u11, @bitCast(self.ch1_sweep))),
            @intFromEnum(IO.NR11) => @truncate(@as(u11, @bitCast(self.ch1_length_timer))),
            @intFromEnum(IO.NR12) => @truncate(@as(u15, @bitCast(self.ch1_envelope))),
            @intFromEnum(IO.NR13) => @bitCast(self.ch1_period_low),
            @intFromEnum(IO.NR14) => @bitCast(self.ch1_control),
            @intFromEnum(IO.NR21) => @truncate(@as(u11, @bitCast(self.ch2_length_timer))),
            @intFromEnum(IO.NR22) => @truncate(@as(u15, @bitCast(self.ch2_envelope))),
            @intFromEnum(IO.NR23) => @bitCast(self.ch2_period_low),
            @intFromEnum(IO.NR24) => @bitCast(self.ch2_control),
            @intFromEnum(IO.NR30) => @as(u8, if (self.ch3_enable) 0x80 else 0) | 0x7f,
            @intFromEnum(IO.NR31) => self.ch3_length_timer,
            @intFromEnum(IO.NR32) => (@as(u8, @intFromEnum(self.ch3_output)) << 5) | 0x9f,
            @intFromEnum(IO.NR33) => @bitCast(self.ch3_period_low),
            @intFromEnum(IO.NR34) => @bitCast(self.ch3_control),
            @intFromEnum(IO.NR41) => @truncate(@as(u11, @bitCast(self.ch4_length_timer))),
            @intFromEnum(IO.NR42) => @truncate(@as(u15, @bitCast(self.ch4_envelope))),
            @intFromEnum(IO.NR43) => @truncate(@as(u24, @bitCast(self.ch4_frequency))),
            @intFromEnum(IO.NR44) => @bitCast(self.ch4_control),
            @intFromEnum(IO.NR50) => @bitCast(self.volume),
            @intFromEnum(IO.NR51) => @bitCast(self.panning),
            @intFromEnum(IO.NR52) => @bitCast(self.ctrl),

            0xff30...0xff3f => self.wave[address - 0xff30],

            else => 0xff,
        };
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        if (self.ctrl.enable) {
            switch (address) {
                @intFromEnum(IO.NR10) => {
                    const v = self.ch1_sweep.current_pace;
                    self.ch1_sweep = @bitCast(@as(u11, value));
                    if (v == 0) self.ch1_sweep.current_pace = self.ch1_sweep.pace;
                },
                @intFromEnum(IO.NR11) => {
                    self.ch1_length_timer = @bitCast(@as(u11, value));
                },
                @intFromEnum(IO.NR12) => {
                    const v = @as(u15, @bitCast(self.ch1_envelope)) & 0x7f00;
                    self.ch1_envelope = @bitCast(@as(u15, value) | v);
                    if (self.ch1_envelope.initial_volume == 0 and self.ch1_envelope.direction == .sub) {
                        self.ch1_envelope.current_pace = 0;
                        self.ch1_envelope.volume = 0;
                        self.ctrl.ch1_on = false;
                        self.ch1_out = 0;
                    }
                },
                @intFromEnum(IO.NR13) => {
                    self.ch1_period_low = @bitCast(value);
                },
                @intFromEnum(IO.NR14) => {
                    self.ch1_control = @bitCast(value);
                    if (self.ch1_control.trigger and (self.ch1_envelope.initial_volume > 0 or self.ch1_envelope.direction == .add)) {
                        self.ctrl.ch1_on = true;
                        self.ch1_sweep.current_pace = self.ch1_sweep.pace;
                        self.ch1_envelope.volume = self.ch1_envelope.initial_volume;
                        self.ch1_envelope.current_pace = self.ch1_envelope.pace;
                    }
                },

                @intFromEnum(IO.NR21) => {
                    self.ch2_length_timer = @bitCast(@as(u11, value));
                },
                @intFromEnum(IO.NR22) => {
                    const v = @as(u15, @bitCast(self.ch2_envelope)) & 0x7f00;
                    self.ch2_envelope = @bitCast(@as(u15, value) | v);
                    if (self.ch2_envelope.initial_volume == 0 and self.ch2_envelope.direction == .sub) {
                        self.ch2_envelope.current_pace = 0;
                        self.ch2_envelope.volume = 0;
                        self.ctrl.ch2_on = false;
                        self.ch2_out = 0;
                    }
                },
                @intFromEnum(IO.NR23) => {
                    self.ch2_period_low = @bitCast(value);
                },
                @intFromEnum(IO.NR24) => {
                    self.ch2_control = @bitCast(value);
                    if (self.ch2_control.trigger and (self.ch2_envelope.initial_volume > 0 or self.ch2_envelope.direction == .add)) {
                        self.ctrl.ch2_on = true;
                        self.ch2_envelope.volume = self.ch2_envelope.initial_volume;
                        self.ch2_envelope.current_pace = self.ch2_envelope.pace;
                    }
                },

                @intFromEnum(IO.NR30) => {
                    self.ch3_enable = (value & 0x80) > 0;
                    if (!self.ch3_enable) {
                        self.ctrl.ch3_on = false;
                        self.ch3_out = 0;
                    }
                },
                @intFromEnum(IO.NR31) => self.ch3_length_timer = value,
                @intFromEnum(IO.NR32) => self.ch3_output = @enumFromInt((value & 0x60) >> 5),
                @intFromEnum(IO.NR33) => self.ch3_period_low = @bitCast(value),
                @intFromEnum(IO.NR34) => {
                    self.ch3_control = @bitCast(value);
                    if (self.ch3_control.trigger and self.ch3_enable) {
                        self.ctrl.ch3_on = true;
                        self.wave_index = 1;
                    }
                },

                @intFromEnum(IO.NR41) => {
                    self.ch4_length_timer = @bitCast(@as(u11, value));
                },
                @intFromEnum(IO.NR42) => {
                    const v = @as(u15, @bitCast(self.ch4_envelope)) & 0x7f00;
                    self.ch4_envelope = @bitCast(@as(u15, value) | v);
                    if (self.ch4_envelope.initial_volume == 0 and self.ch4_envelope.direction == .sub) {
                        self.ch4_envelope.current_pace = 0;
                        self.ch4_envelope.volume = 0;
                        self.ctrl.ch4_on = false;
                        self.ch4_out = 0;
                    }
                },
                @intFromEnum(IO.NR43) => {
                    self.ch4_frequency = @bitCast(@as(u24, value));
                },
                @intFromEnum(IO.NR44) => {
                    self.ch4_control = @bitCast(value);
                    if (self.ch4_control.trigger and (self.ch4_envelope.initial_volume > 0 or self.ch4_envelope.direction == .add)) {
                        self.ctrl.ch4_on = true;
                        self.ch4_envelope.volume = self.ch4_envelope.initial_volume;
                        self.ch4_envelope.current_pace = self.ch4_envelope.pace;
                        self.ch4_frequency.lfsr = 0;
                    }
                },

                @intFromEnum(IO.NR50) => self.volume = @bitCast(value),
                @intFromEnum(IO.NR51) => self.panning = @bitCast(value),

                0xff30...0xff3f => self.wave[address - 0xff30] = value,

                else => {},
            }
        }

        if (address == @intFromEnum(IO.NR52)) {
            self.ctrl.enable = (value & 0x80) > 0;
            if (!self.ctrl.enable) {
                self.clear();
            }
        }
    }

    pub fn divTick(self: *APU) void {
        self.div +%= 1;

        if (!self.ctrl.enable) return;

        if (self.div % 2 == 0) {
            // length timers
            if (self.ch1_control.length_enable) {
                if (self.ch1_length_timer.tick()) {
                    self.ctrl.ch1_on = false;
                    self.ch1_out = 0;
                }
            }

            if (self.ch2_control.length_enable) {
                if (self.ch2_length_timer.tick()) {
                    self.ctrl.ch2_on = false;
                    self.ch2_out = 0;
                }
            }

            if (self.ch3_control.length_enable) {
                if (self.ch3_length_timer == 0xff) {
                    self.ch3_length_timer = 0;
                    self.ctrl.ch3_on = false;
                    self.ch3_out = 0;
                } else {
                    self.ch3_length_timer += 1;
                }
            }

            if (self.ch4_control.length_enable) {
                if (self.ch4_length_timer.tick()) {
                    self.ctrl.ch4_on = false;
                    self.ch4_out = 0;
                }
            }
        }

        if (self.div % 4 == 0) {
            // ch1 sweep
            var period = (@as(u11, self.ch1_control.period_high) << 8) | self.ch1_period_low;
            if (self.ch1_sweep.tick(&period)) self.ctrl.ch1_on = false;
            self.ch1_period_low = @truncate(period & 0xff);
            self.ch1_control.period_high = @truncate(period >> 8);
        }

        if (self.div % 8 == 0) {
            // envelope
            self.ch1_envelope.tick();
            self.ch2_envelope.tick();
            self.ch4_envelope.tick();
        }
    }

    fn mixer(self: *APU) void {
        var ch1_left_out: f64 = 0;
        var ch1_right_out: f64 = 0;
        var ch2_left_out: f64 = 0;
        var ch2_right_out: f64 = 0;
        var ch3_left_out: f64 = 0;
        var ch3_right_out: f64 = 0;
        var ch4_left_out: f64 = 0;
        var ch4_right_out: f64 = 0;

        if (self.ctrl.ch1_on) {
            if (self.panning.ch1_left) ch1_left_out = -std.math.lerp(-1.0, 1.0, @as(f64, @floatFromInt(self.ch1_out)) / 15);
            if (self.panning.ch1_right) ch1_right_out = -std.math.lerp(-1.0, 1.0, @as(f64, @floatFromInt(self.ch1_out)) / 15);
        }

        if (self.ctrl.ch2_on) {
            if (self.panning.ch2_left) ch2_left_out = -std.math.lerp(-1.0, 1.0, @as(f64, @floatFromInt(self.ch2_out)) / 15);
            if (self.panning.ch2_right) ch2_right_out = -std.math.lerp(-1.0, 1.0, @as(f64, @floatFromInt(self.ch2_out)) / 15);
        }

        if (self.ctrl.ch3_on) {
            if (self.panning.ch3_left) ch3_left_out = -std.math.lerp(-1.0, 1.0, @as(f64, @floatFromInt(self.ch3_out)) / 15);
            if (self.panning.ch3_right) ch3_right_out = -std.math.lerp(-1.0, 1.0, @as(f64, @floatFromInt(self.ch3_out)) / 15);
        }

        if (self.ctrl.ch4_on) {
            if (self.panning.ch4_left) ch4_left_out = -std.math.lerp(-1.0, 1.0, @as(f64, @floatFromInt(self.ch4_out)) / 15);
            if (self.panning.ch4_right) ch4_right_out = -std.math.lerp(-1.0, 1.0, @as(f64, @floatFromInt(self.ch4_out)) / 15);
        }

        var left_out: f64 = (ch1_left_out + ch2_left_out + ch3_left_out + ch4_left_out) / 4.0;
        var right_out: f64 = (ch1_right_out + ch2_right_out + ch3_right_out + ch4_right_out) / 4.0;
        left_out *= @as(f64, @floatFromInt(@as(u4, self.volume.left) + 1)) / 32.0;
        right_out *= @as(f64, @floatFromInt(@as(u4, self.volume.right) + 1)) / 32.0;
        const left: i32 = @intFromFloat(std.math.lerp(@as(f64, @floatFromInt(std.math.minInt(i16))), @as(f64, @floatFromInt(std.math.maxInt(i16))), (left_out + 1) / 2));
        const right: i32 = @intFromFloat(std.math.lerp(@as(f64, @floatFromInt(std.math.minInt(i16))), @as(f64, @floatFromInt(std.math.maxInt(i16))), (right_out + 1) / 2));

        const left_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.left_buf)));
        if (left != self.previous_left_output) {
            c.blip_add_delta(left_buf, @intCast(self.apu_clock), left - self.previous_left_output);
            self.previous_left_output = left;
        }

        const right_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.right_buf)));
        if (right != self.previous_right_output) {
            c.blip_add_delta(right_buf, @intCast(self.apu_clock), right - self.previous_right_output);
            self.previous_right_output = right;
        }
    }

    pub fn process(self: *APU) void {
        if (self.ctrl.enable) {
            if (self.ctrl.ch1_on) {
                if (self.apu_clock % 4 == 0) self.ch1_period +%= 1;
                if (self.ch1_period == 0) {
                    self.ch1_period = (@as(u11, self.ch1_control.period_high) << 8) | self.ch1_period_low;
                    self.ch1_out = self.ch1_envelope.volume * @as(u4, self.ch1_length_timer.sample());
                }
            }

            if (self.ctrl.ch2_on) {
                if (self.apu_clock % 4 == 0) self.ch2_period +%= 1;
                if (self.ch2_period == 0) {
                    self.ch2_period = (@as(u11, self.ch2_control.period_high) << 8) | self.ch2_period_low;
                    self.ch2_out = self.ch2_envelope.volume * @as(u4, self.ch2_length_timer.sample());
                }
            }

            if (self.ctrl.ch3_on) {
                if (self.apu_clock % 2 == 0) self.ch3_period +%= 1;
                if (self.ch3_period == 0) {
                    self.ch3_period = (@as(u11, self.ch3_control.period_high) << 8) | self.ch3_period_low;
                    self.ch3_out = self.next_wave;
                    var w: u4 = 0;
                    if (self.wave_index % 2 == 0) {
                        w = @intCast(self.wave[self.wave_index / 2] >> 4);
                    } else {
                        w = @intCast(self.wave[self.wave_index / 2] & 0xf);
                    }
                    self.wave_index += 1;
                    if (self.wave_index == 32) self.wave_index = 0;
                    switch (self.ch3_output) {
                        .p100 => {},
                        .p50 => w >>= 1,
                        .p25 => w >>= 2,
                        .mute => w = 0,
                    }
                    self.next_wave = w;
                }
            }

            if (self.ctrl.ch4_on) {
                var divider: usize = @as(usize, self.ch4_frequency.divider) << 4;
                if (divider == 0) divider = 8;
                divider <<= self.ch4_frequency.shift;
                if (self.ch4_frequency.shift < 14 and (self.apu_clock % divider) == 0) {
                    const feedback: u16 = ~((self.ch4_frequency.lfsr & 1) ^ ((self.ch4_frequency.lfsr & 2) >> 1));
                    self.ch4_frequency.lfsr &= 0x7fff;
                    self.ch4_frequency.lfsr |= feedback << 15;
                    if (self.ch4_frequency.lfsr_width == .b7) {
                        self.ch4_frequency.lfsr &= 0xff7f;
                        self.ch4_frequency.lfsr |= feedback << 7;
                    }
                    self.ch4_out = self.ch4_envelope.volume * @as(u4, @as(u1, @intCast(self.ch4_frequency.lfsr & 1)));
                    self.ch4_frequency.lfsr >>= 1;
                }
            }
        }

        self.mixer();
        self.apu_clock +%= 1;
        if (self.apu_clock == 70224) self.apu_clock = 0;
    }

    fn clear(self: *APU) void {
        self.div = 0;
        self.panning = @bitCast(@as(u8, 0));
        self.volume = @bitCast(@as(u8, 0));

        self.ch1_sweep = @bitCast(@as(u11, 0));
        self.ch1_length_timer = @bitCast(@as(u11, 0));
        self.ch1_envelope = @bitCast(@as(u15, 0));
        self.ch1_control = @bitCast(@as(u8, 0));
        self.ch1_period_low = 0;
        self.ch1_period = 0;
        self.ch1_out = 0;

        self.ch2_length_timer = @bitCast(@as(u11, 0));
        self.ch2_envelope = @bitCast(@as(u15, 0));
        self.ch2_control = @bitCast(@as(u8, 0));
        self.ch2_period_low = 0;
        self.ch2_period = 0;
        self.ch2_out = 0;

        self.ch3_enable = false;
        self.ch3_length_timer = 0;
        self.ch3_output = .mute;
        self.ch3_control = @bitCast(@as(u8, 0));
        self.ch3_period_low = 0;
        self.ch3_period = 0;
        self.ch3_out = 0;

        self.ch4_length_timer = @bitCast(@as(u11, 0));
        self.ch4_envelope = @bitCast(@as(u15, 0));
        self.ch4_control = @bitCast(@as(u8, 0));
        self.ch4_frequency = @bitCast(@as(u24, 0));
        self.ch4_out = 0;

        @memset(&self.wave, 0);
    }

    pub fn reset(self: *APU) void {
        const left_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.left_buf)));
        const right_buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.right_buf)));
        c.blip_clear(left_buf);
        c.blip_clear(right_buf);

        self.apu_clock = 0;
        self.previous_left_output = 0;
        self.previous_right_output = 0;

        self.div = 0;
        self.ctrl = @bitCast(@as(u8, 0xf1));
        self.panning = @bitCast(@as(u8, 0xf3));
        self.volume = @bitCast(@as(u8, 0x77));

        self.ch1_sweep = @bitCast(@as(u11, 0x480));
        self.ch1_length_timer = @bitCast(@as(u11, 0xbf));
        self.ch1_envelope = @bitCast(@as(u15, 0x7bf3));
        self.ch1_control = @bitCast(@as(u8, 0xbf));
        self.ch1_period_low = 0xff;
        self.ch1_period = 0x7ff;
        self.ch1_out = 0;

        self.ch2_length_timer = @bitCast(@as(u11, 0x3f));
        self.ch2_envelope = @bitCast(@as(u15, 0));
        self.ch2_control = @bitCast(@as(u8, 0xbf));
        self.ch2_period_low = 0xff;
        self.ch2_period = 0x7ff;
        self.ch2_out = 0;

        self.ch3_enable = false;
        self.ch3_length_timer = 0xff;
        self.ch3_output = .mute;
        self.ch3_control = @bitCast(@as(u8, 0xbf));
        self.ch3_period_low = 0xff;
        self.ch3_period = 0x7ff;
        self.ch3_out = 0;

        self.ch4_length_timer = @bitCast(@as(u11, 0x3f));
        self.ch4_envelope = @bitCast(@as(u15, 0));
        self.ch4_control = @bitCast(@as(u8, 0xbf));
        self.ch4_frequency = @bitCast(@as(u24, 0));
        self.ch4_out = 0;

        self.wave_index = 1;
        self.next_wave = 0;
        @memset(&self.wave, 0);
    }

    pub fn memory(self: *@This()) Memory(u16, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinitMemory,
            },
        };
    }

    pub fn serialize(self: *const APU, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "wave");
        c.mpack_start_bin(pack, @intCast(self.wave.len));
        c.mpack_write_bytes(pack, &self.wave, self.wave.len);
        c.mpack_finish_bin(pack);

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

        c.mpack_write_cstr(pack, "apu_clock");
        c.mpack_write_u32(pack, @truncate(self.apu_clock));
        c.mpack_write_cstr(pack, "previous_left_output");
        c.mpack_write_i32(pack, self.previous_left_output);
        c.mpack_write_cstr(pack, "previous_right_output");
        c.mpack_write_i32(pack, self.previous_right_output);
        c.mpack_write_cstr(pack, "div");
        c.mpack_write_u8(pack, self.div);
        c.mpack_write_cstr(pack, "ctrl");
        c.mpack_write_u8(pack, @bitCast(self.ctrl));
        c.mpack_write_cstr(pack, "panning");
        c.mpack_write_u8(pack, @bitCast(self.panning));
        c.mpack_write_cstr(pack, "volume");
        c.mpack_write_u8(pack, @bitCast(self.volume));
        c.mpack_write_cstr(pack, "ch1_sweep");
        c.mpack_write_u16(pack, @as(u11, @bitCast(self.ch1_sweep)));
        c.mpack_write_cstr(pack, "ch1_length_timer");
        c.mpack_write_u16(pack, @as(u11, @bitCast(self.ch1_length_timer)));
        c.mpack_write_cstr(pack, "ch1_envelope");
        c.mpack_write_u16(pack, @as(u15, @bitCast(self.ch1_envelope)));
        c.mpack_write_cstr(pack, "ch1_control");
        c.mpack_write_u8(pack, @bitCast(self.ch1_control));
        c.mpack_write_cstr(pack, "ch1_period_low");
        c.mpack_write_u8(pack, self.ch1_period_low);
        c.mpack_write_cstr(pack, "ch1_period");
        c.mpack_write_u16(pack, self.ch1_period);
        c.mpack_write_cstr(pack, "ch1_out");
        c.mpack_write_u8(pack, self.ch1_out);
        c.mpack_write_cstr(pack, "ch2_length_timer");
        c.mpack_write_u16(pack, @as(u11, @bitCast(self.ch2_length_timer)));
        c.mpack_write_cstr(pack, "ch2_envelope");
        c.mpack_write_u16(pack, @as(u15, @bitCast(self.ch2_envelope)));
        c.mpack_write_cstr(pack, "ch2_control");
        c.mpack_write_u8(pack, @bitCast(self.ch2_control));
        c.mpack_write_cstr(pack, "ch2_period_low");
        c.mpack_write_u8(pack, self.ch2_period_low);
        c.mpack_write_cstr(pack, "ch2_period");
        c.mpack_write_u16(pack, self.ch2_period);
        c.mpack_write_cstr(pack, "ch2_out");
        c.mpack_write_u8(pack, self.ch2_out);
        c.mpack_write_cstr(pack, "ch3_enable");
        c.mpack_write_bool(pack, self.ch3_enable);
        c.mpack_write_cstr(pack, "ch3_length_timer");
        c.mpack_write_u8(pack, self.ch3_length_timer);
        c.mpack_write_cstr(pack, "ch3_output");
        c.mpack_write_u8(pack, @intFromEnum(self.ch3_output));
        c.mpack_write_cstr(pack, "ch3_control");
        c.mpack_write_u8(pack, @bitCast(self.ch3_control));
        c.mpack_write_cstr(pack, "ch3_period_low");
        c.mpack_write_u8(pack, self.ch3_period_low);
        c.mpack_write_cstr(pack, "ch3_period");
        c.mpack_write_u16(pack, self.ch3_period);
        c.mpack_write_cstr(pack, "ch3_out");
        c.mpack_write_u8(pack, self.ch3_out);
        c.mpack_write_cstr(pack, "wave_index");
        c.mpack_write_u32(pack, @truncate(self.wave_index));
        c.mpack_write_cstr(pack, "next_wave");
        c.mpack_write_u8(pack, self.next_wave);
        c.mpack_write_cstr(pack, "ch4_length_timer");
        c.mpack_write_u16(pack, @as(u11, @bitCast(self.ch4_length_timer)));
        c.mpack_write_cstr(pack, "ch4_envelope");
        c.mpack_write_u16(pack, @as(u15, @bitCast(self.ch4_envelope)));
        c.mpack_write_cstr(pack, "ch4_control");
        c.mpack_write_u8(pack, @bitCast(self.ch4_control));
        c.mpack_write_cstr(pack, "ch4_frequency");
        c.mpack_write_u32(pack, @as(u24, @bitCast(self.ch4_frequency)));
        c.mpack_write_cstr(pack, "ch4_out");
        c.mpack_write_u8(pack, self.ch4_out);
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *APU, pack: c.mpack_node_t) void {
        @memset(&self.wave, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "wave"), &self.wave, self.wave.len);

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

        self.apu_clock = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "apu_clock"));
        self.previous_left_output = c.mpack_node_i32(c.mpack_node_map_cstr(pack, "previous_left_output"));
        self.previous_right_output = c.mpack_node_i32(c.mpack_node_map_cstr(pack, "previous_right_output"));
        self.div = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "div"));
        self.ctrl = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ctrl")));
        self.panning = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "panning")));
        self.volume = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "volume")));
        self.ch1_sweep = @bitCast(@as(u11, @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "ch1_sweep")))));
        self.ch1_length_timer = @bitCast(@as(u11, @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "ch1_length_timer")))));
        self.ch1_envelope = @bitCast(@as(u15, @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "ch1_envelope")))));
        self.ch1_control = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch1_control")));
        self.ch1_period_low = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch1_period_low"));
        self.ch1_period = @bitCast(@as(u11, @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "ch1_period")))));
        self.ch1_out = @truncate(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch1_out")));
        self.ch2_length_timer = @bitCast(@as(u11, @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "ch2_length_timer")))));
        self.ch2_envelope = @bitCast(@as(u15, @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "ch2_envelope")))));
        self.ch2_control = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch2_control")));
        self.ch2_period_low = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch2_period_low"));
        self.ch2_period = @bitCast(@as(u11, @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "ch2_period")))));
        self.ch2_out = @truncate(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch2_out")));
        self.ch3_enable = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "ch3_enable"));
        self.ch3_length_timer = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch3_length_timer")));
        self.ch3_output = @enumFromInt(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch3_output")));
        self.ch3_control = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch3_control")));
        self.ch3_period_low = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch3_period_low"));
        self.ch3_period = @bitCast(@as(u11, @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "ch3_period")))));
        self.ch3_out = @truncate(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch3_out")));
        self.wave_index = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "wave_index"));
        self.next_wave = @truncate(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "next_wave")));
        self.ch4_length_timer = @bitCast(@as(u11, @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "ch4_length_timer")))));
        self.ch4_envelope = @bitCast(@as(u15, @truncate(c.mpack_node_u16(c.mpack_node_map_cstr(pack, "ch4_envelope")))));
        self.ch4_control = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch4_control")));
        self.ch4_frequency = @bitCast(@as(u24, @truncate(c.mpack_node_u32(c.mpack_node_map_cstr(pack, "ch4_frequency")))));
        self.ch4_out = @truncate(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ch4_out")));
    }
};
