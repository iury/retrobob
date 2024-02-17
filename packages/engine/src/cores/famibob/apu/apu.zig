const std = @import("std");
const Region = @import("../../core.zig").Region;
const Memory = @import("../../../memory.zig").Memory;

pub const LengthCounter = @import("length_counter.zig").LengthCounter;
pub const FrameCounter = @import("frame_counter.zig").FrameCounter;
pub const AudioChannel = @import("audio_channel.zig").AudioChannel;
pub const Envelope = @import("envelope.zig").Envelope;
pub const Triangle = @import("triangle.zig").Triangle;
pub const Square = @import("square.zig").Square;
pub const Noise = @import("noise.zig").Noise;
pub const Timer = @import("timer.zig").Timer;
pub const Mixer = @import("mixer.zig").Mixer;
pub const DMC = @import("dmc.zig").DMC;

pub const APU = struct {
    allocator: std.mem.Allocator,
    enabled: bool = true,
    mixer: *Mixer,
    region: Region,

    current_cycle: u32 = 0,
    previous_cycle: u32 = 0,
    needs_to_run: bool = false,

    frame_counter: FrameCounter = .{},
    square1: Square(.one) = .{},
    square2: Square(.two) = .{},
    triangle: Triangle = .{},
    noise: Noise = .{},
    dmc: DMC = .{},

    pub fn init(allocator: std.mem.Allocator, region: Region, mixer: *Mixer) !*APU {
        const instance = try allocator.create(APU);

        instance.* = .{
            .allocator = allocator,
            .region = region,
            .mixer = mixer,
        };

        instance.frame_counter.apu = instance;
        instance.square1.timer.mixer = mixer;
        instance.square2.timer.mixer = mixer;
        instance.triangle.timer.mixer = mixer;
        instance.noise.timer.mixer = mixer;
        instance.dmc.timer.mixer = mixer;

        instance.reset();
        return instance;
    }

    pub fn deinit(self: *APU) void {
        self.allocator.destroy(self);
    }

    fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        _ = address;

        self.run();

        const v = 0 //
        | @as(u8, if (self.square1.getStatus()) 0x01 else 0) //
        | @as(u8, if (self.square2.getStatus()) 0x02 else 0) //
        | @as(u8, if (self.triangle.getStatus()) 0x04 else 0) //
        | @as(u8, if (self.noise.getStatus()) 0x08 else 0) //
        | @as(u8, if (self.dmc.getStatus()) 0x10 else 0) //
        | @as(u8, if (self.frame_counter.irq_requested) 0x40 else 0) //
        | @as(u8, if (self.dmc.irq_requested) 0x80 else 0);

        self.frame_counter.irq_requested = false;
        return v;
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.run();

        switch (address) {
            0x4000 => {
                self.square1.envelope.initEnvelope(value);
                self.needs_to_run = true;
                self.square1.duty = (value & 0xC0) >> 6;
                if (!self.square1.is_mmc5_square) self.square1.updateOutput();
            },
            0x4001 => {
                self.square1.initSweep(value);
                if (!self.square1.is_mmc5_square) self.square1.updateOutput();
            },
            0x4002 => {
                self.square1.setPeriod((self.square1.real_period & 0x0700) | value);
                if (!self.square1.is_mmc5_square) self.square1.updateOutput();
            },
            0x4003 => {
                self.square1.envelope.length_counter.loadLengthCounter(value >> 3);
                self.needs_to_run = true;
                self.square1.setPeriod((self.square1.real_period & 0xFF) | (@as(u16, value & 0x07) << 8));
                self.square1.duty_pos = 0;
                self.square1.envelope.resetEnvelope();
                if (!self.square1.is_mmc5_square) self.square1.updateOutput();
            },
            0x4004 => {
                self.square2.envelope.initEnvelope(value);
                self.needs_to_run = true;
                self.square2.duty = (value & 0xC0) >> 6;
                if (!self.square2.is_mmc5_square) self.square2.updateOutput();
            },
            0x4005 => {
                self.square2.initSweep(value);
                if (!self.square2.is_mmc5_square) self.square2.updateOutput();
            },
            0x4006 => {
                self.square2.setPeriod((self.square2.real_period & 0x0700) | value);
                if (!self.square2.is_mmc5_square) self.square2.updateOutput();
            },
            0x4007 => {
                self.square2.envelope.length_counter.loadLengthCounter(value >> 3);
                self.needs_to_run = true;
                self.square2.setPeriod((self.square2.real_period & 0xFF) | (@as(u16, value & 0x07) << 8));
                self.square2.duty_pos = 0;
                self.square2.envelope.resetEnvelope();
                if (!self.square2.is_mmc5_square) self.square2.updateOutput();
            },
            0x4008 => {
                self.triangle.linear_control_flag = (value & 0x80) == 0x80;
                self.triangle.linear_counter_reload = value & 0x7F;
                self.triangle.length_counter.initLengthCounter(self.triangle.linear_control_flag);
                self.needs_to_run = true;
            },
            0x400A => {
                self.triangle.timer.period = (self.triangle.timer.period & 0x700) | value;
            },
            0x400B => {
                self.triangle.length_counter.loadLengthCounter(value >> 3);
                self.needs_to_run = true;
                self.triangle.timer.period = (self.triangle.timer.period & 0xFF) | (@as(u16, value & 0x07) << 8);
                self.triangle.linear_reload_flag = true;
            },
            0x400C => {
                self.noise.envelope.initEnvelope(value);
                self.needs_to_run = true;
            },
            0x400E => {
                self.noise.timer.period = self.noise.lookup_table[value & 0x0F] - 1;
                self.noise.mode_flag = (value & 0x80) == 0x80;
            },
            0x400F => {
                self.noise.envelope.length_counter.loadLengthCounter(value >> 3);
                self.needs_to_run = true;
                self.noise.envelope.resetEnvelope();
            },
            0x4010 => {
                self.dmc.irq_enabled = (value & 0x80) == 0x80;
                self.dmc.loop_flag = (value & 0x40) == 0x40;
                self.dmc.timer.period = self.dmc.lookup_table[value & 0x0F] - 1;
                if (!self.dmc.irq_enabled) self.dmc.irq_requested = false;
            },
            0x4011 => {
                const new_value: i8 = @bitCast(value & 0x7f);
                const old_value: i8 = @bitCast(self.dmc.output_level);
                self.dmc.output_level = @bitCast(new_value);

                if (@abs(new_value - old_value) > 50) {
                    // reduce popping sounds
                    self.dmc.output_level = @bitCast(new_value - @divTrunc(new_value - old_value, 2));
                }
            },
            0x4012 => {
                self.dmc.sample_addr = 0xC000 | (@as(u16, value) << 6);
            },
            0x4013 => {
                self.dmc.sample_length = (@as(u16, value) << 4) | 0x0001;
            },
            0x4015 => {
                self.dmc.irq_requested = false;
                self.square1.setEnabled((value & 0x01) > 0);
                self.square2.setEnabled((value & 0x02) > 0);
                self.triangle.setEnabled((value & 0x04) > 0);
                self.noise.setEnabled((value & 0x08) > 0);
                self.dmc.setEnabled((value & 0x10) > 0);
            },
            0x4017 => {
                self.frame_counter.new_value = value;
                self.frame_counter.write_delay_counter = 3;
                self.frame_counter.inhibit_irq = (value & 0x40) == 0x40;
                if (self.frame_counter.inhibit_irq) {
                    self.frame_counter.irq_requested = false;
                }
            },
            else => {},
        }
    }

    pub fn process(self: *APU) void {
        if (self.enabled) {
            self.current_cycle += 1;
            if (self.current_cycle == Mixer.cycle_length - 1) {
                self.endFrame();
            } else if (self.needsToRun(self.current_cycle)) {
                self.run();
            }
        }
    }

    pub fn setRegion(self: *APU, region: Region) void {
        self.region = region;
        self.mixer.setRegion(region);
        self.dmc.lookup_table = if (region == .ntsc) DMC.lookup_table_ntsc else DMC.lookup_table_pal;
        self.noise.lookup_table = if (region == .ntsc) Noise.lookup_table_ntsc else Noise.lookup_table_pal;
        self.run();
        self.frame_counter.step_cycles = if (region == .ntsc) FrameCounter.step_cycles_ntsc else FrameCounter.step_cycles_pal;
    }

    pub fn endFrame(self: *APU) void {
        self.run();
        self.square1.endFrame();
        self.square2.endFrame();
        self.triangle.endFrame();
        self.noise.endFrame();
        self.dmc.endFrame();
        self.mixer.endFrame(self.current_cycle);
        self.mixer.updateRates(false);
        self.current_cycle = 0;
        self.previous_cycle = 0;
    }

    fn needsToRun(self: *APU, cycle: u32) bool {
        if (self.dmc.needsToRun() or self.needs_to_run) {
            self.needs_to_run = false;
            return true;
        } else {
            const cycle_to_run: u32 = cycle - self.previous_cycle;
            return self.frame_counter.needsToRun(cycle_to_run) or self.dmc.irqPending(cycle_to_run);
        }
    }

    fn run(self: *APU) void {
        var cycles_to_run: i32 = @intCast(self.current_cycle - self.previous_cycle);
        while (cycles_to_run > 0) {
            self.previous_cycle += self.frame_counter.run(&cycles_to_run);
            self.square1.reloadLengthCounter();
            self.square2.reloadLengthCounter();
            self.noise.reloadLengthCounter();
            self.triangle.reloadLengthCounter();
            self.square1.run(self.previous_cycle);
            self.square2.run(self.previous_cycle);
            self.noise.run(self.previous_cycle);
            self.triangle.run(self.previous_cycle);
            self.dmc.run(self.previous_cycle);
        }
    }

    pub fn frameCounterTick(self: *APU, frame_type: FrameCounter.FrameType) void {
        self.square1.tickEnvelope();
        self.square2.tickEnvelope();
        self.triangle.tickLinearCounter();
        self.noise.tickEnvelope();
        if (frame_type == .half_frame) {
            self.square1.tickLengthCounter();
            self.square2.tickLengthCounter();
            self.triangle.tickLengthCounter();
            self.noise.tickLengthCounter();
            self.square1.tickSweep();
            self.square2.tickSweep();
        }
    }

    pub fn reset(self: *APU) void {
        self.enabled = true;
        self.current_cycle = 0;
        self.previous_cycle = 0;
        self.needs_to_run = false;
        self.square1.reset();
        self.square2.reset();
        self.triangle.reset();
        self.noise.reset();
        self.dmc.reset();
        self.frame_counter.reset();
        self.mixer.reset();
    }

    pub fn memory(self: *APU) Memory(u16, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinitMemory,
            },
        };
    }

    pub fn jsonStringify(self: *const APU, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("enabled");
        try jw.write(self.enabled);
        try jw.objectField("current_cycle");
        try jw.write(self.current_cycle);
        try jw.objectField("previous_cycle");
        try jw.write(self.previous_cycle);
        try jw.objectField("needs_to_run");
        try jw.write(self.needs_to_run);
        try jw.objectField("frame_counter");
        try jw.write(self.frame_counter);
        try jw.objectField("square1");
        try jw.write(self.square1);
        try jw.objectField("square2");
        try jw.write(self.square2);
        try jw.objectField("triangle");
        try jw.write(self.triangle);
        try jw.objectField("noise");
        try jw.write(self.noise);
        try jw.objectField("dmc");
        try jw.write(self.dmc);
        try jw.endObject();
    }
};
