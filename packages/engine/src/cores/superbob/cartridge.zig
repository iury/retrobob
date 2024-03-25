const std = @import("std");
const Region = @import("../core.zig").Region;

pub const Cartridge = struct {
    allocator: std.mem.Allocator,
    rom_data: []u8,
    crc: u32,
    battery: bool = false,
    region: Region = .ntsc,
    ram_size: usize = 0,
    mapper: enum { unknown, lorom, hirom, exhirom } = .unknown,
    coprocessor: enum { none, dsp, gsu, sa1, sdd1, cx4 } = .none,

    pub fn init(allocator: std.mem.Allocator, rom_data: []const u8) !*Cartridge {
        std.debug.print("Parsing SNES ROM...\n", .{});
        const instance = try allocator.create(Cartridge);
        var corrupted_header = true;

        var rom_size: usize = if (rom_data.len % 1024 == 512) rom_data.len - 512 else rom_data.len;
        rom_size = try std.math.powi(usize, 2, std.math.log2_int_ceil(usize, rom_size));

        instance.* = .{
            .allocator = allocator,
            .rom_data = try allocator.alloc(u8, rom_size),
            .crc = std.hash.Crc32.hash(rom_data),
        };

        // skip 512-byte header of some copier devices
        @memset(instance.rom_data, 0);
        var offset: usize = if (rom_data.len % 1024 == 512) 512 else 0;
        const len = rom_data.len - offset;
        @memcpy(instance.rom_data[0..len], rom_data[offset .. offset + len]);

        // mirror second block to be a power of two
        offset = try std.math.powi(usize, 2, std.math.log2_int(usize, len));
        if (len > offset) {
            const block_size = try std.math.powi(usize, 2, std.math.log2_int_ceil(usize, len - offset));
            while ((offset + block_size) < instance.rom_data.len) {
                @memcpy(instance.rom_data[offset + block_size .. offset + (block_size * 2)], instance.rom_data[offset .. offset + block_size]);
                offset += block_size;
            }
        }

        // compute and check the checksum to determine the mapper
        var checksum: u16 = 0;
        {
            for (0..instance.rom_data.len) |i| checksum +%= instance.rom_data[i];
            var chk1 = instance.rom_data[0x7fde] | (@as(u16, instance.rom_data[0x7fdf]) << 8);
            var chk2 = instance.rom_data[0x7fdc] | (@as(u16, instance.rom_data[0x7fdd]) << 8);
            if (checksum == chk1 and (checksum ^ 0xffff) == chk2) {
                corrupted_header = false;
                instance.mapper = .lorom;
                offset = 0x7fb0;
            } else if (instance.rom_data.len > 0xffc0) {
                chk1 = instance.rom_data[0xffde] | (@as(u16, instance.rom_data[0xffdf]) << 8);
                chk2 = instance.rom_data[0xffdc] | (@as(u16, instance.rom_data[0xffdd]) << 8);
                if (checksum == chk1 and (checksum ^ 0xffff) == chk2) {
                    corrupted_header = false;
                    instance.mapper = .hirom;
                    offset = 0xffb0;
                } else if (instance.rom_data.len > 0x40ffc0) {
                    chk1 = instance.rom_data[0x40ffde] | (@as(u16, instance.rom_data[0x40ffdf]) << 8);
                    chk2 = instance.rom_data[0x40ffdc] | (@as(u16, instance.rom_data[0x40ffdd]) << 8);
                    if (checksum == chk1 and (checksum ^ 0xffff) == chk2) {
                        corrupted_header = false;
                        instance.mapper = .exhirom;
                        offset = 0x40ffb0;
                    }
                }
            }
        }

        // first heuristics
        if (instance.mapper == .unknown) {
            var chk1 = instance.rom_data[0x7fde] | (@as(u16, instance.rom_data[0x7fdf]) << 8);
            var chk2 = instance.rom_data[0x7fdc] | (@as(u16, instance.rom_data[0x7fdd]) << 8);
            if (chk1 == (chk2 ^ 0xffff)) {
                corrupted_header = false;
                instance.mapper = .lorom;
                offset = 0x7fb0;
            } else if (instance.rom_data.len > 0xffc0) {
                chk1 = instance.rom_data[0xffde] | (@as(u16, instance.rom_data[0xffdf]) << 8);
                chk2 = instance.rom_data[0xffdc] | (@as(u16, instance.rom_data[0xffdd]) << 8);
                if (chk1 == (chk2 ^ 0xffff)) {
                    corrupted_header = false;
                    instance.mapper = .hirom;
                    offset = 0xffb0;
                } else if (instance.rom_data.len > 0x40ffc0) {
                    chk1 = instance.rom_data[0x40ffde] | (@as(u16, instance.rom_data[0x40ffdf]) << 8);
                    chk2 = instance.rom_data[0x40ffdc] | (@as(u16, instance.rom_data[0x40ffdd]) << 8);
                    if (chk1 == (chk2 ^ 0xffff)) {
                        corrupted_header = false;
                        instance.mapper = .exhirom;
                        offset = 0x40ffb0;
                    }
                }
            }
        }

        // second heuristics
        if (instance.mapper == .unknown) {
            var all_ascii = true;
            for (0x7fc0..0x7fd5) |i| {
                if (!std.ascii.isPrint(instance.rom_data[i])) {
                    all_ascii = false;
                    break;
                }
            }
            if (all_ascii) {
                corrupted_header = false;
                instance.mapper = .lorom;
                offset = 0x7fb0;
            } else if (instance.rom_data.len >= 0xffff) {
                all_ascii = true;
                for (0xffc0..0xffd5) |i| {
                    if (!std.ascii.isPrint(instance.rom_data[i])) {
                        all_ascii = false;
                        break;
                    }
                }
                if (all_ascii) {
                    corrupted_header = false;
                    instance.mapper = .hirom;
                    offset = 0xffb0;
                } else if (instance.rom_data.len >= 0x40ffff) {
                    all_ascii = true;
                    for (0x40ffc0..0x40ffd5) |i| {
                        if (!std.ascii.isPrint(instance.rom_data[i])) {
                            all_ascii = false;
                            break;
                        }
                    }
                    if (all_ascii) {
                        corrupted_header = false;
                        instance.mapper = .exhirom;
                        offset = 0x40ffb0;
                    }
                }
            }
        }

        // third heuristics, header now is probably corrupted
        if (instance.mapper == .unknown) {
            var vector: u16 = (@as(u16, instance.rom_data[0x7ffd]) << 8) | instance.rom_data[0x7ffc];
            if (vector >= 0x8000 and instance.rom_data[0] != 0 and instance.rom_data[0] != 0xff) {
                corrupted_header = true;
                instance.mapper = .lorom;
                offset = 0x7fb0;
            } else if (instance.rom_data.len >= 0xffff) {
                vector = (@as(u16, instance.rom_data[0xfffd]) << 8) | instance.rom_data[0xfffc];
                if (vector >= 0x8000 and instance.rom_data[vector] != 0 and instance.rom_data[vector] != 0xff) {
                    corrupted_header = true;
                    instance.mapper = .hirom;
                    offset = 0xffb0;
                }
            }
        }

        if (instance.mapper == .unknown) return error.UnsupportedFile;

        if (!corrupted_header) {
            instance.ram_size = if (instance.rom_data[offset + 0x28] > 0) try std.math.powi(usize, 2, instance.rom_data[offset + 0x28]) * 1024 else 0;

            instance.region = switch (instance.rom_data[offset + 0x29]) {
                0x0, 0x1, 0xd, 0x10 => .ntsc,
                else => .pal,
            };

            const chipset = instance.rom_data[offset + 0x26];

            if (chipset == 0 or chipset & 0xf == 3 or chipset & 0xf == 6) {
                instance.ram_size = 0;
            }

            instance.battery = (chipset & 0xf) == 2 or (chipset & 0xf) == 5 or (chipset & 0xf) == 6 or (chipset & 0xf) == 9 or (chipset & 0xf == 10);

            if (chipset > 2) {
                switch (chipset & 0xf0) {
                    0x00 => instance.coprocessor = .dsp,
                    0x10 => {
                        instance.coprocessor = .gsu;
                        if (instance.rom_data[offset + 0x0d] != 0xff) {
                            instance.ram_size = try std.math.powi(usize, 2, instance.rom_data[offset + 0x0d]) * 1024;
                        }
                    },
                    0x30 => instance.coprocessor = .sa1,
                    0x40 => instance.coprocessor = .sdd1,
                    0xf0 => {
                        if (instance.rom_data[offset + 0x0f] == 0x10) {
                            instance.coprocessor = .cx4;
                        } else {
                            return error.UnsupportedCoprocessor;
                        }
                    },
                    else => return error.UnsupportedCoprocessor,
                }
            }

            if (instance.coprocessor != .none) {
                return error.UnsupportedCoprocessor;
            }
        } else {
            std.debug.print("Corrupted header. Assuming default values\n", .{});
            instance.region = .ntsc;
            instance.coprocessor = .none;
            instance.ram_size = 0;
        }

        std.debug.print("CRC: {x}\n", .{instance.crc});
        std.debug.print("ROM size: {d}\n", .{instance.rom_data.len});
        std.debug.print("RAM size: {d}\n", .{instance.ram_size});
        std.debug.print("Region: {s}\n", .{@tagName(instance.region)});
        std.debug.print("Battery: {any}\n", .{instance.battery});
        std.debug.print("Mapper: {s}\n", .{@tagName(instance.mapper)});
        std.debug.print("Coprocessor: {s}\n", .{@tagName(instance.coprocessor)});

        return instance;
    }

    pub fn deinit(self: *Cartridge) void {
        self.allocator.free(self.rom_data);
        self.allocator.destroy(self);
    }
};
