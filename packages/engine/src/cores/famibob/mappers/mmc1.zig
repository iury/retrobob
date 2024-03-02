// MMC1 Mapper (iNES ID 001)
//
// SxROM
//
// PRG ROM size: 256K (512K)
// PRG ROM window: 16K + 16K fixed or 32K
// PRG RAM: 32K
// PRG RAM window: 8K
// CHR capacity: 128K
// CHR window: 4K + 4K or 8K
// Nametable mirroring: H, V, or 1, switchable
//
// PPU $0000-$0FFF: 4 KB switchable CHR bank
// PPU $1000-$1FFF: 4 KB switchable CHR bank
// CPU $6000-$7FFF: 8 KB PRG RAM bank, (optional)
// CPU $8000-$BFFF: 16 KB PRG ROM bank, either switchable or fixed to the first bank
// CPU $C000-$FFFF: 16 KB PRG ROM bank, either fixed to the last bank or switchable

const std = @import("std");
const Mirroring = @import("../famibob.zig").Mirroring;
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;
const c = @import("../../../c.zig");

pub const MMC1 = struct {
    allocator: std.mem.Allocator,
    mirroring: Mirroring,

    vram: []u8,
    prg_rom: []u8,
    chr_rom: []u8,
    chr_ram: ?[]u8 = null,
    prg_ram: []u8,

    load_register: u16 = 0,
    control: u8 = 0,
    chr_bank1: usize = 0,
    chr_bank2: usize = 0,
    prg_rom_bank: usize = 0,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge) !*@This() {
        std.debug.print("Mapper: MMC1\n", .{});
        const instance = try allocator.create(MMC1);

        var chr_ram: ?[]u8 = null;
        var chr_rom: []u8 = cartridge.chr_data;
        if (chr_rom.len == 0) {
            chr_rom = try allocator.alloc(u8, @max(cartridge.chr_ram_size, 0x8000));
            chr_ram = chr_rom;
        }

        instance.* = .{
            .allocator = allocator,
            .mirroring = cartridge.mirroring,
            .vram = try allocator.alloc(u8, 0x800),
            .prg_rom = cartridge.prg_data,
            .chr_rom = chr_rom,
            .chr_ram = chr_ram,
            .prg_ram = try allocator.alloc(u8, cartridge.prg_ram_size),
            .control = 0xc | (if (cartridge.mirroring == .horizontal) @as(u8, 3) else (if (cartridge.mirroring == .vertical) @as(u8, 2) else 0)),
        };

        if (cartridge.trainer_data) |t| {
            @memcpy(instance.prg_ram[0x1000..0x1200], t);
        }

        return instance;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.vram);
        if (self.chr_ram) |arr| self.allocator.free(arr);
        self.allocator.free(self.prg_ram);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn convertAddress(self: *@This(), address: u16) ?usize {
        return switch (address) {
            0x0000...0x1FFF => |addr| if (self.chr_rom.len > 0) blk: {
                if (self.control & 0x10 == 0) {
                    break :blk ((self.chr_bank1 >> 1) * 0x2000) | addr;
                } else {
                    break :blk ((if (addr < 0x1000) self.chr_bank1 else self.chr_bank2) * 0x1000) | (addr % 0x1000);
                }
            } % self.chr_rom.len else null,

            0x2000...0x3FFF => |addr| switch (self.control & 0x3) {
                0 => addr & 0x3FF,
                1 => (addr & 0x3FF) + 0x400,
                2 => addr & 0x7FF,
                3 => (addr & 0x3FF) | ((addr & 0x800) >> 1),
                else => 0,
            },

            0x6000...0x7FFF => |addr| if (self.prg_ram.len > 0) (addr % 0x6000) % self.prg_ram.len else null,

            0x8000...0xFFFF => |addr| if (self.prg_rom.len > 0) blk: {
                const mode = self.control & 0xC;
                if (mode >= 0x8) {
                    if (addr >= 0x8000 and addr <= 0xBFFF) {
                        if (mode == 0x8) {
                            break :blk (addr % 0x8000);
                        } else {
                            break :blk ((addr % 0x8000) + self.prg_rom_bank * 0x4000);
                        }
                    } else {
                        if (mode == 0x8) {
                            break :blk ((addr % 0xC000) + self.prg_rom_bank * 0x4000);
                        } else {
                            break :blk self.prg_rom.len - 0x4000 + (addr % 0xC000);
                        }
                    }
                } else {
                    break :blk ((addr % 0x8000) + (self.prg_rom_bank >> 1) * 0x8000);
                }
            } % self.prg_rom.len else null,
            else => null,
        };
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            return switch (address) {
                0x0000...0x1FFF => self.chr_rom[addr],
                0x2000...0x3FFF => self.vram[addr],
                0x6000...0x7FFF => self.prg_ram[addr],
                0x8000...0xFFFF => self.prg_rom[addr],
                else => 0,
            };
        } else {
            return 0;
        }
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        switch (address) {
            0x8000...0xffff => {
                if ((value & 0x80) > 0) {
                    self.load_register = 1 << 4;
                    self.control |= 0xc;
                } else {
                    const mark = self.load_register & 1;
                    self.load_register = (self.load_register >> 1) | ((value & 1) << 4);
                    if (mark > 0) {
                        switch (address) {
                            0x8000...0x9fff => self.control = @truncate(self.load_register),
                            0xa000...0xbfff => self.chr_bank1 = self.load_register,
                            0xc000...0xdfff => self.chr_bank2 = self.load_register,
                            0xe000...0xffff => self.prg_rom_bank = self.load_register & 0xf,
                            else => {},
                        }
                        self.load_register = 1 << 4;
                    }
                }
            },
            else => {
                if (self.convertAddress(address)) |addr| {
                    switch (address) {
                        0x0000...0x1fff => {
                            self.chr_rom[addr] = value;
                        },
                        0x2000...0x3fff => {
                            self.vram[addr] = value;
                        },
                        0x6000...0x7fff => {
                            self.prg_ram[addr] = value;
                        },
                        else => {},
                    }
                }
            },
        }
    }

    fn serialize(ctx: *const anyopaque, pack: *c.mpack_writer_t) void {
        const self: *const @This() = @ptrCast(@alignCast(ctx));
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "vram");
        c.mpack_start_bin(pack, @intCast(self.vram.len));
        c.mpack_write_bytes(pack, self.vram.ptr, self.vram.len);
        c.mpack_finish_bin(pack);

        c.mpack_write_cstr(pack, "prg_ram");
        c.mpack_start_bin(pack, @intCast(self.prg_ram.len));
        c.mpack_write_bytes(pack, self.prg_ram.ptr, self.prg_ram.len);
        c.mpack_finish_bin(pack);

        if (self.chr_ram) |chr| {
            c.mpack_write_cstr(pack, "chr_ram");
            c.mpack_start_bin(pack, @intCast(chr.len));
            c.mpack_write_bytes(pack, chr.ptr, chr.len);
            c.mpack_finish_bin(pack);
        }

        c.mpack_write_cstr(pack, "mirroring");
        c.mpack_write_u8(pack, @intFromEnum(self.mirroring));
        c.mpack_write_cstr(pack, "load_register");
        c.mpack_write_u16(pack, self.load_register);
        c.mpack_write_cstr(pack, "control");
        c.mpack_write_u8(pack, self.control);
        c.mpack_write_cstr(pack, "chr_bank1");
        c.mpack_write_u32(pack, @truncate(self.chr_bank1));
        c.mpack_write_cstr(pack, "chr_bank2");
        c.mpack_write_u32(pack, @truncate(self.chr_bank2));
        c.mpack_write_cstr(pack, "prg_rom_bank");
        c.mpack_write_u32(pack, @truncate(self.prg_rom_bank));

        c.mpack_complete_map(pack);
    }

    fn deserialize(ctx: *anyopaque, pack: c.mpack_node_t) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        @memset(self.vram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "vram"), self.vram.ptr, self.vram.len);

        @memset(self.prg_ram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "prg_ram"), self.prg_ram.ptr, self.prg_ram.len);

        if (self.chr_ram) |chr| {
            @memset(chr, 0);
            _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "chr_ram"), chr.ptr, chr.len);
        }

        self.mirroring = @enumFromInt(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "mirroring")));
        self.load_register = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "load_register"));
        self.control = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "control"));
        self.chr_bank1 = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "chr_bank1"));
        self.chr_bank2 = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "chr_bank2"));
        self.prg_rom_bank = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "prg_rom_bank"));
    }

    pub fn memory(self: *@This()) Memory(u16, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinitMemory,
                .serialize = serialize,
                .deserialize = deserialize,
            },
        };
    }
};
