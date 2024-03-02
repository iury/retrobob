// AxROM Mapper (iNES ID 007)
//
// PRG capacity: 256K
// PRG ROM window: 32K
// PRG RAM: none
// CHR capacity: 8K
// CHR window: n/a
// Nametable mirroring: 1 switchable
//
// CPU $8000-$FFFF: 32 KB switchable PRG ROM bank

const std = @import("std");
const Mirroring = @import("../famibob.zig").Mirroring;
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;
const c = @import("../../../c.zig");

pub const AxROM = struct {
    allocator: std.mem.Allocator,
    mirroring: Mirroring,
    vram: []u8,
    prg_rom: []u8,
    chr_rom: []u8,
    chr_ram: ?[]u8 = null,
    bank: usize = 0,
    page2: bool = false,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge) !*@This() {
        std.debug.print("Mapper: AxROM\n", .{});
        const instance = try allocator.create(AxROM);

        var chr_ram: ?[]u8 = null;
        var chr_rom: []u8 = cartridge.chr_data;
        if (chr_rom.len == 0) {
            chr_rom = try allocator.alloc(u8, @max(cartridge.chr_ram_size, 0x2000));
            chr_ram = chr_rom;
        }

        instance.* = .{
            .allocator = allocator,
            .mirroring = cartridge.mirroring,
            .vram = try allocator.alloc(u8, 0x800),
            .prg_rom = cartridge.prg_data,
            .chr_rom = chr_rom,
            .chr_ram = chr_ram,
        };

        return instance;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.vram);
        if (self.chr_ram) |arr| self.allocator.free(arr);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn convertAddress(self: *@This(), address: u16) ?usize {
        return switch (address) {
            0x0000...0x1FFF => |addr| if (self.chr_rom.len > 0) addr % self.chr_rom.len else null,
            0x2000...0x3FFF => |addr| if (self.page2) (addr % 0x400) + 0x400 else addr % 0x400,
            0x8000...0xFFFF => |addr| if (self.prg_rom.len > 0) (self.bank * 0x8000 + (addr % 0x8000)) % self.prg_rom.len else null,
            else => null,
        };
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            return switch (address) {
                0x0000...0x1FFF => self.chr_rom[addr],
                0x2000...0x3FFF => self.vram[addr],
                0x8000...0xFFFF => self.prg_rom[addr],
                else => @truncate(address & 0xff),
            };
        } else {
            return @truncate(address & 0xff);
        }
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        switch (address) {
            0x8000...0xFFFF => {
                self.bank = value & 0x7;
                self.page2 = value & 0x10 > 0;
            },
            else => if (self.convertAddress(address)) |addr| {
                switch (address) {
                    0x0000...0x1FFF => {
                        self.chr_rom[addr] = value;
                    },
                    0x2000...0x3FFF => {
                        self.vram[addr] = value;
                    },
                    else => {},
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

        if (self.chr_ram) |chr| {
            c.mpack_write_cstr(pack, "chr_ram");
            c.mpack_start_bin(pack, @intCast(chr.len));
            c.mpack_write_bytes(pack, chr.ptr, chr.len);
            c.mpack_finish_bin(pack);
        }

        c.mpack_write_cstr(pack, "mirroring");
        c.mpack_write_u8(pack, @intFromEnum(self.mirroring));
        c.mpack_write_cstr(pack, "bank");
        c.mpack_write_u32(pack, @truncate(self.bank));
        c.mpack_write_cstr(pack, "page2");
        c.mpack_write_bool(pack, self.page2);

        c.mpack_complete_map(pack);
    }

    fn deserialize(ctx: *anyopaque, pack: c.mpack_node_t) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        @memset(self.vram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "vram"), self.vram.ptr, self.vram.len);

        if (self.chr_ram) |chr| {
            @memset(chr, 0);
            _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "chr_ram"), chr.ptr, chr.len);
        }

        self.mirroring = @enumFromInt(c.mpack_node_u8(c.mpack_node_map_cstr(pack, "mirroring")));
        self.bank = c.mpack_node_u32(c.mpack_node_map_cstr(pack, "bank"));
        self.page2 = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "page2"));
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
