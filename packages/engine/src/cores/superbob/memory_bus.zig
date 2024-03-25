const std = @import("std");
const IO = @import("io.zig").IO;
const Memory = @import("../../memory.zig").Memory;
const c = @import("../../c.zig");

pub const MemoryBus = struct {
    allocator: std.mem.Allocator,
    wram: []u8,
    memsel: bool = false,
    ppu: Memory(u24, u8),
    apu: Memory(u24, u8),
    input: Memory(u24, u8),
    mapper: Memory(u24, u8),
    dma: Memory(u24, u8),

    openbus: u8 = 0,

    // 2181h, 2182h, 2183h
    wmadd: u17 = 0,

    // multiplication and division registers
    wrmpya: u8 = 0,
    wrdiv: u16 = 0,
    rddiv: u16 = 0,
    rdmpy: u16 = 0,

    pub fn init(allocator: std.mem.Allocator) !*MemoryBus {
        const instance = try allocator.create(MemoryBus);

        instance.* = .{
            .allocator = allocator,
            .wram = try allocator.alloc(u8, 0x20000),
            .ppu = undefined,
            .apu = undefined,
            .input = undefined,
            .mapper = undefined,
            .dma = undefined,
        };

        var rnd = std.rand.DefaultPrng.init(@bitCast(std.time.timestamp()));
        const random = rnd.random();
        for (0..instance.wram.len) |i| {
            instance.wram[i] = @max(1, random.int(u8));
        }

        return instance;
    }

    pub fn deinit(self: *MemoryBus) void {
        self.allocator.free(self.wram);
        self.allocator.destroy(self);
    }

    pub fn deinitMemory(ctx: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn readIO(self: *MemoryBus, address: u24) u8 {
        const addr = address & 0xffff;
        return switch (addr) {
            0x2134...0x213f, 0x4210...0x4212 => self.ppu.read(addr),
            0x2140...0x217f => self.apu.read(0x2140 + (addr % 4)),
            0x4016, 0x4017, 0x4213, 0x4218...0x421f => self.input.read(addr),
            0x4300...0x437f => self.dma.read(addr),
            @intFromEnum(IO.RDDIVH) => @intCast(self.rddiv >> 8),
            @intFromEnum(IO.RDDIVL) => @intCast(self.rddiv & 0xff),
            @intFromEnum(IO.RDMPYH) => @intCast(self.rdmpy >> 8),
            @intFromEnum(IO.RDMPYL) => @intCast(self.rdmpy & 0xff),

            @intFromEnum(IO.WMDATA) => blk: {
                const v = self.wram[self.wmadd];
                self.wmadd +%= 1;
                break :blk v;
            },

            else => self.mapper.read(addr),
        };
    }

    fn writeIO(self: *MemoryBus, address: u24, value: u8) void {
        const addr = address & 0xffff;
        switch (addr) {
            0x4200, 0x4201, 0x4207...0x420a, 0x2100...0x2133 => self.ppu.write(addr, value),
            0x2140...0x217f => self.apu.write(0x2140 + (addr % 4), value),
            0x4016 => self.input.write(addr, value),
            0x420b, 0x420c, 0x4300...0x437f => self.dma.write(addr, value),

            @intFromEnum(IO.WMDATA) => {
                self.wram[self.wmadd] = value;
                self.wmadd +%= 1;
            },

            @intFromEnum(IO.WMADDL) => {
                self.wmadd &= 0x1ff00;
                self.wmadd |= value;
            },

            @intFromEnum(IO.WMADDM) => {
                self.wmadd &= 0x100ff;
                self.wmadd |= @as(u16, value) << 8;
            },

            @intFromEnum(IO.WMADDH) => {
                self.wmadd &= 0x0ffff;
                self.wmadd |= @as(u17, value & 1) << 16;
            },

            @intFromEnum(IO.WRMPYA) => self.wrmpya = value,

            @intFromEnum(IO.WRMPYB) => self.rdmpy = @as(u16, self.wrmpya) *% @as(u16, value),

            @intFromEnum(IO.WRDIVL) => {
                self.wrdiv &= 0xff00;
                self.wrdiv |= value;
            },

            @intFromEnum(IO.WRDIVH) => {
                self.wrdiv &= 0x00ff;
                self.wrdiv |= @as(u16, value) << 8;
            },

            @intFromEnum(IO.WRDIVB) => {
                if (value == 0) {
                    self.rddiv = 0xffff;
                    self.rdmpy = self.wrdiv;
                } else {
                    self.rddiv = self.wrdiv / value;
                    self.rdmpy = self.wrdiv % value;
                }
            },

            @intFromEnum(IO.MEMSEL) => self.memsel = (value & 1) == 1,

            else => self.mapper.write(addr, value),
        }
    }

    pub fn read(ctx: *anyopaque, address: u24) u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const v: u8 = switch (@as(u8, @truncate(address >> 16))) {
            0x00...0x3f => switch (@as(u16, @truncate(address & 0xffff))) {
                0x0000...0x1fff => self.wram[address & 0x1fff],
                0x2000...0x20ff => self.openbus,
                0x2100...0x21ff => self.readIO(address),
                0x2200...0x3fff => self.openbus,
                0x4000...0x7fff => self.readIO(address),
                0x8000...0xffff => self.mapper.read(address),
            },
            0x40...0x7d => self.mapper.read(address),
            0x7e, 0x7f => self.wram[address - 0x7e0000],
            0x80...0xbf => switch (@as(u16, @truncate(address & 0xffff))) {
                0x0000...0x1fff => self.wram[address & 0x1fff],
                0x2000...0x20ff => self.openbus,
                0x2100...0x21ff => self.readIO(address),
                0x2200...0x3fff => self.openbus,
                0x4000...0x7fff => self.readIO(address),
                0x8000...0xffff => self.mapper.read(address),
            },
            0xc0...0xff => self.mapper.read(address),
        };
        self.openbus = v;
        return v;
    }

    pub fn write(ctx: *anyopaque, address: u24, value: u8) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.openbus = value;
        switch (@as(u8, @truncate(address >> 16))) {
            0x00...0x3f => switch (@as(u16, @truncate(address & 0xffff))) {
                0x0000...0x1fff => self.wram[address & 0x1fff] = value,
                0x2000...0x20ff => {},
                0x2100...0x21ff => self.writeIO(address, value),
                0x2200...0x3fff => {},
                0x4000...0x7fff => self.writeIO(address, value),
                0x8000...0xffff => self.mapper.write(address, value),
            },
            0x40...0x7d => self.mapper.write(address, value),
            0x7e, 0x7f => self.wram[address - 0x7e0000] = value,
            0x80...0xbf => switch (@as(u16, @truncate(address & 0xffff))) {
                0x0000...0x1fff => self.wram[address & 0x1fff] = value,
                0x2000...0x20ff => {},
                0x2100...0x21ff => self.writeIO(address, value),
                0x2200...0x3fff => {},
                0x4000...0x7fff => self.writeIO(address, value),
                0x8000...0xffff => self.mapper.write(address, value),
            },
            0xc0...0xff => self.mapper.write(address, value),
        }
    }

    pub fn reset(self: *MemoryBus) void {
        self.memsel = false;
        self.wmadd = 0;
    }

    pub fn serialize(self: *const MemoryBus, pack: *c.mpack_writer_t) void {
        c.mpack_build_map(pack);

        c.mpack_write_cstr(pack, "wram");
        c.mpack_start_bin(pack, @intCast(self.wram.len));
        c.mpack_write_bytes(pack, self.wram.ptr, self.wram.len);
        c.mpack_finish_bin(pack);

        c.mpack_write_cstr(pack, "memsel");
        c.mpack_write_bool(pack, self.memsel);
        c.mpack_write_cstr(pack, "wmadd");
        c.mpack_write_u32(pack, self.wmadd);
        c.mpack_write_cstr(pack, "wrmpya");
        c.mpack_write_u8(pack, self.wrmpya);
        c.mpack_write_cstr(pack, "wrdiv");
        c.mpack_write_u16(pack, self.wrdiv);
        c.mpack_write_cstr(pack, "rddiv");
        c.mpack_write_u16(pack, self.rddiv);
        c.mpack_write_cstr(pack, "rdmpy");
        c.mpack_write_u16(pack, self.rdmpy);

        c.mpack_complete_map(pack);
    }

    pub fn deserialize(self: *MemoryBus, pack: c.mpack_node_t) void {
        @memset(self.wram, 0);
        _ = c.mpack_node_copy_data(c.mpack_node_map_cstr(pack, "wram"), self.wram.ptr, self.wram.len);
        self.memsel = c.mpack_node_bool(c.mpack_node_map_cstr(pack, "memsel"));
        self.wmadd = @as(u17, @truncate(c.mpack_node_u32(c.mpack_node_map_cstr(pack, "wmadd"))));
        self.wrmpya = c.mpack_node_u8(c.mpack_node_map_cstr(pack, "wrmpya"));
        self.wrdiv = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "wrdiv"));
        self.rddiv = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "rddiv"));
        self.rdmpy = c.mpack_node_u16(c.mpack_node_map_cstr(pack, "rdmpy"));
    }

    pub fn memory(self: *MemoryBus) Memory(u24, u8) {
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
