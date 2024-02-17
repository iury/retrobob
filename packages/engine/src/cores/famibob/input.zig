const std = @import("std");
const c = @import("../../c.zig");
const Memory = @import("../../memory.zig").Memory;

pub const Input = struct {
    allocator: std.mem.Allocator,
    latch1: u8 = 0,
    latch2: u8 = 0,
    strobe: bool = false,

    /// poll controllers and store them in latches
    fn poll(self: *Input) void {
        // if it has at least 1 gamepad then:
        // player1 = gamepad1
        // player2 = gamepad2 if possible or else keyboard
        // otherwise:
        // player1 = keyboard
        // player2 = disconnected

        if (c.IsGamepadAvailable(0)) {
            self.latch1 = self.pollFromGamepad(0);
            if (c.IsGamepadAvailable(1)) {
                self.latch2 = self.pollFromGamepad(1);
            } else {
                self.latch2 = self.pollFromKeyboard();
            }
        } else {
            self.latch1 = self.pollFromKeyboard();
            self.latch2 = 0;
        }
    }

    /// returns a bit representation of the keyboard
    fn pollFromKeyboard(self: *Input) u8 {
        _ = self;
        const a = c.IsKeyDown(c.KEY_X) or c.IsKeyDown(c.KEY_S);
        const b = c.IsKeyDown(c.KEY_Z) or c.IsKeyDown(c.KEY_A);
        const start = c.IsKeyDown(c.KEY_W) or c.IsKeyDown(c.KEY_ENTER);
        const select = c.IsKeyDown(c.KEY_Q);
        const down = c.IsKeyDown(c.KEY_DOWN);
        const right = c.IsKeyDown(c.KEY_RIGHT);
        var up = c.IsKeyDown(c.KEY_UP);
        var left = c.IsKeyDown(c.KEY_LEFT);
        var bitset = std.StaticBitSet(8).initEmpty();

        // clear impossible positions
        if (up and down) up = false;
        if (left and right) left = false;

        if (a) bitset.set(0);
        if (b) bitset.set(1);
        if (select) bitset.set(2);
        if (start) bitset.set(3);
        if (up) bitset.set(4);
        if (down) bitset.set(5);
        if (left) bitset.set(6);
        if (right) bitset.set(7);
        return bitset.mask;
    }

    /// returns a bit representation of the gamepad
    fn pollFromGamepad(self: *Input, gamepad: u8) u8 {
        _ = self;
        const a = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_RIGHT_FACE_LEFT) or c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_RIGHT_FACE_RIGHT);
        const b = c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_RIGHT_FACE_UP) or c.IsGamepadButtonDown(gamepad, c.GAMEPAD_BUTTON_RIGHT_FACE_DOWN);
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

        var bitset = std.StaticBitSet(8).initEmpty();
        if (a) bitset.set(0);
        if (b) bitset.set(1);
        if (select) bitset.set(2);
        if (start) bitset.set(3);
        if (up) bitset.set(4);
        if (down) bitset.set(5);
        if (left) bitset.set(6);
        if (right) bitset.set(7);
        return bitset.mask;
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.strobe) self.poll();
        // 0x4016 = controller 1, 0x4017 = controller 2
        if (address == 0x4016) {
            const v = self.latch1 & 1;
            self.latch1 >>= 1;
            return v;
        } else {
            const v = self.latch2 & 1;
            self.latch2 >>= 1;
            return v;
        }
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        _ = address;
        self.strobe = (value & 1) > 0;
        if (self.strobe) self.poll();
    }

    pub fn init(allocator: std.mem.Allocator) !*Input {
        const instance = try allocator.create(Input);
        instance.* = .{
            .allocator = allocator,
        };
        return instance;
    }

    pub fn deinit(self: *Input) void {
        self.allocator.destroy(self);
    }

    fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
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
};
