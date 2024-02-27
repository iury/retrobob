const std = @import("std");
const IO = @import("io.zig").IO;
const Memory = @import("../../memory.zig").Memory;

const TAC = packed struct {
    divider: enum(u2) { m256 = 0, m4, m16, m64 },
    enable: bool,
    unused: u5,
};

const Counter = packed struct {
    tickers: u6,
    div: u8,
};

pub const Timer = struct {
    allocator: std.mem.Allocator,
    tima: u8 = 0,
    tma: u8 = 0,
    overflow: ?bool = null,
    counter: Counter = @bitCast(@as(u14, 0)),
    tac: TAC = @bitCast(@as(u8, 0xf8)),
    bus: Memory(u16, u8),

    pub fn init(allocator: std.mem.Allocator, bus: Memory(u16, u8)) !*Timer {
        const instance = try allocator.create(Timer);
        instance.* = .{ .allocator = allocator, .bus = bus };
        return instance;
    }

    pub fn deinit(self: *Timer) void {
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn reset(self: *Timer) void {
        self.tima = 0;
        self.tma = 0;
        self.overflow = null;
        self.counter = @bitCast(@as(u14, 0));
        self.tac = @bitCast(@as(u8, 0xf8));
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return switch (address) {
            @intFromEnum(IO.TAC) => @bitCast(self.tac),
            @intFromEnum(IO.DIV) => self.counter.div,
            @intFromEnum(IO.TMA) => self.tma,
            @intFromEnum(IO.TIMA) => self.tima,
            else => 0,
        };
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        switch (address) {
            @intFromEnum(IO.TAC) => self.tac = @bitCast(0xf8 | (value & 7)),
            @intFromEnum(IO.DIV) => self.counter = @bitCast(@as(u14, 0)),
            @intFromEnum(IO.TMA) => self.tma = value,
            @intFromEnum(IO.TIMA) => {
                if (self.overflow) |v| {
                    if (v) {
                        self.tima = value;
                        self.overflow = null;
                    }
                } else {
                    self.tima = value;
                }
            },
            else => {},
        }
    }

    pub fn process(self: *Timer) void {
        self.counter = @bitCast(@as(u14, @bitCast(self.counter)) +% 1);
        if (self.tac.enable) {
            if (self.overflow) |v| {
                if (v) {
                    self.overflow = false;
                    self.bus.write(@intFromEnum(IO.IF), self.bus.read(@intFromEnum(IO.IF)) | 4);
                } else {
                    self.overflow = null;
                    self.tima = self.tma;
                }
            }

            const divider: u14 = @as(u14, switch (self.tac.divider) {
                .m4 => 4,
                .m16 => 16,
                .m64 => 64,
                .m256 => 256,
            });

            if ((@as(u14, @bitCast(self.counter)) % divider) == 0) {
                self.tima +%= 1;
                if (self.tima == 0) self.overflow = true;
            }
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

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("tima");
        try jw.write(self.tima);
        try jw.objectField("tma");
        try jw.write(self.tma);
        try jw.objectField("overflow");
        try jw.write(self.overflow);
        try jw.objectField("counter");
        try jw.write(self.counter);
        try jw.objectField("tac");
        try jw.write(self.tac);
        try jw.endObject();
    }
};
