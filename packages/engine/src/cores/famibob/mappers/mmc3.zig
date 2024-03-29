// MMC3 Mapper (iNES ID 004)
//
// PRG capacity: 512K
// PRG ROM window: 8K + 8K + 16K fixed
// PRG RAM: 8K
// CHR capacity: 256K
// CHR window: 2Kx2 + 1Kx4
// Nametable mirroring: H or V, switchable, or 4 fixed
//
// PPU $0000-$07FF (or $1000-$17FF): 2 KB switchable CHR bank
// PPU $0800-$0FFF (or $1800-$1FFF): 2 KB switchable CHR bank
// PPU $1000-$13FF (or $0000-$03FF): 1 KB switchable CHR bank
// PPU $1400-$17FF (or $0400-$07FF): 1 KB switchable CHR bank
// PPU $1800-$1BFF (or $0800-$0BFF): 1 KB switchable CHR bank
// PPU $1C00-$1FFF (or $0C00-$0FFF): 1 KB switchable CHR bank
// CPU $6000-$7FFF: 8 KB PRG RAM bank (optional)
// CPU $8000-$9FFF (or $C000-$DFFF): 8 KB switchable PRG ROM bank
// CPU $A000-$BFFF: 8 KB switchable PRG ROM bank
// CPU $C000-$DFFF (or $8000-$9FFF): 8 KB PRG ROM bank, fixed to the second-last bank
// CPU $E000-$FFFF: 8 KB PRG ROM bank, fixed to the last bank

const std = @import("std");
const Mirroring = @import("../famibob.zig").Mirroring;
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;
const c = @import("../../../c.zig");

