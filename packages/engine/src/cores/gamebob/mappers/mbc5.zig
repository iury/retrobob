const std = @import("std");
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;
const c = @import("../../../c.zig");

pub const MBC5 = struct {
    allocator: std.mem.Allocator,
    rom: []u8,
    ram: []u8,

    ram_enable: bool,
    rom_bank: u16,
    ram_bank: u8,
    rumble: bool,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge, rumble: bool) !*@This() {
        std.debug.print("Mapper: MBC5\n", .{});
        const instance = try allocator.create(MBC5);
        instance.* = .{
            .allocator = allocator,
            .rom = cartridge.rom_data,
            .ram = try allocator.alloc(u8, cartridge.ram_size),
            .ram_enable = false,
            .rom_bank = 1,
            .ram_bank = 0,
            .rumble = rumble,
        };
        @memset(instance.ram, 0);
        return instance;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.ram);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn convertAddress(self: *@This(), address: u16) ?usize {
        return switch (address) {
            0x0000...0x3fff => |addr| addr,
            0x4000...0x7fff => |addr| (@as(usize, self.rom_bank) * 0x4000) | (addr - 0x4000),
            0xa000...0xbfff => |addr| (@as(usize, self.ram_bank) * 0x2000) | (addr - 0xa000),
            else => null,
        };
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            return switch (address) {
                0x0000...0x7fff => self.rom[addr % self.rom.len],
                0xa000...0xbfff => if (self.ram_enable and self.ram.len > 0) self.ram[addr % self.ram.len] else 0xff,
                else => 0xff,
            };
        }
        return 0xff;
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            switch (address) {
                0x0000...0x1fff => {
                    self.ram_enable = (value & 0xf) == 0xa;
                },
                0x2000...0x2fff => {
                    self.rom_bank &= 0x100;
                    self.rom_bank |= value;
                },
                0x3000...0x3fff => {
                    self.rom_bank &= 0xff;
                    self.rom_bank |= @as(u16, value & 1) << 8;
                },
                0x4000...0x5fff => {
                    if (self.rumble) {
                        self.ram_bank = value & 7;
                    } else {
                        self.ram_bank = value & 0xf;
                    }
                },
                0xa000...0xbfff => {
                    if (self.ram_enable and self.ram.len > 0) {
                        self.ram[addr % self.ram.len] = value;
                    }
                },
                else => {},
            }
        }
    }

    fn serialize(ctx: *const anyopaque, pack: *c.mpack_writer_t) void {
        const self: *const @This() = @ptrCast(@alignCast(ctx));
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "ram");
        c.mpack_start_bin(pack, @intCast(self.ram.len));
        c.mpack_write_bytes(pack, self.ram.ptr, self.ram.len);
        c.mpack_finish_bin(pack);

        c.mpack_write_cstr(pack, "ram_enable");
        c.mpack_write_bool(pack, self.ram_enable);
        c.mpack_write_cstr(pack, "rom_bank");
        c.mpack_write_u16(pack, self.rom_bank);
        c.mpack_write_cstr(pack, "ram_bank");
        c.mpack_write_u8(pack, self.ram_bank);

        c.mpack_complete_map(pack);
    }

    fn deserialize(ctx: *anyopaque, pack: c.mpack_node_t) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        @memset(self.ram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "ram"), self.ram.ptr, self.ram.len);

        self.ram_enable = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "ram_enable"));
        self.rom_bank = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "rom_bank"));
        self.ram_bank = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ram_bank"));
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
