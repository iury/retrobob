const std = @import("std");
const Cartridge = @import("../cartridge.zig").Cartridge;
const Memory = @import("../../../memory.zig").Memory;
const RTC = @import("rtc.zig").RTC;
const c = @import("../../../c.zig");

const RTCData = packed struct {
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
        c.mpack_write_u8(pack, self.rom_bank);
        c.mpack_write_cstr(pack, "ram_bank");
        c.mpack_write_u8(pack, self.ram_bank);
        c.mpack_write_cstr(pack, "latch");
        c.mpack_write_u8(pack, self.latch);
        c.mpack_write_cstr(pack, "rtc_latch");
        c.mpack_write_u64(pack, @bitCast(self.rtc_latch));
        c.mpack_write_cstr(pack, "rtc_data");
        c.mpack_write_u64(pack, @bitCast(self.rtc_data));

        c.mpack_complete_map(pack);
    }

    fn deserialize(ctx: *anyopaque, pack: c.mpack_node_t) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        @memset(self.ram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "ram"), self.ram.ptr, self.ram.len);

        self.ram_enable = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "ram_enable"));
        self.rom_bank = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "rom_bank"));
        self.ram_bank = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ram_bank"));
        self.latch = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "latch"));
        self.rtc_latch = @bitCast(c.mpack_node_u64(c.mpack_node_map_cstr(pack, "rtc_latch")));
        self.rtc_data = @bitCast(c.mpack_node_u64(c.mpack_node_map_cstr(pack, "rtc_data")));
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

    pub fn rtc(self: *@This()) RTC {
        return .{
            .ptr = self,
            .vtable = &.{
                .tick = tick,
            },
        };
    }
};