pub const MMC3 = struct {
    allocator: std.mem.Allocator,
    mirroring: Mirroring,

    vram: []u8,
    prg_rom: []u8,
    chr_rom: []u8,
    chr_ram: ?[]u8 = null,
    prg_ram: []u8,

    prev_a12: u8 = 0,
    irq_counter: u8 = 0,
    irq_latch: u8 = 0,
    irq_reload: bool = false,
    irq_enabled: bool = false,
    irq_occurred: bool = false,

    control: u8 = 0,
    r0: u8 = 0,
    r1: u8 = 0,
    r2: u8 = 0,
    r3: u8 = 0,
    r4: u8 = 0,
    r5: u8 = 0,
    r6: u8 = 0,
    r7: u8 = 0,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge) !*@This() {
        std.debug.print("Mapper: MMC2\n", .{});
        const instance = try allocator.create(MMC3);

        var chr_ram: ?[]u8 = null;
        var chr_rom: []u8 = cartridge.chr_data;
        if (chr_rom.len == 0) {
            chr_rom = try allocator.alloc(u8, @max(cartridge.chr_ram_size, 0x40000));
            chr_ram = chr_rom;
        }

        instance.* = .{
            .allocator = allocator,
            .mirroring = cartridge.mirroring,
            .vram = try allocator.alloc(u8, if (cartridge.mirroring == .four_screen) 0x2000 else 0x800),
            .prg_rom = cartridge.prg_data,
            .chr_rom = chr_rom,
            .chr_ram = chr_ram,
            .prg_ram = try allocator.alloc(u8, cartridge.prg_ram_size),
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
            0x0000...0x1FFF => |addr| blk: {
                self.checkA12(address);

                if (self.chr_rom.len == 0) break :blk null;
                var v: usize = addr % 0x0400;

                if (self.control & 0x80 == 0) {
                    v += 0x0400 * @as(usize, switch (addr) {
                        0x0000...0x03FF => self.r0,
                        0x0400...0x07FF => self.r0 + 1,
                        0x0800...0x0BFF => self.r1,
                        0x0C00...0x0FFF => self.r1 + 1,
                        0x1000...0x13FF => self.r2,
                        0x1400...0x17FF => self.r3,
                        0x1800...0x1BFF => self.r4,
                        0x1C00...0x1FFF => self.r5,
                        else => 0,
                    });
                } else {
                    v += 0x0400 * @as(usize, switch (addr) {
                        0x0000...0x03FF => self.r2,
                        0x0400...0x07FF => self.r3,
                        0x0800...0x0BFF => self.r4,
                        0x0C00...0x0FFF => self.r5,
                        0x1000...0x13FF => self.r0,
                        0x1400...0x17FF => self.r0 + 1,
                        0x1800...0x1BFF => self.r1,
                        0x1C00...0x1FFF => self.r1 + 1,
                        else => 0,
                    });
                }

                break :blk v % self.chr_rom.len;
            },

            0x8000...0xFFFF => |addr| blk: {
                if (self.prg_rom.len == 0) break :blk null;
                var v: usize = addr % 0x2000;

                if (self.control & 0x40 == 0) {
                    v += 0x2000 * @as(usize, switch (addr) {
                        0x8000...0x9FFF => self.r6,
                        0xA000...0xBFFF => self.r7,
                        0xC000...0xDFFF => @intCast(self.prg_rom.len / 0x2000 - 2),
                        0xE000...0xFFFF => @intCast(self.prg_rom.len / 0x2000 - 1),
                        else => 0,
                    });
                } else {
                    v += 0x2000 * @as(usize, switch (addr) {
                        0x8000...0x9FFF => @intCast(self.prg_rom.len / 0x2000 - 2),
                        0xA000...0xBFFF => self.r7,
                        0xC000...0xDFFF => self.r6,
                        0xE000...0xFFFF => @intCast(self.prg_rom.len / 0x2000 - 1),
                        else => 0,
                    });
                }

                break :blk v % self.prg_rom.len;
            },

            0x6000...0x7FFF => |addr| if (self.prg_ram.len > 0) addr % 0x2000 % self.prg_ram.len else null,

            0x2000...0x3FFF => |addr| switch (self.mirroring) {
                .horizontal => (addr & 0x3FF) | ((addr & 0x800) >> 1),
                .vertical => addr & 0x7FF,
                .four_screen => addr & 0x1FFF,
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
                else => 0,
            };
        } else {
            return 0;
        }
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        switch (address) {
            0x8000...0x9FFF => {
                if (address % 2 == 0) {
                    self.control = value;
                } else {
                    switch (self.control & 0x7) {
                        0 => {
                            self.r0 = value & 0xFE;
                        },
                        1 => {
                            self.r1 = value & 0xFE;
                        },
                        2 => {
                            self.r2 = value;
                        },
                        3 => {
                            self.r3 = value;
                        },
                        4 => {
                            self.r4 = value;
                        },
                        5 => {
                            self.r5 = value;
                        },
                        6 => {
                            self.r6 = value & 0x3F;
                        },
                        7 => {
                            self.r7 = value & 0x3F;
                        },
                        else => {},
                    }
                }
            },
            0xA000...0xBFFE => {
                if (address % 2 == 0) {
                    if (self.mirroring != .four_screen) {
                        self.mirroring = if (value & 1 == 0) .vertical else .horizontal;
                    }
                }
            },
            0xC000...0xDFFF => {
                if (address % 2 == 0) {
                    self.irq_latch = value;
                } else {
                    self.irq_counter = 0;
                    self.irq_reload = true;
                }
            },
            0xE000...0xFFFF => {
                if (address % 2 == 0) {
                    self.irq_enabled = false;
                    self.irq_occurred = false;
                } else {
                    self.irq_enabled = true;
                }
            },
            else => {
                if (self.convertAddress(address)) |addr| {
                    switch (address) {
                        0x0000...0x1FFF => {
                            self.chr_rom[addr] = value;
                        },
                        0x2000...0x3FFF => {
                            self.vram[addr] = value;
                        },
                        0x6000...0x7FFF => {
                            self.prg_ram[addr] = value;
                        },
                        else => {},
                    }
                }
            },
        }
    }

    fn checkA12(self: *@This(), address: u16) void {
        if ((address & 0x1000) > 0 and self.prev_a12 == 0) self.a12Trigger();
        self.prev_a12 = if ((address & 0x1000) > 0) 1 else 0;
    }

    fn a12Trigger(self: *@This()) void {
        if (self.irq_counter == 0 or self.irq_reload) {
            self.irq_reload = false;
            self.irq_counter = self.irq_latch;
        } else {
            self.irq_counter -%= 1;
        }

        if (self.irq_counter == 0 and self.irq_enabled) {
            self.irq_occurred = true;
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
        c.mpack_write_cstr(pack, "prev_a12");
        c.mpack_write_u8(pack, self.prev_a12);
        c.mpack_write_cstr(pack, "irq_counter");
        c.mpack_write_u8(pack, self.irq_counter);
        c.mpack_write_cstr(pack, "irq_latch");
        c.mpack_write_u8(pack, self.irq_latch);
        c.mpack_write_cstr(pack, "irq_reload");
        c.mpack_write_bool(pack, self.irq_reload);
        c.mpack_write_cstr(pack, "irq_enabled");
        c.mpack_write_bool(pack, self.irq_enabled);
        c.mpack_write_cstr(pack, "irq_occurred");
        c.mpack_write_bool(pack, self.irq_occurred);
        c.mpack_write_cstr(pack, "control");
        c.mpack_write_u8(pack, self.control);
        c.mpack_write_cstr(pack, "r0");
        c.mpack_write_u8(pack, self.r0);
        c.mpack_write_cstr(pack, "r1");
        c.mpack_write_u8(pack, self.r1);
        c.mpack_write_cstr(pack, "r2");
        c.mpack_write_u8(pack, self.r2);
        c.mpack_write_cstr(pack, "r3");
        c.mpack_write_u8(pack, self.r3);
        c.mpack_write_cstr(pack, "r4");
        c.mpack_write_u8(pack, self.r4);
        c.mpack_write_cstr(pack, "r5");
        c.mpack_write_u8(pack, self.r5);
        c.mpack_write_cstr(pack, "r6");
        c.mpack_write_u8(pack, self.r6);
        c.mpack_write_cstr(pack, "r7");
        c.mpack_write_u8(pack, self.r7);

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
        self.prev_a12 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "prev_a12"));
        self.irq_counter = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "irq_counter"));
        self.irq_latch = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "irq_latch"));
        self.irq_reload = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "irq_reload"));
        self.irq_enabled = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "irq_enabled"));
        self.irq_occurred = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "irq_occurred"));
        self.control = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "control"));
        self.r0 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "r0"));
        self.r1 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "r1"));
        self.r2 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "r2"));
        self.r3 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "r3"));
        self.r4 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "r4"));
        self.r5 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "r5"));
        self.r6 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "r6"));
        self.r7 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "r7"));
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
