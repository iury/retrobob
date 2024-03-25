const std = @import("std");
const Memory = @import("../../memory.zig").Memory;
const IO = @import("io.zig").IO;
const c = @import("../../c.zig");

pub const Input = struct {
    allocator: std.mem.Allocator,
    bus: Memory(u24, u8),

    strobe: bool = false,
    latch1: std.fifo.LinearFifo(u1, .{ .Static = 16 }),
    latch2: std.fifo.LinearFifo(u1, .{ .Static = 16 }),
    joy1l: u8 = 0,
    joy1h: u8 = 0,
    joy2l: u8 = 0,
    joy2h: u8 = 0,

    pub fn init(allocator: std.mem.Allocator, bus: Memory(u24, u8)) !*Input {
        const instance = try allocator.create(Input);
        instance.* = .{
            .allocator = allocator,
            .bus = bus,
            .latch1 = std.fifo.LinearFifo(u1, .{ .Static = 16 }).init(),
            .latch2 = std.fifo.LinearFifo(u1, .{ .Static = 16 }).init(),
        };
        return instance;
    }

    pub fn deinit(self: *Input) void {
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn poll(self: *Input) !void {
        // if it has at least 1 gamepad then:
        // player1 = gamepad1
        // player2 = gamepad2 if possible or else keyboard
        // otherwise:
        // player1 = keyboard
        // player2 = disconnected

        var joy1: u16 = 0;
        var joy2: ?u16 = null;

        if (c.IsGamepadAvailable(0)) {
            joy1 = pollFromGamepad(0);
            if (c.IsGamepadAvailable(1)) {
                joy2 = pollFromGamepad(1);
            } else {
                joy2 = pollFromKeyboard();
            }
        } else {
            joy1 = pollFromKeyboard();
        }

        self.latch1.discard(self.latch1.count);
        self.latch2.discard(self.latch2.count);

        self.joy1h = @intCast(joy1 >> 8);
        self.joy1l = @intCast(joy1 & 0xff);
        for (0..16) |_| {
            try self.latch1.writeItem(@as(u1, if ((joy1 & 0x8000) > 0) 1 else 0));
            joy1 <<= 1;
        }

        if (joy2) |_| {
            var j2 = joy2.?;
            self.joy2h = @intCast(j2 >> 8);
            self.joy2l = @intCast(j2 & 0xff);
            for (0..16) |_| {
                try self.latch2.writeItem(@as(u1, if ((j2 & 0x8000) > 0) 1 else 0));
                j2 <<= 1;
            }
        }
    }

    fn pollFromKeyboard() u16 {
        const a = c.IsKeyDown(c.KEY_X);
        const b = c.IsKeyDown(c.KEY_Z);
        const x = c.IsKeyDown(c.KEY_S);
        const y = c.IsKeyDown(c.KEY_A);
        const l = c.IsKeyDown(c.KEY_D);
        const r = c.IsKeyDown(c.KEY_C);
        const start = c.IsKeyDown(c.KEY_W) or c.IsKeyDown(c.KEY_ENTER);
        const select = c.IsKeyDown(c.KEY_Q);
        const down = c.IsKeyDown(c.KEY_DOWN);
        const right = c.IsKeyDown(c.KEY_RIGHT);
        var up = c.IsKeyDown(c.KEY_UP);
        var left = c.IsKeyDown(c.KEY_LEFT);

        // clear impossible positions
        if (up and down) up = false;
        if (left and right) left = false;

        return @as(u16, if (b) 0x8000 else 0) |
            @as(u16, if (y) 0x4000 else 0) |
            @as(u16, if (select) 0x2000 else 0) |
            @as(u16, if (start) 0x1000 else 0) |
            @as(u16, if (up) 0x0800 else 0) |
            @as(u16, if (down) 0x0400 else 0) |
            @as(u16, if (left) 0x0200 else 0) |
            @as(u16, if (right) 0x0100 else 0) |
            @as(u16, if (a) 0x0080 else 0) |
            @as(u16, if (x) 0x0040 else 0) |
            @as(u16, if (l) 0x0020 else 0) |
            @as(u16, if (r) 0x0010 else 0) |
            0b0000; // signature
    }

    fn pollFromGamepad(gamepad: u8) u16 {
        const a = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_RIGHT_FACE_RIGHT);
        const b = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_RIGHT_FACE_DOWN);
        const x = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_RIGHT_FACE_UP);
        const y = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_RIGHT_FACE_LEFT);
        const l = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_LEFT_TRIGGER_1);
        const r = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_RIGHT_TRIGGER_1);
        const select = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_MIDDLE_LEFT);
        const start = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_MIDDLE) or c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_MIDDLE_RIGHT);
        var up = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_LEFT_FACE_UP);
        var down = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_LEFT_FACE_DOWN);
        var left = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_LEFT_FACE_LEFT);
        var right = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_LEFT_FACE_RIGHT);
        if (c.GetGamepadAxisCount(gamepad) > 0) {
            up = up or c.GetGamepadAxisMovement(gamepad, c.GAMEPAD_AXIS_LEFT_Y) < -0.3;
            down = down or c.GetGamepadAxisMovement(gamepad, c.GAMEPAD_AXIS_LEFT_Y) > 0.3;
            left = left or c.GetGamepadAxisMovement(gamepad, c.GAMEPAD_AXIS_LEFT_X) < -0.3;
            right = right or c.GetGamepadAxisMovement(gamepad, c.GAMEPAD_AXIS_LEFT_X) > 0.3;
        }

        // clear impossible positions
        if (up and down) up = false;
        if (left and right) left = false;

        return @as(u16, if (b) 0x8000 else 0) |
            @as(u16, if (y) 0x4000 else 0) |
            @as(u16, if (select) 0x2000 else 0) |
            @as(u16, if (start) 0x1000 else 0) |
            @as(u16, if (up) 0x0800 else 0) |
            @as(u16, if (down) 0x0400 else 0) |
            @as(u16, if (left) 0x0200 else 0) |
            @as(u16, if (right) 0x0100 else 0) |
            @as(u16, if (a) 0x0080 else 0) |
            @as(u16, if (x) 0x0040 else 0) |
            @as(u16, if (l) 0x0020 else 0) |
            @as(u16, if (r) 0x0010 else 0) |
            0b0000; // signature
    }

    pub fn read(ctx: *anyopaque, address: u24) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.strobe) self.poll() catch unreachable;
        return switch (address) {
            @intFromEnum(IO.JOYSER0) => self.latch1.readItem() orelse 1,
            @intFromEnum(IO.JOYSER1) => 0x1c | @as(u8, self.latch2.readItem() orelse if (c.IsGamepadAvailable(0)) 1 else 0),
            @intFromEnum(IO.JOY1L) => self.joy1l,
            @intFromEnum(IO.JOY1H) => self.joy1h,
            @intFromEnum(IO.JOY2L) => self.joy2l,
            @intFromEnum(IO.JOY2H) => self.joy2h,
            @intFromEnum(IO.JOY3L) => 0,
            @intFromEnum(IO.JOY3H) => 0,
            @intFromEnum(IO.JOY4L) => 0,
            @intFromEnum(IO.JOY4H) => 0,
            else => 0,
        };
    }

    pub fn write(ctx: *anyopaque, address: u24, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        switch (address) {
            @intFromEnum(IO.JOYSER0) => {
                self.strobe = (value & 1) > 0;
                if (self.strobe) self.poll() catch unreachable;
            },
            else => {},
        }
    }

    pub fn memory(self: *@This()) Memory(u24, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinitMemory,
            },
        };
    }
};
