const std = @import("std");
const getDmgPalettes = @import("dmg_palettes.zig").getDmgPalettes;

pub const Cartridge = struct {
    allocator: std.mem.Allocator,
    rom_data: []u8,
    crc: u32,
    title_hash: u8,
    dmg_mode: bool,
    is_nintendo: bool,
    mapper_id: u8,
    rom_size: usize,
    ram_size: usize,
    battery: bool = false,
    palette: usize,

    pub fn init(allocator: std.mem.Allocator, rom_data: []const u8) !*Cartridge {
        std.debug.print("Parsing GB ROM...\n", .{});
        const instance = try allocator.create(Cartridge);

        var title_hash: u8 = 0;
        for (0x134..0x144) |i| title_hash +%= rom_data[i];
        const is_nintendo = rom_data[0x14b] == 0x01 or (rom_data[0x14b] == 0x33 and rom_data[0x144] == '0' and rom_data[0x145] == '1');
        const palette = getDmgPalettes(rom_data, title_hash, is_nintendo);

        instance.* = .{
            .allocator = allocator,
            .rom_data = try allocator.alloc(u8, rom_data.len),
            .crc = std.hash.Crc32.hash(rom_data),
            .title_hash = title_hash,
            .is_nintendo = is_nintendo,
            .palette = palette,
            .dmg_mode = rom_data[0x143] != 0x80 and rom_data[0x143] != 0xc0,
            .mapper_id = rom_data[0x147],
            .rom_size = 32768 * (@as(usize, 1) << @as(u5, @intCast(rom_data[0x148]))),
            .ram_size = switch (rom_data[0x149]) {
                2 => 8192,
                3 => 32768,
                4 => 131072,
                5 => 65536,
                else => 0,
            },
        };

        instance.battery = switch (instance.mapper_id) {
            0x03, 0x06, 0x09, 0x0d, 0x0f, 0x10, 0x13, 0x1b, 0x1e, 0x22, 0xff => true,
            else => false,
        };

        @memcpy(instance.rom_data, rom_data);

        std.debug.print("CRC: {x}\n", .{instance.crc});
        std.debug.print("DMG Mode: {any}\n", .{instance.dmg_mode});
        std.debug.print("Palette: {d}\n", .{instance.palette});
        std.debug.print("Mapper ID: {d}\n", .{instance.mapper_id});
        std.debug.print("ROM size: {d}\n", .{instance.rom_size});
        std.debug.print("RAM size: {d}\n", .{instance.ram_size});
        std.debug.print("Battery: {any}\n", .{instance.battery});

        return instance;
    }

    pub fn deinit(self: *Cartridge) void {
        self.allocator.free(self.rom_data);
        self.allocator.destroy(self);
    }
};
