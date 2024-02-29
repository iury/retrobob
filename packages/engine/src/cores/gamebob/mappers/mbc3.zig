const std = @import("std");
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;
const RTC = @import("rtc.zig").RTC;

const RTCData = struct {
    subseconds: u16 = 0,
    seconds: u8 = 0,
    minutes: u8 = 0,
    hours: u8 = 0,
    day: u16 = 0,
    dh: u8 = 0,
};

pub const MBC3 = struct {
    allocator: std.mem.Allocator,
    rom: []u8,
    ram: []u8,

    ram_enable: bool,
    rom_bank: u8,
    ram_bank: u8,
    has_rtc: bool,
    rtc_data: RTCData,
    rtc_latch: RTCData,
    latch: u8 = 0,

    pub fn init(allocator: std.mem.Allocator, cartridge: *Cartridge, has_rtc: bool) !*@This() {
        std.debug.print("Mapper: MBC3\n", .{});
        const instance = try allocator.create(MBC3);
        instance.* = .{
            .allocator = allocator,
            .rom = cartridge.rom_data,
            .ram = try allocator.alloc(u8, cartridge.ram_size),
            .ram_enable = false,
            .rom_bank = 1,
            .ram_bank = 0,
            .has_rtc = has_rtc,
            .rtc_data = .{},
            .rtc_latch = .{},
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
            0xa000...0xbfff => |addr| if (self.ram_bank < 4) ((@as(usize, self.ram_bank) * 0x2000) | (addr - 0xa000)) else null,
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
        } else if (self.ram_bank >= 4) {
            return switch (self.ram_bank) {
                8 => self.rtc_latch.seconds,
                9 => self.rtc_latch.minutes,
                10 => self.rtc_latch.hours,
                11 => @intCast(self.rtc_latch.day & 0xff),
                12 => self.rtc_latch.dh,
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
                0x2000...0x3fff => {
                    self.rom_bank = if (value > 1) value else 1;
                },
                0x4000...0x5fff => {
                    self.ram_bank = if (self.has_rtc) value else (value & 3);
                },
                0x6000...0x7fff => {
                    if (value == 1 and self.latch == 0) self.rtc_latch = self.rtc_data;
                    self.latch = value;
                },
                0xa000...0xbfff => {
                    if (self.ram_enable and self.ram.len > 0) self.ram[addr % self.ram.len] = value;
                },
                else => {},
            }
        } else if (self.ram_bank >= 4) {
            switch (self.ram_bank) {
                8 => {
                    self.rtc_data.seconds = value & 0x3f;
                    self.rtc_data.subseconds = 0;
                },
                9 => self.rtc_data.minutes = value & 0x3f,
                10 => self.rtc_data.hours = value & 0x1f,
                11 => {
                    self.rtc_data.day &= 0x100;
                    self.rtc_data.day |= value;
                },
                12 => {
                    self.rtc_data.day &= 0xff;
                    self.rtc_data.day |= @as(u16, value & 1) << 8;
                    self.rtc_data.dh = value & 0xc1;
                },
                else => {},
            }
        }
    }

    fn tick(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if ((self.rtc_data.dh & 0x40) == 0) {
            self.rtc_data.subseconds += 1;
            if (self.rtc_data.subseconds == 512) {
                self.rtc_data.subseconds = 0;
                self.rtc_data.seconds += 1;
                if (self.rtc_data.seconds > 0x3f) self.rtc_data.seconds = 0;
                if (self.rtc_data.seconds == 60) {
                    self.rtc_data.seconds = 0;
                    self.rtc_data.minutes += 1;
                    if (self.rtc_data.minutes > 0x3f) self.rtc_data.minutes = 0;
                    if (self.rtc_data.minutes == 60) {
                        self.rtc_data.minutes = 0;
                        self.rtc_data.hours += 1;
                        if (self.rtc_data.hours > 0x1f) self.rtc_data.hours = 0;
                        if (self.rtc_data.hours == 24) {
                            self.rtc_data.hours = 0;
                            self.rtc_data.day += 1;
                            if (self.rtc_data.day > 255) {
                                self.rtc_data.dh |= 1;
                            }
                            if (self.rtc_data.day == 512) {
                                self.rtc_data.day = 0;
                                self.rtc_data.dh |= 0x80;
                                self.rtc_data.dh &= 0xfe;
                            }
                        }
                    }
                }
            }
        }
    }

    fn jsonParse(ctx: *anyopaque, value: std.json.Value) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        @memset(self.ram, 0);
        for (value.object.get("ram").?.array.items, 0..) |v, i| {
            self.ram[i] = @intCast(v.integer);
        }

        self.ram_enable = value.object.get("ram_enable").?.bool;
        self.rom_bank = @intCast(value.object.get("rom_bank").?.integer);
        self.ram_bank = @intCast(value.object.get("ram_bank").?.integer);
        self.latch = @intCast(value.object.get("latch").?.integer);

        const rtc_data = value.object.get("rtc_data").?.object;
        self.rtc_data.subseconds = @intCast(rtc_data.get("subseconds").?.integer);
        self.rtc_data.seconds = @intCast(rtc_data.get("seconds").?.integer);
        self.rtc_data.minutes = @intCast(rtc_data.get("minutes").?.integer);
        self.rtc_data.hours = @intCast(rtc_data.get("hours").?.integer);
        self.rtc_data.day = @intCast(rtc_data.get("day").?.integer);
        self.rtc_data.dh = @intCast(rtc_data.get("dh").?.integer);

        const rtc_latch = value.object.get("rtc_latch").?.object;
        self.rtc_latch.subseconds = @intCast(rtc_latch.get("subseconds").?.integer);
        self.rtc_latch.seconds = @intCast(rtc_latch.get("seconds").?.integer);
        self.rtc_latch.minutes = @intCast(rtc_latch.get("minutes").?.integer);
        self.rtc_latch.hours = @intCast(rtc_latch.get("hours").?.integer);
        self.rtc_latch.day = @intCast(rtc_latch.get("day").?.integer);
        self.rtc_latch.dh = @intCast(rtc_latch.get("dh").?.integer);
    }

    fn jsonStringify(ctx: *anyopaque, allocator: std.mem.Allocator) !std.json.Value {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        var data = std.json.ObjectMap.init(allocator);

        try data.put("ram", .{ .string = self.ram });
        try data.put("ram_enable", .{ .bool = self.ram_enable });
        try data.put("rom_bank", .{ .integer = self.rom_bank });
        try data.put("ram_bank", .{ .integer = self.ram_bank });
        try data.put("latch", .{ .integer = self.ram_bank });

        var rtc_data = std.json.ObjectMap.init(allocator);
        try rtc_data.put("subseconds", .{ .integer = self.rtc_data.subseconds });
        try rtc_data.put("seconds", .{ .integer = self.rtc_data.seconds });
        try rtc_data.put("minutes", .{ .integer = self.rtc_data.minutes });
        try rtc_data.put("hours", .{ .integer = self.rtc_data.hours });
        try rtc_data.put("day", .{ .integer = self.rtc_data.day });
        try rtc_data.put("dh", .{ .integer = self.rtc_data.dh });
        try data.put("rtc_data", .{ .object = rtc_data });

        var rtc_latch = std.json.ObjectMap.init(allocator);
        try rtc_latch.put("subseconds", .{ .integer = self.rtc_latch.subseconds });
        try rtc_latch.put("seconds", .{ .integer = self.rtc_latch.seconds });
        try rtc_latch.put("minutes", .{ .integer = self.rtc_latch.minutes });
        try rtc_latch.put("hours", .{ .integer = self.rtc_latch.hours });
        try rtc_latch.put("day", .{ .integer = self.rtc_latch.day });
        try rtc_latch.put("dh", .{ .integer = self.rtc_latch.dh });
        try data.put("rtc_latch", .{ .object = rtc_latch });

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

    pub fn rtc(self: *@This()) RTC {
        return .{
            .ptr = self,
            .vtable = &.{
                .tick = tick,
            },
        };
    }
};
