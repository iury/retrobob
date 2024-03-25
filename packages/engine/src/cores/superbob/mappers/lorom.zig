const std = @import("std");
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;
const c = @import("../../../c.zig");

pub const LoROM = struct {
    allocator: std.mem.Allocator,
    rom: []u8,
    sram: []u8,
    openbus: *u8,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge, openbus: *u8) !*@This() {
        std.debug.print("Mapper: LoROM\n", .{});
        const instance = try allocator.create(LoROM);
        instance.* = .{
            .allocator = allocator,
            .rom = cartridge.rom_data,
            .sram = try allocator.alloc(u8, cartridge.ram_size),
            .openbus = openbus,
        };
        @memset(instance.sram, 0);
        return instance;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.sram);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn convertAddress(self: *@This(), address: u24) ?usize {
        return switch (@as(u8, @truncate(address >> 16))) {
            0x00...0x3f => switch (@as(u16, @truncate(address & 0xffff))) {
                // IO
                0x0000...0x7fff => address & 0xffff,
                // mirror ROM
                0x8000...0xffff => ((address >> 16) * 0x8000) + (address & 0x7fff),
            },
            // mirror ROM
            0x40...0x6f => ((address >> 16) * 0x8000) + (address & 0x7fff),
            0x70...0x7d => switch (@as(u16, @truncate(address & 0xffff))) {
                // SRAM
                0x0000...0x7fff => if (self.sram.len > 0) (((address >> 16) - 0x70) * 0x8000) + (address & 0x7fff) else ((address >> 16) * 0x8000) + (address & 0x7fff),
                // mirror ROM
                0x8000...0xffff => ((address >> 16) * 0x8000) + (address & 0x7fff),
            },
            0x80...0xbf => switch (@as(u16, @truncate(address & 0xffff))) {
                // IO
                0x0000...0x7fff => address & 0xffff,
                // ROM
                0x8000...0xffff => (((address >> 16) - 0x80) * 0x8000) + (address & 0x7fff),
            },
            // ROM
            0xc0...0xef => (((address >> 16) - 0x80) * 0x8000) + (address & 0x7fff),
            0xf0...0xff => switch (@as(u16, @truncate(address & 0xffff))) {
                // SRAM
                0x0000...0x7fff => if (self.sram.len > 0) (((address >> 16) - 0xf0) * 0x8000) + (address & 0x7fff) else (((address >> 16) - 0x80) * 0x8000) + (address & 0x7fff),
                // ROM
                0x8000...0xffff => (((address >> 16) - 0x80) * 0x8000) + (address & 0x7fff),
            },
            // WRAM
            0x7e, 0x7f => null,
        };
    }

    fn readIO(self: *@This(), address: usize) u8 {
        return switch (address) {
            else => self.openbus.*,
        };
    }

    fn writeIO(self: *@This(), address: usize, value: u8) void {
        _ = self;
        _ = value;
        return switch (address) {
            else => {},
        };
    }

    pub fn read(ctx: *anyopaque, address: u24) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            return switch (@as(u8, @truncate(address >> 16))) {
                0x00...0x3f => switch (@as(u16, @truncate(address & 0xffff))) {
                    0x0000...0x7fff => self.readIO(addr),
                    0x8000...0xffff => self.rom[addr % self.rom.len],
                },
                0x40...0x6f => self.rom[addr % self.rom.len],
                0x70...0x7d => switch (@as(u16, @truncate(address & 0xffff))) {
                    0x0000...0x7fff => if (self.sram.len > 0) self.sram[addr % self.sram.len] else self.rom[addr % self.rom.len],
                    0x8000...0xffff => self.rom[addr % self.rom.len],
                },
                0x80...0xbf => switch (@as(u16, @truncate(address & 0xffff))) {
                    0x0000...0x7fff => self.readIO(addr),
                    0x8000...0xffff => self.rom[addr % self.rom.len],
                },
                0xc0...0xef => self.rom[addr % self.rom.len],
                0xf0...0xff => switch (@as(u16, @truncate(address & 0xffff))) {
                    0x0000...0x7fff => if (self.sram.len > 0) self.sram[addr % self.sram.len] else self.rom[addr % self.rom.len],
                    0x8000...0xffff => self.rom[addr % self.rom.len],
                },
                0x7e, 0x7f => self.openbus.*,
            };
        }
        return self.openbus.*;
    }

    pub fn write(ctx: *anyopaque, address: u24, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            switch (@as(u8, @truncate(address >> 16))) {
                0x00...0x3f => switch (@as(u16, @truncate(address & 0xffff))) {
                    0x0000...0x7fff => self.writeIO(addr, value),
                    else => {},
                },
                0x40...0x6f => {},
                0x70...0x7d => switch (@as(u16, @truncate(address & 0xffff))) {
                    0x0000...0x7fff => {
                        if (self.sram.len > 0) self.sram[addr % self.sram.len] = value;
                    },
                    0x8000...0xffff => {},
                },
                0x80...0xbf => switch (@as(u16, @truncate(address & 0xffff))) {
                    0x0000...0x7fff => self.writeIO(addr, value),
                    0x8000...0xffff => {},
                },
                0xc0...0xef => {},
                0xf0...0xff => switch (@as(u16, @truncate(address & 0xffff))) {
                    0x0000...0x7fff => {
                        if (self.sram.len > 0) self.sram[addr % self.sram.len] = value;
                    },
                    0x8000...0xffff => {},
                },
                0x7e, 0x7f => {},
            }
        }
    }

    fn serialize(ctx: *const anyopaque, pack: *c.mpack_writer_t) void {
        const self: *const @This() = @ptrCast(@alignCast(ctx));
        c.mpack_build_map(pack);
        c.mpack_write_cstr(pack, "sram");
        c.mpack_start_bin(pack, @intCast(self.sram.len));
        c.mpack_write_bytes(pack, self.sram.ptr, self.sram.len);
        c.mpack_finish_bin(pack);
        c.mpack_complete_map(pack);
    }

    fn deserialize(ctx: *anyopaque, pack: c.mpack_node_t) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        @memset(self.sram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "sram"), self.sram.ptr, self.sram.len);
    }

    pub fn memory(self: *@This()) Memory(u24, u8) {
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
