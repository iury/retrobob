const std = @import("std");
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;

pub const ROMOnly = struct {
    allocator: std.mem.Allocator,
    rom: []u8,
    ram: []u8,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge) !*@This() {
        std.debug.print("Mapper: ROM Only\n", .{});
        const instance = try allocator.create(ROMOnly);
        instance.* = .{
            .allocator = allocator,
            .rom = cartridge.rom_data,
            .ram = try allocator.alloc(u8, cartridge.ram_size),
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
            0x0000...0x7fff => |addr| addr % self.rom.len,
            0xa000...0xbfff => |addr| if (self.ram.len > 0) (addr - 0xa000) % self.ram.len else null,
            else => null,
        };
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            return switch (address) {
                0x0000...0x7fff => self.rom[addr],
                0xa000...0xbfff => self.ram[addr],
                else => 0,
            };
        }
        return 0;
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.convertAddress(address)) |addr| {
            switch (address) {
                0xa000...0xbfff => {
                    self.ram[addr] = value;
                },
                else => {},
            }
        }
    }

    fn jsonParse(ctx: *anyopaque, value: std.json.Value) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        @memset(self.ram, 0);
        for (value.object.get("ram").?.array.items, 0..) |v, i| {
            self.ram[i] = @intCast(v.integer);
        }
    }

    fn jsonStringify(ctx: *anyopaque, allocator: std.mem.Allocator) !std.json.Value {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        var data = std.json.ObjectMap.init(allocator);
        try data.put("ram", .{ .string = self.ram });
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
