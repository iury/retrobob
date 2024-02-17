// UxROM Mapper (iNES ID 002)
//
// PRG capacity: 256K / 4096K
// PRG ROM window: 16K + 16K fixed
// PRG RAM: none
// CHR capacity: 8K
// CHR window: n/a
// Nametable mirroring: fixed vertical or horizontal mirroring
//
// CPU $8000-$BFFF: 16 KB switchable PRG ROM bank
// CPU $C000-$FFFF: 16 KB PRG ROM bank, fixed to the last bank

const std = @import("std");
const Mirroring = @import("../famibob.zig").Mirroring;
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;

pub const UxROM = struct {
    allocator: std.mem.Allocator,
    mirroring: Mirroring,
    vram: []u8,
    prg_rom: []u8,
    chr_rom: []u8,
    chr_ram: ?[]u8 = null,
    bank: usize = 0,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge) !*@This() {
        std.debug.print("Mapper: UxROM\n", .{});
        const instance = try allocator.create(UxROM);

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
            0x8000...0xBFFF => |addr| if (self.prg_rom.len > 0) self.bank * 0x4000 + (addr % 0x8000) else null,
            0xC000...0xFFFF => |addr| if (self.prg_rom.len > 0) self.prg_rom.len - 0x4000 + (addr % 0xC000) else null,
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
                0x0000...0x1FFF => self.chr_rom[addr],
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
            0x8000...0xFFFF => {
                self.bank = value;
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
                        else => {},
                    }
                }
            },
        }
    }

    fn jsonParse(ctx: *anyopaque, allocator: std.mem.Allocator, value: std.json.Value) !void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        const vram = try std.json.parseFromValueLeaky([]u8, allocator, value.object.get("vram").?, .{});
        @memcpy(self.vram, vram);

        if (self.chr_ram != null) {
            const chr_ram = try std.json.parseFromValueLeaky([]u8, allocator, value.object.get("chr_ram").?, .{});
            @memcpy(self.chr_ram.?, chr_ram);
        }

        self.mirroring = @enumFromInt(value.object.get("mirroring").?.integer);
        self.bank = @intCast(value.object.get("bank").?.integer);
    }

    fn jsonStringify(ctx: *anyopaque, allocator: std.mem.Allocator) !std.json.Value {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        var data = std.json.ObjectMap.init(allocator);

        try data.put("mirroring", .{ .integer = @intFromEnum(self.mirroring) });
        try data.put("vram", .{ .string = self.vram });

        try data.put("bank", .{ .integer = @as(i64, @intCast(self.bank)) });

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
