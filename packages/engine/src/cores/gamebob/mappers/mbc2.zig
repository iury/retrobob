const std = @import("std");
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;

pub const MBC2 = struct {
    allocator: std.mem.Allocator,
    rom: []u8,
    ram: []u8,

    ram_enable: bool,
    rom_bank: u8,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge) !*@This() {
        std.debug.print("Mapper: MBC2\n", .{});
        const instance = try allocator.create(MBC2);
        instance.* = .{
            .allocator = allocator,
            .rom = cartridge.rom_data,
            .ram = try allocator.alloc(u8, 0x200),
            .ram_enable = false,
            .rom_bank = 1,
        };
        @memset(instance.ram, 0);
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
            0xa000...0xbfff => |addr| (addr - 0xa000) % 0x200,
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
        return 0xff;
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            switch (address) {
                0x0000...0x3fff => {
                    if (address & 0x100 == 0) {
                        self.ram_enable = value == 0x0a;
                    } else {
                        self.rom_bank = value & 0xf;
                        if (self.rom_bank == 0) self.rom_bank = 1;
                    }
                },
                0xa000...0xbfff => {
                    if (self.ram_enable and self.ram.len > 0) {
                        self.ram[addr % self.ram.len] = value;
                    }
                },
                else => {},
            }
        }
    }

    fn jsonParse(ctx: *anyopaque, value: std.json.Value) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        @memset(self.ram, 0);
        for (value.object.get("ram").?.array.items, 0..) |v, i| {
            self.ram[i] = @intCast(v.integer);
        }

        self.ram_enable = value.object.get("ram_enable").?.bool;
        self.rom_bank = @intCast(value.object.get("rom_bank").?.integer);
    }

    fn jsonStringify(ctx: *anyopaque, allocator: std.mem.Allocator) !std.json.Value {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        var data = std.json.ObjectMap.init(allocator);
        try data.put("ram", .{ .string = self.ram });
        try data.put("ram_enable", .{ .bool = self.ram_enable });
        try data.put("rom_bank", .{ .integer = self.rom_bank });
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
