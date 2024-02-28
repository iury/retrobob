// CNROM Mapper (iNES ID 003)
//
// PRG capacity: 16K or 32K
// PRG ROM window: n/a
// PRG RAM: none
// CHR ROM capacity: 32K
// CHR ROM window: 8K
// Nametable mirroring: fixed vertical or horizontal mirroring
//
// PPU $0000-$1FFF: 8 KB switchable CHR ROM bank

const std = @import("std");
const Mirroring = @import("../famibob.zig").Mirroring;
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;

pub const CNROM = struct {
    allocator: std.mem.Allocator,
    mirroring: Mirroring,
    vram: []u8,
    prg_rom: []u8,
    chr_rom: []u8,
    bank: usize = 0,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge) !*@This() {
        std.debug.print("Mapper: CNROM\n", .{});
        const instance = try allocator.create(CNROM);
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
            0x0000...0x1FFF => |addr| if (self.chr_rom.len > 0) (self.bank * 0x2000 + addr) % self.chr_rom.len else null,
            0x8000...0xFFFF => |addr| if (self.prg_rom.len > 0) addr % self.prg_rom.len else null,
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
            0x2000...0x3FFF => {
                if (self.convertAddress(address)) |addr| self.vram[addr] = value;
            },
            0x8000...0xFFFF => {
                self.bank = value & 0xF;
            },
            else => {},
        }
    }

    fn jsonParse(ctx: *anyopaque, value: std.json.Value) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        @memset(self.vram, 0);
        for (value.object.get("vram").?.array.items, 0..) |v, i| {
            self.vram[i] = @intCast(v.integer);
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
