const std = @import("std");
const IO = @import("io.zig").IO;
const Memory = @import("../../memory.zig").Memory;
const c = @import("../../c.zig");

pub const MemoryBus = struct {
    allocator: std.mem.Allocator,

    ie: u8 = 0,
    svbk: u8 = 1,
    iflags: u8 = 0xe1,
    key1: u8 = 0x7e,
    wram: []u8,
    hiram: []u8,

    ppu: Memory(u16, u8),
    apu: Memory(u16, u8),
    input: Memory(u16, u8),
    timer: Memory(u16, u8),
    mapper: Memory(u16, u8),

    pub fn init(allocator: std.mem.Allocator) !*MemoryBus {
        var instance = try allocator.create(MemoryBus);

        instance.* = .{
            .allocator = allocator,
            .hiram = try allocator.alloc(u8, 160),
            .wram = try allocator.alloc(u8, 32768),
            .ppu = undefined,
            .apu = undefined,
            .input = undefined,
            .timer = undefined,
            .mapper = undefined,
        };

        var rnd = std.rand.DefaultPrng.init(@bitCast(std.time.timestamp()));
        const random = rnd.random();
        for (0..instance.wram.len) |i| {
            instance.wram[i] = random.int(u8);
        }

        return instance;
    }

    pub fn deinit(self: *MemoryBus) void {
        self.allocator.free(self.hiram);
        self.allocator.free(self.wram);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    pub fn read(ctx: *anyopaque, address: u16) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        return switch (address) {
            0x0000...0x7fff, 0xa000...0xbfff => self.mapper.read(address),

            0x8000...0x9fff, 0xfe00...0xfe9f => self.ppu.read(address),

            0xc000...0xcfff => self.wram[address - 0xc000],

            0xd000...0xdfff => self.wram[@as(usize, self.svbk) * 0x1000 + (address - 0xd000)],

            0xe000...0xfdff => self.wram[address - 0xe000],

            0xfea0...0xfeff => @as(u8, @intCast((address & 0xf0) | ((address & 0xf0) >> 4))),

            0xff00...0xff7f => switch (address) {
                @intFromEnum(IO.P1) => self.input.read(address),

                @intFromEnum(IO.DIV),
                @intFromEnum(IO.TMA),
                @intFromEnum(IO.TIMA),
                @intFromEnum(IO.TAC),
                => self.timer.read(address),

                @intFromEnum(IO.LCDC),
                @intFromEnum(IO.STAT),
                @intFromEnum(IO.SCY),
                @intFromEnum(IO.SCX),
                @intFromEnum(IO.LY),
                @intFromEnum(IO.LYC),
                @intFromEnum(IO.DMA),
                @intFromEnum(IO.BGP),
                @intFromEnum(IO.OBP0),
                @intFromEnum(IO.OBP1),
                @intFromEnum(IO.WY),
                @intFromEnum(IO.WX),
                @intFromEnum(IO.OPRI),
                @intFromEnum(IO.KEY0),
                @intFromEnum(IO.VBK),
                @intFromEnum(IO.HDMA1),
                @intFromEnum(IO.HDMA2),
                @intFromEnum(IO.HDMA3),
                @intFromEnum(IO.HDMA4),
                @intFromEnum(IO.HDMA5),
                @intFromEnum(IO.BCPD),
                @intFromEnum(IO.OCPD),
                @intFromEnum(IO.BCPS),
                @intFromEnum(IO.OCPS),
                => self.ppu.read(address),

                0xff30...0xff3f,
                @intFromEnum(IO.NR10),
                @intFromEnum(IO.NR11),
                @intFromEnum(IO.NR12),
                @intFromEnum(IO.NR13),
                @intFromEnum(IO.NR14),
                @intFromEnum(IO.NR21),
                @intFromEnum(IO.NR22),
                @intFromEnum(IO.NR23),
                @intFromEnum(IO.NR24),
                @intFromEnum(IO.NR30),
                @intFromEnum(IO.NR31),
                @intFromEnum(IO.NR32),
                @intFromEnum(IO.NR33),
                @intFromEnum(IO.NR34),
                @intFromEnum(IO.NR41),
                @intFromEnum(IO.NR42),
                @intFromEnum(IO.NR43),
                @intFromEnum(IO.NR44),
                @intFromEnum(IO.NR50),
                @intFromEnum(IO.NR51),
                @intFromEnum(IO.NR52),
                => self.apu.read(address),

                @intFromEnum(IO.IF) => self.iflags,
                @intFromEnum(IO.KEY1) => self.key1,
                @intFromEnum(IO.SVBK) => 0xf8 | self.svbk,

                else => 0xff,
            },

            0xff80...0xfffe => self.hiram[address - 0xff80],
            0xffff => self.ie,
        };
    }

    pub fn write(ctx: *anyopaque, address: u16, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        switch (address) {
            0x0000...0x7fff, 0xa000...0xbfff => self.mapper.write(address, value),

            0x8000...0x9fff, 0xfe00...0xfe9f => self.ppu.write(address, value),

            0xc000...0xcfff => self.wram[address - 0xc000] = value,

            0xd000...0xdfff => self.wram[@as(usize, self.svbk) * 0x1000 + (address - 0xd000)] = value,

            0xe000...0xfdff => self.wram[address - 0xe000] = value,

            0xfea0...0xfeff => {},

            0xff00...0xff7f => {
                switch (address) {
                    @intFromEnum(IO.P1) => self.input.write(address, value),

                    @intFromEnum(IO.DIV),
                    @intFromEnum(IO.TMA),
                    @intFromEnum(IO.TIMA),
                    @intFromEnum(IO.TAC),
                    => self.timer.write(address, value),

                    @intFromEnum(IO.LCDC),
                    @intFromEnum(IO.STAT),
                    @intFromEnum(IO.SCY),
                    @intFromEnum(IO.SCX),
                    @intFromEnum(IO.LY),
                    @intFromEnum(IO.LYC),
                    @intFromEnum(IO.DMA),
                    @intFromEnum(IO.BGP),
                    @intFromEnum(IO.OBP0),
                    @intFromEnum(IO.OBP1),
                    @intFromEnum(IO.WY),
                    @intFromEnum(IO.WX),
                    @intFromEnum(IO.OPRI),
                    @intFromEnum(IO.KEY0),
                    @intFromEnum(IO.VBK),
                    @intFromEnum(IO.HDMA1),
                    @intFromEnum(IO.HDMA2),
                    @intFromEnum(IO.HDMA3),
                    @intFromEnum(IO.HDMA4),
                    @intFromEnum(IO.HDMA5),
                    @intFromEnum(IO.BCPD),
                    @intFromEnum(IO.OCPD),
                    @intFromEnum(IO.BCPS),
                    @intFromEnum(IO.OCPS),
                    => self.ppu.write(address, value),

                    0xff30...0xff3f,
                    @intFromEnum(IO.NR10),
                    @intFromEnum(IO.NR11),
                    @intFromEnum(IO.NR12),
                    @intFromEnum(IO.NR13),
                    @intFromEnum(IO.NR14),
                    @intFromEnum(IO.NR21),
                    @intFromEnum(IO.NR22),
                    @intFromEnum(IO.NR23),
                    @intFromEnum(IO.NR24),
                    @intFromEnum(IO.NR30),
                    @intFromEnum(IO.NR31),
                    @intFromEnum(IO.NR32),
                    @intFromEnum(IO.NR33),
                    @intFromEnum(IO.NR34),
                    @intFromEnum(IO.NR41),
                    @intFromEnum(IO.NR42),
                    @intFromEnum(IO.NR43),
                    @intFromEnum(IO.NR44),
                    @intFromEnum(IO.NR50),
                    @intFromEnum(IO.NR51),
                    @intFromEnum(IO.NR52),
                    => self.apu.write(address, value),

                    @intFromEnum(IO.IF) => self.iflags = 0xe0 | (value & 0x1f),
                    @intFromEnum(IO.KEY1) => self.key1 = 0x7e | value,
                    @intFromEnum(IO.SVBK) => self.svbk = if (value & 7 > 1) (value & 7) else 1,

                    else => {},
                }
            },

            0xff80...0xfffe => self.hiram[address - 0xff80] = value,
            0xffff => self.ie = value,
        }
    }

    pub fn reset(self: *MemoryBus) void {
        self.ie = 0;
        self.svbk = 1;
        self.iflags = 0xe1;
        self.key1 = 0x7e;
        @memset(self.hiram, 0xff);
    }

    pub fn serialize(self: *const MemoryBus, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "ie");
        c.mpack_write_u8(pack, self.ie);
        c.mpack_write_cstr(pack, "svbk");
        c.mpack_write_u8(pack, self.svbk);
        c.mpack_write_cstr(pack, "iflags");
        c.mpack_write_u8(pack, self.iflags);
        c.mpack_write_cstr(pack, "key1");
        c.mpack_write_u8(pack, self.key1);

        c.mpack_write_cstr(pack, "hiram");
        c.mpack_start_bin(pack, @intCast(self.hiram.len));
        c.mpack_write_bytes(pack, self.hiram.ptr, self.hiram.len);
        c.mpack_finish_bin(pack);

        c.mpack_write_cstr(pack, "wram");
        c.mpack_start_bin(pack, @intCast(self.wram.len));
        c.mpack_write_bytes(pack, self.wram.ptr, self.wram.len);
        c.mpack_finish_bin(pack);

        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *MemoryBus, pack: c.mpack_node_t) void {
        @memset(self.hiram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "hiram"), self.hiram.ptr, self.hiram.len);

        @memset(self.wram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "wram"), self.wram.ptr, self.wram.len);

        self.ie = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "ie"));
        self.svbk = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "svbk"));
        self.iflags = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "iflags"));
        self.key1 = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "key1"));
    }

    pub fn memory(self: *MemoryBus) Memory(u16, u8) {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinitMemory,
            },
        };
    }
};
