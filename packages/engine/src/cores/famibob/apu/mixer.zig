const std = @import("std");
const c = @import("../../../c.zig");
const APU = @import("apu.zig");
const Region = @import("../../core.zig").Region;
const AudioChannel = APU.AudioChannel;

pub const Mixer = struct {
    pub const cycle_length: u32 = 10000;
    pub const max_sample_rate: u32 = 48000;
    pub const max_samples_per_frame = max_sample_rate / 50;

    allocator: std.mem.Allocator,
    region: Region,

    blip_buf: *c.blip_t,
    timestamps: std.AutoArrayHashMap(u32, void),

    channel_output: [11][cycle_length]i16 = [_][cycle_length]i16{[_]i16{0} ** cycle_length} ** 11,
    current_output: [11]i16 = [_]i16{0} ** 11,
    sample_rate: u32 = max_sample_rate,
    previous_output: i16 = 0,
    clock_rate: u32 = 0,
    sample_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, region: Region) !*Mixer {
        const instance = try allocator.create(Mixer);
        const buf = c.blip_new(max_samples_per_frame) orelse return error.BlipError;
        const stamps = std.AutoArrayHashMap(u32, void).init(allocator);
        instance.* = .{
            .allocator = allocator,
            .region = region,
            .timestamps = stamps,
            .blip_buf = buf,
        };
        return instance;
    }

    pub fn deinit(self: *Mixer) void {
        self.timestamps.deinit();
        c.blip_delete(self.blip_buf);
        self.allocator.destroy(self);
    }

    pub fn setRegion(self: *Mixer, region: Region) void {
        self.region = region;
        self.updateRates(true);
    }

    pub fn addDelta(self: *Mixer, channel: AudioChannel, time: u32, delta: i16) void {
        if (delta != 0) {
            self.timestamps.put(time, {}) catch return;
            self.channel_output[@intFromEnum(channel)][time] += delta;
        }
    }

    pub fn fillAudioBuffer(self: *Mixer, buffer: []i16) usize {
        return @intCast(c.blip_read_samples(self.blip_buf, buffer.ptr, @intCast(buffer.len), 0));
    }

    pub fn updateRates(self: *Mixer, force: bool) void {
        const clock_rate: u32 = switch (self.region) {
            .ntsc => 1789773,
            .pal => 1662607,
        };

        if (force or self.clock_rate != clock_rate) {
            self.clock_rate = clock_rate;
            c.blip_set_rates(self.blip_buf, @floatFromInt(self.clock_rate), @floatFromInt(self.sample_rate));
        }
    }

    pub fn getChannelOutput(self: *Mixer, channel: AudioChannel) f64 {
        return @floatFromInt(self.current_output[@intFromEnum(channel)]);
    }

    pub fn getOutputVolume(self: *Mixer) i16 {
        const square_output: f64 = self.getChannelOutput(.square1) + self.getChannelOutput(.square2);
        const tnd_output: f64 = self.getChannelOutput(.dmc) + 2.7516713261 * self.getChannelOutput(.triangle) + 1.8493587125 * self.getChannelOutput(.noise);

        const square_volume: f64 = @trunc((95.88 * 5000.0) / (8128.0 / square_output + 100.0));
        const tnd_volume: f64 = @trunc((159.79 * 5000.0) / (22638.0 / tnd_output + 100.0));

        return @intFromFloat((square_volume + tnd_volume + //
            self.getChannelOutput(.fds) * 20 + //
            self.getChannelOutput(.mmc5) * 43 + //
            self.getChannelOutput(.namco163) * 20 + //
            self.getChannelOutput(.sunsoft5b) * 15 + //
            self.getChannelOutput(.vrc6) * 75 + //
            self.getChannelOutput(.vrc7)) * 4);
    }

    const C = struct {
        keys: []u32,
        pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
            return ctx.keys[a_index] < ctx.keys[b_index];
        }
    };

    pub fn endFrame(self: *Mixer, time: u32) void {
        self.timestamps.sort(C{ .keys = self.timestamps.keys() });

        var iter = self.timestamps.iterator();
        while (iter.next()) |item| {
            const stamp = item.key_ptr.*;

            for (0..11) |i| {
                self.current_output[i] += self.channel_output[i][stamp];
            }

            const output: i16 = self.getOutputVolume();
            c.blip_add_delta(self.blip_buf, stamp, output - self.previous_output);
            self.previous_output = output;
        }

        c.blip_end_frame(self.blip_buf, time);
        self.timestamps.clearRetainingCapacity();
        for (0..11) |i| {
            @memset(self.channel_output[i][0..], 0);
        }
    }

    pub fn reset(self: *Mixer) void {
        self.sample_count = 0;
        self.previous_output = 0;
        c.blip_clear(self.blip_buf);
        self.timestamps.clearRetainingCapacity();
        @memset(self.current_output[0..], 0);
        for (0..11) |i| {
            @memset(self.channel_output[i][0..], 0);
        }
        self.updateRates(true);
    }
};
