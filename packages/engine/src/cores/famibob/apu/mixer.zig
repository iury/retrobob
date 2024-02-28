const std = @import("std");
const c = @import("../../../c.zig");
const APU = @import("apu.zig");
const Region = @import("../../core.zig").Region;
const AudioChannel = APU.AudioChannel;

const blip_t = extern struct {
    factor: usize,
    offset: usize,
    avail: c_int,
    size: c_int,
    integrator: c_int,
};

pub const Mixer = struct {
    pub const cycle_length: u32 = 10000;
    pub const max_sample_rate: u32 = 48000;
    pub const max_samples_per_frame = max_sample_rate / 50;

    allocator: std.mem.Allocator,
    region: Region,

    blip_buf: *blip_t,
    timestamps: std.AutoArrayHashMap(u32, void),
    channel_output: [][cycle_length]i16,
    current_output: [5]i16 = [_]i16{0} ** 5,

    sample_rate: u32 = max_sample_rate,
    previous_output: i16 = 0,
    clock_rate: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, region: Region) !*Mixer {
        const instance = try allocator.create(Mixer);
        const buf: *blip_t = @as(*blip_t, @ptrCast(@alignCast(c.blip_new(max_samples_per_frame) orelse return error.BlipError)));
        const stamps = std.AutoArrayHashMap(u32, void).init(allocator);
        instance.* = .{
            .allocator = allocator,
            .region = region,
            .timestamps = stamps,
            .blip_buf = buf,
            .channel_output = try allocator.alloc([cycle_length]i16, 5),
        };
        return instance;
    }

    pub fn deinit(self: *Mixer) void {
        self.timestamps.deinit();
        self.allocator.free(self.channel_output);
        const buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.blip_buf)));
        c.blip_delete(buf);
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
        const buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.blip_buf)));
        return @intCast(c.blip_read_samples(buf, buffer.ptr, @intCast(buffer.len), 0));
    }

    pub fn updateRates(self: *Mixer, force: bool) void {
        const clock_rate: u32 = switch (self.region) {
            .ntsc => 1789773,
            .pal => 1662607,
        };

        if (force or self.clock_rate != clock_rate) {
            self.clock_rate = clock_rate;
            const buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.blip_buf)));
            c.blip_set_rates(buf, @floatFromInt(self.clock_rate), @floatFromInt(self.sample_rate));
        }
    }

    pub fn getChannelOutput(self: *Mixer, channel: AudioChannel) f64 {
        return @floatFromInt(self.current_output[@intFromEnum(channel)]);
    }

    pub fn getOutputVolume(self: *Mixer) i16 {
        const square_output: f64 = self.getChannelOutput(.square1) + self.getChannelOutput(.square2);
        const tnd_output: f64 = self.getChannelOutput(.dmc) + 2.7516713261 * self.getChannelOutput(.triangle) + 1.8493587125 * self.getChannelOutput(.noise);

        const square_volume: f64 = @trunc((95.88 * 32768.0) / (8128.0 / square_output + 100.0));
        const tnd_volume: f64 = @trunc((159.79 * 32768.0) / (22638.0 / tnd_output + 100.0));

        return @intFromFloat((square_volume + tnd_volume) * 0.6);
    }

    const C = struct {
        keys: []u32,
        pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
            return ctx.keys[a_index] < ctx.keys[b_index];
        }
    };

    pub fn endFrame(self: *Mixer, time: u32) void {
        const buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.blip_buf)));
        self.timestamps.sort(C{ .keys = self.timestamps.keys() });

        var iter = self.timestamps.iterator();
        while (iter.next()) |item| {
            const stamp = item.key_ptr.*;

            for (0..5) |i| {
                self.current_output[i] += self.channel_output[i][stamp];
            }

            const output: i16 = self.getOutputVolume();
            c.blip_add_delta(buf, stamp, output - self.previous_output);
            self.previous_output = output;
        }

        c.blip_end_frame(buf, time);
        self.timestamps.clearRetainingCapacity();
        for (0..5) |i| {
            @memset(self.channel_output[i][0..], 0);
        }
    }

    pub fn reset(self: *Mixer) void {
        self.previous_output = 0;
        const buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.blip_buf)));
        c.blip_clear(buf);
        self.timestamps.clearRetainingCapacity();
        @memset(self.current_output[0..], 0);
        for (0..5) |i| {
            @memset(self.channel_output[i][0..], 0);
        }
        self.updateRates(true);
    }

    pub fn jsonStringify(self: *const Mixer, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("region");
        try jw.write(self.region);
        try jw.objectField("blip_buf");
        try jw.write(self.blip_buf);
        try jw.objectField("sample_rate");
        try jw.write(self.sample_rate);
        try jw.objectField("previous_output");
        try jw.write(self.previous_output);
        try jw.objectField("clock_rate");
        try jw.write(self.clock_rate);
        try jw.objectField("current_output");
        try jw.write(self.current_output);

        try jw.objectField("channel_output");
        try jw.beginArray();
        for (0..self.channel_output.len) |i| {
            const arr = self.channel_output[i][0..];
            var pos = arr.len;
            while (pos > 0) : (pos -= 1) {
                if (arr[pos - 1] != 0) break;
            }
            try jw.write(arr[0..pos]);
        }
        try jw.endArray();

        try jw.objectField("timestamps");
        var stamps = std.ArrayList(u32).init(std.heap.c_allocator);
        defer stamps.deinit();
        var iter = self.timestamps.iterator();
        while (iter.next()) |item| {
            const stamp = item.key_ptr.*;
            stamps.append(stamp) catch unreachable;
        }
        try jw.write(stamps.items);

        try jw.endObject();
    }

    pub fn jsonParse(self: *Mixer, value: std.json.Value) void {
        self.region = std.meta.stringToEnum(Region, value.object.get("region").?.string).?;
        self.sample_rate = @intCast(value.object.get("sample_rate").?.integer);
        self.previous_output = @intCast(value.object.get("previous_output").?.integer);
        self.clock_rate = @intCast(value.object.get("clock_rate").?.integer);

        const buf = @as(*c.struct_blip_t, @ptrCast(@alignCast(self.blip_buf)));
        c.blip_clear(buf);
        const blip = value.object.get("blip_buf").?.object;
        self.blip_buf.factor = @intCast(blip.get("factor").?.integer);
        self.blip_buf.offset = @intCast(blip.get("offset").?.integer);
        self.blip_buf.avail = @intCast(blip.get("avail").?.integer);
        self.blip_buf.size = @intCast(blip.get("size").?.integer);
        self.blip_buf.integrator = @intCast(blip.get("integrator").?.integer);

        self.timestamps.clearRetainingCapacity();
        for (value.object.get("timestamps").?.array.items) |v| {
            self.timestamps.put(@intCast(v.integer), {}) catch unreachable;
        }

        @memset(self.current_output[0..], 0);
        for (value.object.get("current_output").?.array.items, 0..) |v, i| {
            self.current_output[i] = @intCast(v.integer);
        }

        for (0..5) |i| {
            @memset(self.channel_output[i][0..], 0);
            for (value.object.get("channel_output").?.array.items[i].array.items, 0..) |v, j| {
                self.channel_output[i][j] = @intCast(v.integer);
            }
        }
    }
};
