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
    pub const max_sample_rate: u32 = 44100;
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
            .ntsc => 1786830,
            .pal => 1662375,
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

    pub fn serialize(self: *const Mixer, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "blip_buf");
        c.mpack_build_map(pack);
        if (@sizeOf(usize) == 8) {
            c.mpack_write_cstr(pack, "factor");
            c.mpack_write_u64(pack, self.blip_buf.factor);
            c.mpack_write_cstr(pack, "offset");
            c.mpack_write_u64(pack, self.blip_buf.offset);
        } else {
            c.mpack_write_cstr(pack, "factor");
            c.mpack_write_u32(pack, self.blip_buf.factor);
            c.mpack_write_cstr(pack, "offset");
            c.mpack_write_u32(pack, self.blip_buf.offset);
        }
        c.mpack_write_cstr(pack, "avail");
        c.mpack_write_i32(pack, self.blip_buf.avail);
        c.mpack_write_cstr(pack, "size");
        c.mpack_write_i32(pack, self.blip_buf.size);
        c.mpack_write_cstr(pack, "integrator");
        c.mpack_write_i32(pack, self.blip_buf.integrator);
        c.mpack_complete_map(pack);

        c.mpack_write_cstr(pack, "previous_output");
        c.mpack_write_i16(pack, self.previous_output);

        c.mpack_write_cstr(pack, "current_output");
        c.mpack_build_array(pack);
        for (self.current_output) |item| c.mpack_write_i16(pack, item);
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "channel_output");
        c.mpack_build_array(pack);
        for (0..self.channel_output.len) |i| {
            c.mpack_build_array(pack);
            for (self.channel_output[i]) |item| c.mpack_write_i16(pack, item);
            c.mpack_complete_array(pack);
        }
        c.mpack_complete_array(pack);

        c.mpack_write_cstr(pack, "timestamps");
        c.mpack_build_array(pack);
        var stamps = std.ArrayList(u32).init(std.heap.c_allocator);
        defer stamps.deinit();
        var iter = self.timestamps.iterator();
        while (iter.next()) |item| {
            const stamp = item.key_ptr.*;
            stamps.append(stamp) catch unreachable;
        }
        for (stamps.items) |item| c.mpack_write_u32(pack, item);
        c.mpack_complete_array(pack);

        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *Mixer, pack: c.mpack_node_t) void {
        const blip_buf = c.mpack_node_map_cstr(pack, "blip_buf");
        {
            if (@sizeOf(usize) == 8) {
                self.blip_buf.factor = c.mpack_node_u64(c.mpack_node_map_cstr(blip_buf, "factor"));
                self.blip_buf.offset = c.mpack_node_u64(c.mpack_node_map_cstr(blip_buf, "offset"));
            } else {
                self.blip_buf.factor = c.mpack_node_u32(c.mpack_node_map_cstr(blip_buf, "factor"));
                self.blip_buf.offset = c.mpack_node_u32(c.mpack_node_map_cstr(blip_buf, "offset"));
            }
            self.blip_buf.avail = c.mpack_node_i32(c.mpack_node_map_cstr(blip_buf, "avail"));
            self.blip_buf.size = c.mpack_node_i32(c.mpack_node_map_cstr(blip_buf, "size"));
            self.blip_buf.integrator = c.mpack_node_i32(c.mpack_node_map_cstr(blip_buf, "integrator"));
        }

        self.previous_output = c.mpack_node_i16(c.mpack_node_map_cstr(pack, "previous_output"));

        {
            @memset(&self.current_output, 0);
            const current_output = c.mpack_node_map_cstr(pack, "current_output");
            const len = c.mpack_node_array_length(current_output);
            for (0..len) |i| {
                self.current_output[i] = c.mpack_node_i16(c.mpack_node_array_at(current_output, i));
            }
        }

        for (0..5) |i| {
            @memset(&self.channel_output[i], 0);
            const output = c.mpack_node_array_at(c.mpack_node_map_cstr(pack, "channel_output"), i);
            const len = c.mpack_node_array_length(output);
            for (0..len) |j| {
                self.channel_output[i][j] = c.mpack_node_i16(c.mpack_node_array_at(output, j));
            }
        }

        {
            self.timestamps.clearRetainingCapacity();
            const stamps = c.mpack_node_map_cstr(pack, "timestamps");
            const len = c.mpack_node_array_length(stamps);
            for (0..len) |i| {
                self.timestamps.put(c.mpack_node_u32(c.mpack_node_array_at(stamps, i)), {}) catch unreachable;
            }
        }
    }
};
