const std = @import("std");
const IO = @import("io.zig").IO;
const Memory = @import("../../memory.zig").Memory;
const c = @import("../../c.zig");

const P1 = packed struct {
    a_right: bool,
    b_left: bool,
    select_up: bool,
    start_down: bool,
    dpad: bool,
    button: bool,
    unused: u2,
};

pub const Input = struct {
    allocator: std.mem.Allocator,
    bus: Memory(u16, u8),
    p1: P1,

    pub fn init(allocator: std.mem.Allocator, bus: Memory(u16, u8)) !*Input {
        const instance = try allocator.create(Input);
        instance.* = .{
            .allocator = allocator,
            .bus = bus,
            .p1 = @bitCast(@as(u8, 0xff)),
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

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        _ = address;
        return @bitCast(self.p1);
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        _ = address;
        self.p1.dpad = (value & 0x10) > 0;
        self.p1.button = (value & 0x20) > 0;
    }

    pub fn process(self: *Input) void {
        const old: P1 = self.p1;
        var new: P1 = old;

        new.b_left = true;
        new.a_right = true;
        new.select_up = true;
        new.start_down = true;

        if (!new.dpad) {
            var up = c.IsKeyDown(c.KEY_UP);
            var down = c.IsKeyDown(c.KEY_DOWN);
            var left = c.IsKeyDown(c.KEY_LEFT);
            var right = c.IsKeyDown(c.KEY_RIGHT);
            up = up or c.IsGamepadButtonDown(0, c.GAMEPAD_BUTTON_LEFT_FACE_UP);
            down = down or c.IsGamepadButtonDown(0, c.GAMEPAD_BUTTON_LEFT_FACE_DOWN);
            left = left or c.IsGamepadButtonDown(0, c.GAMEPAD_BUTTON_LEFT_FACE_LEFT);
            right = right or c.IsGamepadButtonDown(0, c.GAMEPAD_BUTTON_LEFT_FACE_RIGHT);
            if (c.GetGamepadAxisCount(0) > 0) {
                up = up or c.GetGamepadAxisMovement(0, c.GAMEPAD_AXIS_LEFT_Y) < -0.3;
                down = down or c.GetGamepadAxisMovement(0, c.GAMEPAD_AXIS_LEFT_Y) > 0.3;
                left = left or c.GetGamepadAxisMovement(0, c.GAMEPAD_AXIS_LEFT_X) < -0.3;
                right = right or c.GetGamepadAxisMovement(0, c.GAMEPAD_AXIS_LEFT_X) > 0.3;
            }

            if (up and down) up = false;
            if (left and right) left = false;

            new.b_left = !left;
            new.a_right = !right;
            new.select_up = !up;
            new.start_down = !down;
        }

        if (!new.button) {
            var a = c.IsKeyDown(c.KEY_X) or c.IsKeyDown(c.KEY_S);
            var b = c.IsKeyDown(c.KEY_Z) or c.IsKeyDown(c.KEY_A);
            var start = c.IsKeyDown(c.KEY_W) or c.IsKeyDown(c.KEY_ENTER);
            var select = c.IsKeyDown(c.KEY_Q);
            a = a or c.IsGamepadButtonDown(0, c.GAMEPAD_BUTTON_RIGHT_FACE_LEFT) or c.IsGamepadButtonDown(0, c.GAMEPAD_BUTTON_RIGHT_FACE_RIGHT);
            b = b or c.IsGamepadButtonDown(0, c.GAMEPAD_BUTTON_RIGHT_FACE_UP) or c.IsGamepadButtonDown(0, c.GAMEPAD_BUTTON_RIGHT_FACE_DOWN);
            select = select or c.IsGamepadButtonDown(0, c.GAMEPAD_BUTTON_MIDDLE_LEFT);
            start = start or c.IsGamepadButtonDown(0, c.GAMEPAD_BUTTON_MIDDLE) or c.IsGamepadButtonDown(0, c.GAMEPAD_BUTTON_MIDDLE_RIGHT);

            new.b_left = !b;
            new.a_right = !a;
            new.select_up = !select;
            new.start_down = !start;
        }

        self.p1 = new;
        if ((old.select_up and !new.select_up) or (old.start_down and !new.start_down) or (old.b_left and !new.b_left) or (old.a_right and !new.a_right)) {
            self.bus.write(@intFromEnum(IO.IF), self.bus.read(@intFromEnum(IO.IF)) | 0x10);
        }
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

    pub fn serialize(self: *const Input, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);
        c.mpack_write_cstr(pack, "p1");
        c.mpack_write_u8(pack, @bitCast(self.p1));
        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *Input, pack: c.mpack_node_t) void {
        self.p1 = @bitCast(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "p1")));
    }
};
