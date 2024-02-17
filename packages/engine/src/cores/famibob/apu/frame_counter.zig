const APU = @import("apu.zig").APU;

pub const FrameCounter = struct {
    pub const FrameType = enum { none, quarter_frame, half_frame };
    pub const step_cycles_ntsc: []const [6]i32 = &[_][6]i32{ .{ 7457, 14913, 22371, 29828, 29829, 29830 }, .{ 7457, 14913, 22371, 29829, 37281, 37282 } };
    pub const step_cycles_pal: []const [6]i32 = &[_][6]i32{ .{ 8313, 16627, 24939, 33252, 33253, 33254 }, .{ 8313, 16627, 24939, 33253, 41565, 41566 } };

    const frame_type: []const [6]FrameType = &[_][6]FrameType{
        .{ .quarter_frame, .half_frame, .quarter_frame, .none, .half_frame, .none }, //
        .{ .quarter_frame, .half_frame, .quarter_frame, .none, .half_frame, .none },
    };

    apu: *APU = undefined,

    irq_requested: bool = false,
    step_cycles: []const [6]i32 = step_cycles_ntsc,
    previous_cycle: i32 = 0,
    current_step: u32 = 0,
    step_mode: u32 = 0,
    inhibit_irq: bool = false,
    block_tick: u8 = 0,
    new_value: i16 = 0,
    write_delay_counter: i8 = 0,

    pub fn needsToRun(self: *FrameCounter, cycles: u32) bool {
        return self.new_value >= 0 or self.block_tick > 0 or (self.previous_cycle + @as(i32, @intCast(cycles)) >= self.step_cycles[self.step_mode][self.current_step] - 1);
    }

    pub fn run(self: *FrameCounter, cycles_to_run: *i32) u32 {
        var cycles_ran: u32 = 0;

        if (self.previous_cycle + cycles_to_run.* >= self.step_cycles[self.step_mode][self.current_step]) {
            if (!self.inhibit_irq and self.step_mode == 0 and self.current_step >= 3) {
                self.irq_requested = true;
            }

            const frame: FrameType = frame_type[self.step_mode][self.current_step];
            if (frame != .none and self.block_tick == 0) {
                APU.frameCounterTick(self.apu, frame);
                self.block_tick = 2;
            }

            if (self.step_cycles[self.step_mode][self.current_step] < self.previous_cycle) {
                cycles_ran = 0;
            } else {
                cycles_ran = @intCast(self.step_cycles[self.step_mode][self.current_step] - self.previous_cycle);
            }

            cycles_to_run.* -= @intCast(cycles_ran);

            self.current_step += 1;
            if (self.current_step == 6) {
                self.current_step = 0;
                self.previous_cycle = 0;
            } else {
                self.previous_cycle += @intCast(cycles_ran);
            }
        } else {
            cycles_ran = @intCast(cycles_to_run.*);
            cycles_to_run.* = 0;
            self.previous_cycle += @intCast(cycles_ran);
        }

        if (self.new_value >= 0) {
            self.write_delay_counter -= 1;
            if (self.write_delay_counter == 0) {
                self.step_mode = if ((self.new_value & 0x80) == 0x80) 1 else 0;

                self.write_delay_counter = -1;
                self.current_step = 0;
                self.previous_cycle = 0;
                self.new_value = -1;

                if (self.step_mode == 1 and self.block_tick == 0) {
                    self.apu.frameCounterTick(.half_frame);
                    self.block_tick = 2;
                }
            }
        }

        if (self.block_tick > 0) {
            self.block_tick -= 1;
        }

        return cycles_ran;
    }

    pub fn reset(self: *FrameCounter) void {
        self.irq_requested = false;
        self.previous_cycle = 0;
        self.step_mode = 0;
        self.current_step = 0;
        self.new_value = if (self.step_mode == 1) 0x80 else 0;
        self.write_delay_counter = 3;
        self.inhibit_irq = false;
        self.block_tick = 0;
    }

    pub fn jsonStringify(self: *const FrameCounter, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("irq_requested");
        try jw.write(self.irq_requested);
        try jw.objectField("previous_cycle");
        try jw.write(self.previous_cycle);
        try jw.objectField("current_step");
        try jw.write(self.current_step);
        try jw.objectField("step_mode");
        try jw.write(self.step_mode);
        try jw.objectField("inhibit_irq");
        try jw.write(self.inhibit_irq);
        try jw.objectField("block_tick");
        try jw.write(self.block_tick);
        try jw.objectField("new_value");
        try jw.write(self.new_value);
        try jw.objectField("write_delay_counter");
        try jw.write(self.write_delay_counter);
        try jw.endObject();
    }
};
