const std = @import("std");
const Region = @import("../core.zig").Region;
const Mirroring = @import("famibob.zig").Mirroring;

pub const Cartridge = struct {
    allocator: std.mem.Allocator,
    prg_data: []u8,
    chr_data: []u8,
    trainer_data: ?[]u8 = null,

    crc: u32 = 0,
    mapper_id: u8 = 0,
    prg_rom_size: usize = 0,
    chr_rom_size: usize = 0,
    prg_ram_size: usize = 0,
    chr_ram_size: usize = 0,
    trainer: bool = false,
    battery: bool = false,
    region: Region = .ntsc,
    mirroring: Mirroring = .horizontal,

    pub fn init(allocator: std.mem.Allocator, rom_data: []const u8) !*Cartridge {
        if (rom_data[0] == 'N' and rom_data[1] == 'E' and rom_data[2] == 'S' and rom_data[3] == 0x1a) {
            if ((rom_data[7] & 3) != 0) {
                return error.UnsupportedSystem;
            }

            std.debug.print("Parsing NES ROM...\n", .{});
            std.debug.print("ROM size: {d}\n", .{rom_data.len});

            var instance = try allocator.create(Cartridge);

            instance.* = .{
                .allocator = allocator,
                .prg_data = undefined,
                .chr_data = undefined,
                .crc = std.hash.Crc32.hash(rom_data),
                .prg_rom_size = 16 * 1024 * @as(usize, rom_data[4]),
                .chr_rom_size = 8 * 1024 * @as(usize, rom_data[5]),
                .mapper_id = (rom_data[6] >> 4) | (rom_data[7] & 0xf0),
                .trainer = (rom_data[6] & 4) > 0,
                .battery = (rom_data[6] & 2) > 0,
            };

            if ((rom_data[6] & 8) > 0) {
                instance.mirroring = .four_screen;
            } else if ((rom_data[6] & 1) > 0) {
                instance.mirroring = .vertical;
            } else {
                instance.mirroring = .horizontal;
            }

            if ((rom_data[7] & 0xc) == 8) {
                std.debug.print("NES 2.0 file format.\n", .{});
                instance.prg_ram_size = if (rom_data[10] & 0xf > 0) @as(usize, 64) << @as(u4, @truncate(rom_data[10] & 0xf)) else 64 << 7;
                instance.chr_ram_size = @as(usize, 64) << @as(u4, @truncate(rom_data[11] & 0xf));
                instance.region = if ((rom_data[12] & 3) != 1) .ntsc else .pal;
            } else {
                std.debug.print("iNES file format\n", .{});
                instance.prg_ram_size = 8 * 1024;
                instance.chr_ram_size = 0;
                instance.region = .ntsc;
            }

            const prg_from: usize = if (instance.trainer) 528 else 16;
            instance.prg_data = try allocator.alloc(u8, instance.prg_rom_size);
            if (instance.prg_data.len > 0) {
                @memcpy(instance.prg_data, rom_data[prg_from .. prg_from + instance.prg_rom_size]);
            }

            instance.chr_data = try allocator.alloc(u8, instance.chr_rom_size);
            if (instance.chr_data.len > 0) {
                @memcpy(instance.chr_data, rom_data[rom_data.len - instance.chr_rom_size ..]);
            }

            if (instance.trainer) {
                instance.trainer_data = try allocator.alloc(u8, 512);
                @memcpy(instance.trainer_data.?, rom_data[16..528]);
            }

            std.debug.print("Mapper ID: {d}\n", .{instance.mapper_id});
            std.debug.print("Region: {s}\n", .{std.enums.tagName(Region, instance.region).?});
            std.debug.print("Mirroring: {s}\n", .{std.enums.tagName(Mirroring, instance.mirroring).?});
            std.debug.print("Battery: {any}\n", .{instance.battery});
            std.debug.print("Trainer data: {any}\n", .{instance.trainer});
            std.debug.print("PRG ROM size: {d}\n", .{instance.prg_data.len});
            std.debug.print("CHR ROM size: {d}\n", .{instance.chr_data.len});
            std.debug.print("PRG RAM size: {d}\n", .{instance.prg_ram_size});
            std.debug.print("CHR RAM size: {d}\n", .{instance.chr_ram_size});

            return instance;
        } else {
            return error.UnsupportedFile;
        }
    }

    pub fn deinit(self: *Cartridge) void {
        self.allocator.free(self.prg_data);
        self.allocator.free(self.chr_data);
        if (self.trainer_data) |t| self.allocator.free(t);
        self.allocator.destroy(self);
    }
};
