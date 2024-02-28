const std = @import("std");
const Memory = @import("../../memory.zig").Memory;

pub const MemoryBus = struct {
    allocator: std.mem.Allocator,
    ram: []u8,

    mapper_handler: Memory(u16, u8),
    ppu_handler: Memory(u16, u8),
    apu_handler: Memory(u16, u8),
    input_handler: Memory(u16, u8),

    pub fn init(
        allocator: std.mem.Allocator,
        mapper_handler: Memory(u16, u8),
        ppu_handler: Memory(u16, u8),
        apu_handler: Memory(u16, u8),
        input_handler: Memory(u16, u8),
    ) !*MemoryBus {
        const instance = try allocator.create(MemoryBus);

        instance.* = .{
            .allocator = allocator,
            .ram = try allocator.alloc(u8, 0x800),
            .mapper_handler = mapper_handler,
            .ppu_handler = ppu_handler,
            .apu_handler = apu_handler,
            .input_handler = input_handler,
        };

        var rnd = std.rand.DefaultPrng.init(@bitCast(std.time.timestamp()));
        const random = rnd.random();
        for (0..instance.ram.len) |i| {
            instance.ram[i] = random.int(u8);
        }

        return instance;
    }

    pub fn deinit(self: *MemoryBus) void {
        self.allocator.free(self.ram);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return switch (address) {
            0x0000...0x1fff => self.ram[address % 0x800],
            0x2000...0x3fff => self.ppu_handler.read(0x2000 + (address % 8)),
            0x4015 => self.apu_handler.read(address),
            0x4000...0x4014, 0x4016...0xffff => blk: {
                var v: u8 = 0;
                if (address == 0x4016 or address == 0x4017) {
                    v = 0x40 | self.input_handler.read(address);
                } else {
                    v = self.mapper_handler.read(address);
                }
                break :blk v;
            },
        };
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        switch (address) {
            0x0000...0x1fff => self.ram[address % 0x800] = value,
            0x2000...0x3fff => self.ppu_handler.write(0x2000 + (address % 8), value),
            0x4014 => self.ppu_handler.write(address, value),
            0x4016 => self.input_handler.write(address, value),
            0x4000...0x4013, 0x4015, 0x4017 => self.apu_handler.write(address, value),
            0x4020...0xffff => self.mapper_handler.write(address, value),
            else => {},
        }
    }

    fn jsonStringify(ctx: *anyopaque, allocator: std.mem.Allocator) !std.json.Value {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        var data = std.json.ObjectMap.init(allocator);
        try data.put("ram", .{ .string = self.ram });
        return .{ .object = data };
    }

    pub fn jsonParse(ctx: *anyopaque, value: std.json.Value) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        @memset(self.ram, 0);
        for (value.object.get("ram").?.array.items, 0..) |v, i| {
            self.ram[i] = @intCast(v.integer);
        }
    }

    pub fn memory(self: *MemoryBus) Memory(u16, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinitMemory,
                .jsonParse = jsonParse,
                .jsonStringify = jsonStringify,
            },
        };
    }
};
