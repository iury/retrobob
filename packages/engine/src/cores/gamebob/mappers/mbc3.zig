const std = @import("std");
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;

pub const MBC3 = struct {
    allocator: std.mem.Allocator,
    rom: []u8,
    ram: []u8,

    ram_enable: bool,
    rom_bank: u8,
    ram_bank: u8,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge) !*@This() {
        std.debug.print("Mapper: MBC3\n", .{});

        var instance = try allocator.create(MBC3);

        instance.* = .{
            .allocator = allocator,
            .rom = cartridge.rom_data,
            .ram = try allocator.alloc(u8, cartridge.ram_size),
            .ram_enable = false,
            .rom_bank = 1,
            .ram_bank = 0,
        };

        var rnd = std.rand.DefaultPrng.init(@bitCast(std.time.timestamp()));
        const random = rnd.random();
        for (0..instance.ram.len) |i| {
            instance.ram[i] = random.int(u8);
        }

        return instance;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.ram);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn convertAddress(self: *@This(), address: u16) ?usize {
        return switch (address) {
            0x0000...0x3fff => |addr| addr,
            0x4000...0x7fff => |addr| (@as(usize, self.rom_bank) * 0x4000) | (addr - 0x4000),
            0xa000...0xbfff => |addr| if (self.ram_bank != 0xff) ((@as(usize, self.ram_bank) * 0x2000) | (addr - 0xa000)) else null,
            else => null,
        };
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            return switch (address) {
                0x0000...0x7fff => self.rom[addr % self.rom.len],
                0xa000...0xbfff => if (self.ram_enable and self.ram.len > 0) self.ram[addr % self.ram.len] else 0xff,
                else => 0xff,
            };
        }
        return 0;
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            switch (address) {
                0x0000...0x1fff => {
                    self.ram_enable = (value & 0xf) == 0xa;
                },
                0x2000...0x3fff => {
                    self.rom_bank = if (value > 1) value else 1;
                },
                0x4000...0x5fff => {
                    self.ram_bank = if (value < 4) value else 0xff;
                },
                0x6000...0x7fff => {},
                0xa000...0xbfff => {
                    if (self.ram_enable and self.ram_bank != 0xff and self.ram.len > 0) {
                        self.ram[addr % self.ram.len] = value;
                    }
                },
                else => {},
            }
        }
    }

    fn jsonParse(ctx: *anyopaque, allocator: std.mem.Allocator, value: std.json.Value) !void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const ram = try std.json.parseFromValueLeaky([]u8, allocator, value.object.get("ram").?, .{});
        @memcpy(self.ram, ram);
    }

    fn jsonStringify(ctx: *anyopaque, allocator: std.mem.Allocator) !std.json.Value {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        var data = std.json.ObjectMap.init(allocator);
        try data.put("ram", .{ .string = self.ram });
        try data.put("ram_enable", .{ .bool = self.ram_enable });
        try data.put("rom_bank", .{ .integer = self.rom_bank });
        try data.put("ram_bank", .{ .integer = self.ram_bank });
        return .{ .object = data };
    }

    pub fn memory(self: *@This()) Memory(u16, u8) {
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
