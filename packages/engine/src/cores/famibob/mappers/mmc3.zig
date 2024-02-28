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

    fn jsonParse(ctx: *anyopaque, value: std.json.Value) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        @memset(self.vram, 0);
        for (value.object.get("vram").?.array.items, 0..) |v, i| {
            self.vram[i] = @intCast(v.integer);
        }

        @memset(self.prg_ram, 0);
        for (value.object.get("prg_ram").?.array.items, 0..) |v, i| {
            self.prg_ram[i] = @intCast(v.integer);
        }

        if (self.chr_ram) |chr| {
            @memset(chr, 0);
            for (value.object.get("chr_ram").?.array.items, 0..) |v, i| {
                chr[i] = @intCast(v.integer);
            }
        }

        self.mirroring = @enumFromInt(value.object.get("mirroring").?.integer);
        self.prev_a12 = @intCast(value.object.get("prev_a12").?.integer);
        self.irq_counter = @intCast(value.object.get("irq_counter").?.integer);
        self.irq_latch = @intCast(value.object.get("irq_latch").?.integer);
        self.irq_reload = value.object.get("irq_reload").?.bool;
        self.irq_enabled = value.object.get("irq_enabled").?.bool;
        self.irq_occurred = value.object.get("irq_occurred").?.bool;
        self.control = @intCast(value.object.get("control").?.integer);
        self.r0 = @intCast(value.object.get("r0").?.integer);
        self.r1 = @intCast(value.object.get("r1").?.integer);
        self.r2 = @intCast(value.object.get("r2").?.integer);
        self.r3 = @intCast(value.object.get("r3").?.integer);
        self.r4 = @intCast(value.object.get("r4").?.integer);
        self.r5 = @intCast(value.object.get("r5").?.integer);
        self.r6 = @intCast(value.object.get("r6").?.integer);
        self.r7 = @intCast(value.object.get("r7").?.integer);
    }

    fn jsonStringify(ctx: *anyopaque, allocator: std.mem.Allocator) !std.json.Value {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        var data = std.json.ObjectMap.init(allocator);

        try data.put("mirroring", .{ .integer = @intFromEnum(self.mirroring) });
        try data.put("vram", .{ .string = self.vram });
        try data.put("prg_ram", .{ .string = self.prg_ram });

        try data.put("prev_a12", .{ .integer = @as(i64, @intCast(self.prev_a12)) });
        try data.put("irq_counter", .{ .integer = @as(i64, @intCast(self.irq_counter)) });
        try data.put("irq_latch", .{ .integer = @as(i64, @intCast(self.irq_latch)) });
        try data.put("irq_reload", .{ .bool = self.irq_reload });
        try data.put("irq_enabled", .{ .bool = self.irq_enabled });
        try data.put("irq_occurred", .{ .bool = self.irq_occurred });
        try data.put("control", .{ .integer = @as(i64, @intCast(self.control)) });
        try data.put("r0", .{ .integer = @as(i64, @intCast(self.r0)) });
        try data.put("r1", .{ .integer = @as(i64, @intCast(self.r1)) });
        try data.put("r2", .{ .integer = @as(i64, @intCast(self.r2)) });
        try data.put("r3", .{ .integer = @as(i64, @intCast(self.r3)) });
        try data.put("r4", .{ .integer = @as(i64, @intCast(self.r4)) });
        try data.put("r5", .{ .integer = @as(i64, @intCast(self.r5)) });
        try data.put("r6", .{ .integer = @as(i64, @intCast(self.r6)) });
        try data.put("r7", .{ .integer = @as(i64, @intCast(self.r7)) });

        if (self.chr_ram) |arr| {
            try data.put("chr_ram", .{ .string = arr });
        } else {
            try data.put("chr_ram", .null);
        }

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
