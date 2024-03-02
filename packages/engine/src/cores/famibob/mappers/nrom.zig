// NROM Mapper (iNES ID 000)
//
// NES-NROM-128, NES-NROM-256
//
// PRG ROM size: 16kB for NROM-128, 32kB for NROM-256
// PRG ROM bank size: not bankswitched
// PRG RAM: 2 or 4 kB, not bankswitched
// CHR capacity: 8kB ROM
// CHR bank size: not bankswitched
// Nametable mirroring: fixed vertical or horizontal mirroring
//
// CPU $6000-$7FFF: PRG RAM, mirrored as necessary to fill entire 8kB window
// CPU $8000-$BFFF: first 16kB of ROM
// CPU $C000-$FFFF: last 16kB of ROM (NROM-256) or mirror of $8000-$BFFF (NROM-128)

const std = @import("std");
const Mirroring = @import("../famibob.zig").Mirroring;
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;
const c = @import("../../../c.zig");

pub const NROM = struct {
    allocator: std.mem.Allocator,
    mirroring: Mirroring,
    vram: []u8,
    prg_rom: []u8,
    chr_rom: []u8,
    prg_ram: []u8,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge) !*@This() {
        std.debug.print("Mapper: NROM\n", .{});

        var instance = try allocator.create(NROM);
        instance.* = .{
            .allocator = allocator,
            .mirroring = cartridge.mirroring,
            .vram = try allocator.alloc(u8, 0x800),
            .prg_rom = cartridge.prg_data,
            .chr_rom = cartridge.chr_data,
            .prg_ram = try allocator.alloc(u8, cartridge.prg_ram_size),
        };

        if (cartridge.trainer_data) |t| {
            @memcpy(instance.prg_ram[0x1000..0x1200], t);
        }

        return instance;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.vram);
        self.allocator.free(self.prg_ram);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn convertAddress(self: *@This(), address: u16) ?usize {
        return switch (address) {
            0x0000...0x1fff => |addr| if (self.chr_rom.len > 0) addr % self.chr_rom.len else null,
            0x6000...0x7fff => |addr| if (self.prg_ram.len > 0) addr % self.prg_ram.len else null,
            0x8000...0xbfff => |addr| if (self.prg_rom.len > 0) addr % 0x4000 else null,
            0xc000...0xffff => |addr| if (self.prg_rom.len > 0) if (self.prg_rom.len > 0x4000) (addr % 0x4000) + 0x4000 else addr % 0x4000 else null,
            0x2000...0x3fff => |addr| switch (self.mirroring) {
                .horizontal => (addr & 0x3ff) | ((addr & 0x800) >> 1),
                .vertical => addr & 0x7ff,
                else => 0,
            },
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
                else => @as(u8, @truncate(address & 0xff)),
            };
        }
        return @as(u8, @truncate(address & 0xff));
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            switch (address) {
                0x2000...0x3fff => {
                    self.vram[addr] = value;
                },
                0x6000...0x7fff => {
                    self.prg_ram[addr] = value;
                },
                else => {},
            }
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

        c.mpack_write_cstr(pack, "mirroring");
        c.mpack_write_u8(pack, @intFromEnum(self.mirroring));

        c.mpack_complete_map(pack);
    }

    fn deserialize(ctx: *anyopaque, pack: c.mpack_node_t) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        @memset(self.vram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "vram"), self.vram.ptr, self.vram.len);

        @memset(self.prg_ram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "prg_ram"), self.prg_ram.ptr, self.prg_ram.len);

        self.mirroring = @enumFromInt(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "mirroring")));
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
