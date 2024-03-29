// MMC2 Mapper (iNES ID 009)
//
// PRG capacity: 128K
// PRG ROM window: 8K + 24K fixed
// PRG RAM: none
// CHR capacity: 128K
// CHR window: 4K + 4K (triggered)
// Nametable mirroring: H or V, switchable
//
// PPU $0000-$0FFF: Two 4 KB switchable CHR ROM banks
// PPU $1000-$1FFF: Two 4 KB switchable CHR ROM banks
// CPU $8000-$9FFF: 8 KB switchable PRG ROM bank
// CPU $A000-$FFFF: Three 8 KB PRG ROM banks, fixed to the last three banks

const std = @import("std");
const Mirroring = @import("../famibob.zig").Mirroring;
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;
const c = @import("../../../c.zig");

pub const MMC2 = struct {
    allocator: std.mem.Allocator,
    mirroring: Mirroring,

    vram: []u8,
    prg_rom: []u8,
    chr_rom: []u8,

    latch0: u8 = 0xFD,
    latch1: u8 = 0xFD,
    chr_bankFD0: usize = 0,
    chr_bankFE0: usize = 0,
    chr_bankFD1: usize = 0,
    chr_bankFE1: usize = 0,
    prg_bank: usize = 0,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge) !*@This() {
        std.debug.print("Mapper: MMC2\n", .{});
        const instance = try allocator.create(MMC2);
        instance.* = .{
            .allocator = allocator,
            .mirroring = cartridge.mirroring,
            .vram = try allocator.alloc(u8, 0x800),
            .prg_rom = cartridge.prg_data,
            .chr_rom = cartridge.chr_data,
        };
        return instance;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.vram);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn convertAddress(self: *@This(), address: u16) ?usize {
        return switch (address) {
            0x0000...0x0FFF => |addr| if (self.chr_rom.len > 0) ((if (self.latch0 == 0xFD) self.chr_bankFD0 else self.chr_bankFE0) * 0x1000 + (addr % 0x1000)) % self.chr_rom.len else null,
            0x1000...0x1FFF => |addr| if (self.chr_rom.len > 0) ((if (self.latch1 == 0xFD) self.chr_bankFD1 else self.chr_bankFE1) * 0x1000 + (addr % 0x1000)) % self.chr_rom.len else null,
            0x8000...0x9FFF => |addr| if (self.prg_rom.len > 0) (self.prg_bank * 0x2000 + (addr % 0x8000)) % self.prg_rom.len else null,
            0xA000...0xFFFF => |addr| if (self.prg_rom.len > 0) (self.prg_rom.len - 0x6000 + (addr % 0xA000)) % self.prg_rom.len else null,
            0x2000...0x3FFF => |addr| switch (self.mirroring) {
                .horizontal => (addr & 0x3FF) | ((addr & 0x800) >> 1),
                .vertical => addr & 0x7FF,
                else => 0,
            },
            else => null,
        };
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            return switch (address) {
                0x0000...0x1FFF => blk: {
                    const v = self.chr_rom[addr];
                    if (address == 0x0FD8) self.latch0 = 0xFD;
                    if (address == 0x0FE8) self.latch0 = 0xFE;
                    if (address >= 0x1FD8 and address <= 0x1FDF) self.latch1 = 0xFD;
                    if (address >= 0x1FE8 and address <= 0x1FEF) self.latch1 = 0xFE;
                    break :blk v;
                },
                0x2000...0x3FFF => self.vram[addr],
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
            0xA000...0xAFFF => {
                self.prg_bank = value & 0xF;
            },
            0xB000...0xBFFF => {
                self.chr_bankFD0 = value & 0x1F;
            },
            0xC000...0xCFFF => {
                self.chr_bankFE0 = value & 0x1F;
            },
            0xD000...0xDFFF => {
                self.chr_bankFD1 = value & 0x1F;
            },
            0xE000...0xEFFF => {
                self.chr_bankFE1 = value & 0x1F;
            },
            0xF000...0xFFFF => {
                self.mirroring = if (value & 1 == 0) .vertical else .horizontal;
            },
            else => {
                if (self.convertAddress(address)) |addr| {
                    switch (address) {
                        0x2000...0x3FFF => {
                            self.vram[addr] = value;
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

        c.mpack_write_cstr(pack, "mirroring");
        c.mpack_write_u8(pack, @intFromEnum(self.mirroring));
        c.mpack_write_cstr(pack, "latch0");
        c.mpack_write_u8(pack, self.latch0);
        c.mpack_write_cstr(pack, "latch1");
        c.mpack_write_u8(pack, self.latch1);
        c.mpack_write_cstr(pack, "chr_bankFD0");
        c.mpack_write_u32(pack, @truncate(self.chr_bankFD0));
        c.mpack_write_cstr(pack, "chr_bankFE0");
        c.mpack_write_u32(pack, @truncate(self.chr_bankFE0));
        c.mpack_write_cstr(pack, "chr_bankFD1");
        c.mpack_write_u32(pack, @truncate(self.chr_bankFD1));
        c.mpack_write_cstr(pack, "chr_bankFE1");
        c.mpack_write_u32(pack, @truncate(self.chr_bankFE1));
        c.mpack_write_cstr(pack, "prg_bank");
        c.mpack_write_u32(pack, @truncate(self.prg_bank));

        c.mpack_complete_map(pack);
    }

    fn deserialize(ctx: *anyopaque, pack: c.mpack_node_t) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        @memset(self.vram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "vram"), self.vram.ptr, self.vram.len);

        self.mirroring = @enumFromInt(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "mirroring")));
        self.latch0 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "latch0"));
        self.latch1 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "latch1"));
        self.chr_bankFD0 = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "chr_bankFD0"));
        self.chr_bankFE0 = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "chr_bankFE0"));
        self.chr_bankFD1 = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "chr_bankFD1"));
        self.chr_bankFE1 = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "chr_bankFE1"));
        self.prg_bank = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "prg_bank"));
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
